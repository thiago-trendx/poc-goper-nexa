import 'dart:async';
import 'dart:math' as math;

import 'machine_exception.dart';
import 'machine_gateway.dart';
import 'models/connection_event.dart';
import 'models/control_snapshot.dart';
import 'models/device_info.dart';
import 'models/device_params.dart';
import 'models/device_status.dart';
import 'models/enums.dart';
import 'models/firmware_event.dart';
import 'models/lift_motor_event.dart';
import 'models/machine_event.dart';
import 'models/params_ack_event.dart';

enum _LiftActivity { none, adjusting, selfChecking }

/// Gateway falso que simula a máquina 850, para desenvolver e testar UI e Blocs sem hardware.
///
/// Comportamento simulado (não é o do controlador real):
/// - o status só é emitido enquanto o polling está ativo, a cada `intervalMs`;
/// - em `STOP` a força é a `inactiveForce` e a máquina fica parada; em `RUNNING` força real e
///   curso variam de forma senoidal, com uma repetição a cada [repetitionPeriod];
/// - ajuste de posição e autoteste dos motores param o movimento antes, duram o tempo configurado
///   e emitem eventos `liftMotor`;
/// - o relógio do status é simulado (avança `intervalMs` por ciclo), o que torna os testes
///   determinísticos com `fakeAsync`.
///
/// Erros podem ser injetados com [injectErrorCode], [injectLiftMotorErrors], [failNextCommand],
/// [simulateDisconnect] e [autoConnectShouldFail].
class FakeMachineGateway implements MachineGateway {
  FakeMachineGateway({
    this.portPath = '/dev/ttyFAKE0',
    this.connectDelay = const Duration(milliseconds: 300),
    this.liftMotorAdjustDuration = const Duration(seconds: 4),
    this.selfCheckDuration = const Duration(seconds: 6),
    this.firmwareStepInterval = const Duration(milliseconds: 500),
    this.repetitionPeriod = const Duration(seconds: 3),
    DeviceParams? initialParams,
    DeviceInfo? deviceInfo,
  })  : _params = initialParams ?? defaultParams,
        _deviceInfo = deviceInfo ?? defaultDeviceInfo;

  /// Calibração inicial simulada.
  static const defaultParams = DeviceParams(
    minForce: 5,
    maxForce: 100,
    inactiveForce: 5,
    maxLength: 200,
    ratedSpeed: 1000,
    ropeGuideDiameter: 10,
    orginMinDistance: 5,
    orginMaxDistance: 50,
    velocityRange: 20,
    torqueVariationCycle: 50,
    torqueCoefficient: 10,
  );

  static const defaultDeviceInfo = DeviceInfo(
    softwareNum: 'FAKE-850',
    versionCode: 1,
    produceCode: 'FAKE0001',
  );

  /// Porta devolvida por `autoConnect` e usada em `reconnect`.
  final String portPath;
  final Duration connectDelay;
  final Duration liftMotorAdjustDuration;
  final Duration selfCheckDuration;
  final Duration firmwareStepInterval;
  final Duration repetitionPeriod;

  /// Quando `true`, o próximo `autoConnect` termina em evento `connection` com `failed`.
  bool autoConnectShouldFail = false;

  /// Quando `true`, ajuste e autoteste dos motores terminam com `timeout` em vez de `completed`.
  bool simulateLiftMotorTimeout = false;

  /// Quando informado, o controlador "devolve" estes valores em vez dos enviados em
  /// `sendDeviceParams` (simula um controlador que ajusta ou recusa campos).
  DeviceParams Function(DeviceParams sent)? ackFor;

  /// Quando `true`, `sendDeviceParams` é aceito mas o `paramsAck` nunca chega.
  bool dropParamsAck = false;

  static const _monotonicBaseMs = 1000000;
  static const _epochBaseMs = 1750000000000;
  static const _liftMargin = Duration(seconds: 4);

  final StreamController<MachineEvent> _controller = StreamController.broadcast();
  final DeviceInfo _deviceInfo;
  DeviceParams _params;

  /// Como no controle real, a força inicial é desconhecida/inválida: o app precisa defini-la.
  ControlSnapshot _control = const ControlSnapshot();
  int? _safetyMaxForceKg;

  bool _connected = false;
  bool _disposed = false;
  String? _currentPort;
  Timer? _connectTimer;

  Timer? _pollTimer;
  int _intervalMs = 200;
  int _simMs = 0;
  int _runMs = 0;
  int _pullOffset = 0;
  int _distance = 0;

  int _errorCode = 0;
  int _liftError1 = 0;
  int _liftError2 = 0;
  MachineException? _failNext;

  _LiftActivity _lift = _LiftActivity.none;
  Timer? _liftTimer;

  Timer? _firmwareTimer;
  bool _resumePollingAfterFirmware = false;

  // ---- Apoio a testes e à simulação de falhas ----

  ControlSnapshot get controlSnapshot => _control;
  DeviceParams get deviceParams => _params;
  bool get isConnected => _connected;
  bool get isPolling => _pollTimer != null;

  /// Faz o status passar a informar [code] em `errorCode` (0 = sem erro).
  void injectErrorCode(int code) => _errorCode = code;

  /// Faz o status passar a informar erros dos motores de elevação 1 e 2 (0 = sem erro).
  void injectLiftMotorErrors({int error1 = 0, int error2 = 0}) {
    _liftError1 = error1;
    _liftError2 = error2;
  }

  void clearInjectedErrors() {
    _errorCode = 0;
    _liftError1 = 0;
    _liftError2 = 0;
  }

  /// O próximo comando falha com [exception].
  void failNextCommand(MachineException exception) => _failNext = exception;

  /// Simula perda de conexão: para o polling e emite `connection` com [state].
  void simulateDisconnect({
    MachineConnectionState state = MachineConnectionState.disconnected,
    String? reason,
  }) {
    final port = _currentPort;
    _dropConnection();
    _emit(ConnectionEvent(state: state, portPath: port, reason: reason));
  }

  // ---- MachineGateway ----

  @override
  Stream<MachineEvent> get events => _controller.stream;

  @override
  Future<void> initialize({
    required String spFileName,
    int? baudRate,
    int? sendIntervalMs,
    int? testTimeMs,
    bool? logEnabled,
    int? maxForceKg,
  }) async {
    _precheck(needsConnection: false);
    if (spFileName.trim().isEmpty) {
      throw const MachineException(MachineErrorCode.invalidArgs, 'spFileName vazio');
    }
    if (maxForceKg != null && maxForceKg <= 0) {
      throw const MachineException(MachineErrorCode.invalidArgs, 'maxForceKg deve ser > 0');
    }
    _safetyMaxForceKg = maxForceKg;
  }

  @override
  Future<void> autoConnect() async {
    _precheck(needsConnection: false);
    final fail = autoConnectShouldFail;
    _scheduleConnection(portPath, fail: fail, reason: 'Nenhuma porta respondeu (simulado)');
  }

  @override
  Future<bool> connect(String portPath) async {
    _precheck(needsConnection: false);
    if (portPath.trim().isEmpty) {
      throw const MachineException(MachineErrorCode.invalidArgs, 'portPath vazio');
    }
    _scheduleConnection(portPath);
    return true;
  }

  @override
  Future<void> disconnect() async {
    _precheck(needsConnection: false);
    final port = _currentPort;
    _dropConnection();
    _emit(ConnectionEvent(state: MachineConnectionState.disconnected, portPath: port));
  }

  @override
  Future<void> reconnect() async {
    _precheck(needsConnection: false);
    _scheduleConnection(_currentPort ?? portPath);
  }

  @override
  Future<ConnectionInfo> getConnectionInfo() async {
    _precheck(needsConnection: false);
    final state = _connected
        ? PortState.connected
        : (_connectTimer?.isActive ?? false)
            ? PortState.scanning
            : PortState.idle;
    return ConnectionInfo(state: state, portPath: _connected ? _currentPort : null);
  }

  @override
  Future<void> startPolling({int intervalMs = 200}) async {
    _precheck();
    if (intervalMs <= 0) {
      throw const MachineException(MachineErrorCode.invalidArgs, 'intervalMs deve ser > 0');
    }
    _intervalMs = intervalMs;
    // Como o nativo: o polling sempre começa em STOP.
    _control = _control.copyWith(run: RunState.stop);
    _startPollTimer();
  }

  @override
  Future<void> stopPolling() async {
    _precheck(needsConnection: false);
    _pollTimer?.cancel();
    _pollTimer = null;
    // Sem polling a máquina não recebe mais ordens: o estado local volta a STOP.
    _control = _control.copyWith(run: RunState.stop);
    _abortLift();
  }

  @override
  Future<void> queryDeviceInfo() async {
    _precheck();
    Timer(Duration.zero, () => _emit(_deviceInfo));
  }

  @override
  Future<DeviceParams> getDeviceParams() async {
    _precheck(needsConnection: false);
    return _params;
  }

  @override
  Future<void> sendDeviceParams(DeviceParams params) async {
    _precheck();
    _requireStopped('enviar os parâmetros');
    final errors = params.validate();
    if (errors.isNotEmpty) {
      throw MachineException(
        MachineErrorCode.outOfRange,
        'Fora da faixa: ${errors.keys.map((f) => f.key).join(', ')}',
      );
    }
    final returned = ackFor?.call(params) ?? params;
    _params = returned; // o SDK também guarda no cache o que o controlador devolve
    if (!dropParamsAck) Timer(Duration.zero, () => _emit(ParamsAckEvent(returned)));
  }

  @override
  Future<ControlSnapshot> getControlParams() async {
    _precheck(needsConnection: false);
    return _control;
  }

  @override
  Future<void> start() async {
    _precheck();
    _requireLiftIdle();
    if (_pollTimer == null) {
      throw const MachineException(
        MachineErrorCode.sdkError,
        'Ligue o polling antes de iniciar: sem ele a máquina não recebe as ordens seguintes, inclusive o STOP',
      );
    }
    final problem = _forceProblem(_control.force);
    if (problem != null) {
      throw MachineException(
        MachineErrorCode.outOfRange,
        'A força atual (${_control.force} kg) não é válida: $problem. Defina a força antes de iniciar',
      );
    }
    _control = _control.copyWith(run: RunState.running);
  }

  @override
  Future<void> stop() async {
    _precheck();
    _control = _control.copyWith(run: RunState.stop);
  }

  @override
  Future<void> originReset() async {
    _precheck();
    _requireLiftIdle();
    _requireStopped('redefinir a origem');
    _distance = 0;
    _pullOffset = _runMs ~/ repetitionPeriod.inMilliseconds;
  }

  @override
  Future<void> errorRestore() async {
    _precheck();
    _requireLiftIdle();
    _requireStopped('restaurar erros');
    clearInjectedErrors();
  }

  @override
  Future<void> clearData(ClearMode mode) async {
    _precheck();
    _requireLiftIdle();
    if (mode == ClearMode.none) return;
    _pullOffset = _runMs ~/ repetitionPeriod.inMilliseconds;
  }

  @override
  Future<void> setForce(int kg) async {
    _precheck();
    final problem = _forceProblem(kg);
    if (problem != null) throw MachineException(MachineErrorCode.outOfRange, problem);
    _control = _control.copyWith(force: kg);
  }

  @override
  Future<void> setMode(ForceMode mode) async {
    _precheck();
    _control = _control.copyWith(mode: mode);
  }

  @override
  Future<void> setCoefficient(CoefficientKind kind, int value) async {
    _precheck();
    // Faixas do demo do fabricante (concêntrico/excêntrico 0–6, elástico 0–10); o isocinético vai de
    // 0 até o velocityRange da calibração (Javadoc).
    final max = switch (kind) {
      CoefficientKind.centripetal => 6,
      CoefficientKind.centrifugal => 6,
      CoefficientKind.elastic => 10,
      CoefficientKind.velocity => _params.velocityRange,
    };
    if (value < 0 || value > max) {
      throw MachineException(
        MachineErrorCode.outOfRange,
        'Coeficiente ${kind.name} deve estar entre 0 e $max',
      );
    }
    _control = switch (kind) {
      CoefficientKind.centripetal => _control.copyWith(centripetal: value),
      CoefficientKind.centrifugal => _control.copyWith(centrifugal: value),
      CoefficientKind.velocity => _control.copyWith(velocity: value),
      CoefficientKind.elastic => _control.copyWith(elastic: value),
    };
  }

  @override
  Future<void> setElasticMax(int value) async {
    _precheck();
    if (value < 1 || value > _params.maxLength) {
      throw MachineException(
        MachineErrorCode.outOfRange,
        'O curso elástico deve estar entre 1 e ${_params.maxLength}',
      );
    }
    _control = _control.copyWith(maxElectric: value);
  }

  @override
  Future<void> setSafeMode(SafeMode mode) async {
    _precheck();
    _control = _control.copyWith(safeMode: mode);
  }

  @override
  Future<void> setBalancingForce(int kg) async {
    _precheck();
    if (kg < 0 || kg > 25) {
      throw const MachineException(MachineErrorCode.outOfRange, 'Força deve estar entre 0 e 25 kg');
    }
    _control = _control.copyWith(balancingForce: kg);
  }

  @override
  Future<void> setMotorPosition({required int p1, required int p2}) async {
    _precheck();
    _requireLiftIdle();
    _requirePolling('ajustar a posição dos motores');
    if (p1 < 0 || p2 < 0) {
      throw const MachineException(MachineErrorCode.outOfRange, 'As posições dos motores devem ser >= 0');
    }
    if (p1 == _control.motorPosition1 && p2 == _control.motorPosition2) {
      throw MachineException(
        MachineErrorCode.invalidArgs,
        'Os motores já estão nas posições $p1 e $p2; nada a ajustar',
      );
    }
    _control = _control.copyWith(run: RunState.stop, motorPosition1: p1, motorPosition2: p2);
    _startLift(
      _LiftActivity.adjusting,
      duration: liftMotorAdjustDuration,
      remainingSec: (liftMotorAdjustDuration + _liftMargin).inSeconds,
    );
  }

  @override
  Future<void> startMotorSelfCheck({int timeoutSec = 130}) async {
    _precheck();
    _requireLiftIdle();
    _requirePolling('iniciar o autoteste');
    if (timeoutSec < 1 || timeoutSec > 600) {
      throw const MachineException(MachineErrorCode.outOfRange, 'timeoutSec deve estar entre 1 e 600');
    }
    // O Javadoc exige o movimento parado durante o autoteste.
    _control = _control.copyWith(run: RunState.stop, motorSelfCheck: true);
    _startLift(_LiftActivity.selfChecking, duration: selfCheckDuration, remainingSec: timeoutSec);
  }

  @override
  Future<void> installFirmware({
    required int type,
    required String filePath,
    int? timeoutMs,
  }) async {
    _precheck();
    _requireStopped('instalar o firmware');
    if (type != 1 && type != 2) {
      throw const MachineException(MachineErrorCode.invalidArgs, 'type deve ser 1 ou 2');
    }
    if (filePath.trim().isEmpty) {
      throw const MachineException(MachineErrorCode.invalidArgs, 'filePath vazio');
    }
    if (_firmwareTimer != null) {
      throw const MachineException(MachineErrorCode.busy, 'Instalação de firmware em andamento');
    }
    // A instalação pausa o polling e o retoma no final.
    _resumePollingAfterFirmware = _pollTimer != null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _emit(const FirmwareEvent(phase: FirmwarePhase.sending));
    var progress = 0;
    _firmwareTimer = Timer.periodic(firmwareStepInterval, (timer) {
      progress += 25;
      if (progress < 100) {
        _emit(FirmwareEvent(phase: FirmwarePhase.progress, progress: progress));
        return;
      }
      _emit(const FirmwareEvent(phase: FirmwarePhase.progress, progress: 100));
      _emit(const FirmwareEvent(phase: FirmwarePhase.success));
      _finishFirmware();
    });
  }

  @override
  Future<void> cancelFirmware() async {
    _precheck(needsConnection: false);
    if (_firmwareTimer == null) return;
    _emit(const FirmwareEvent(phase: FirmwarePhase.error, message: 'Instalação cancelada'));
    _finishFirmware();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _connectTimer?.cancel();
    _pollTimer?.cancel();
    _liftTimer?.cancel();
    _firmwareTimer?.cancel();
    await _controller.close();
  }

  // ---- Internos ----

  void _precheck({bool needsConnection = true}) {
    if (_disposed) throw StateError('FakeMachineGateway já foi descartado');
    final failure = _failNext;
    if (failure != null) {
      _failNext = null;
      throw failure;
    }
    if (needsConnection && !_connected) {
      throw const MachineException(MachineErrorCode.notConnected, 'Sem conexão com a máquina');
    }
  }

  /// Faixa de força permitida: de `minForce` a `maxForce` da calibração (como o demo do fabricante),
  /// e nunca acima do limite de segurança do app. Devolve a mensagem de problema ou `null`.
  String? _forceProblem(int kg) {
    final cap = _safetyMaxForceKg;
    final max = cap == null ? _params.maxForce : (cap < _params.maxForce ? cap : _params.maxForce);
    if (max < _params.minForce) {
      return 'o limite de segurança do app ($cap kg) está abaixo da força mínima da calibração (${_params.minForce} kg)';
    }
    if (kg < _params.minForce || kg > max) {
      final capNote = cap != null && cap < _params.maxForce ? ' (limite de segurança do app: $cap kg)' : '';
      return 'a força deve estar entre ${_params.minForce} e $max kg$capNote';
    }
    return null;
  }

  void _requireStopped(String action) {
    if (_control.run == RunState.running) {
      throw MachineException(MachineErrorCode.busy, 'Pare a máquina antes de $action');
    }
  }

  void _requirePolling(String action) {
    if (_pollTimer == null) {
      throw MachineException(
        MachineErrorCode.sdkError,
        'Ligue o polling antes de $action: o controlador só recebe as ordens pelo polling',
      );
    }
  }

  /// Como o nativo: sem polling ou sem conexão a operação dos motores é abortada e conta como
  /// `timeout`, para a tela não ficar esperando um evento que não virá.
  void _abortLift() {
    if (_lift == _LiftActivity.none) return;
    _liftTimer?.cancel();
    final wasSelfCheck = _lift == _LiftActivity.selfChecking;
    _lift = _LiftActivity.none;
    _control = _control.copyWith(run: RunState.stop, motorSelfCheck: wasSelfCheck ? false : null);
    _emit(const LiftMotorEvent(phase: LiftMotorPhase.timeout, remainingSec: 0));
  }

  void _requireLiftIdle() {
    if (_lift != _LiftActivity.none) {
      throw const MachineException(MachineErrorCode.busy, 'Motores de elevação em operação');
    }
  }

  void _emit(MachineEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  void _scheduleConnection(String path, {bool fail = false, String? reason}) {
    _connectTimer?.cancel();
    _connectTimer = Timer(connectDelay, () {
      if (fail) {
        _emit(ConnectionEvent(
          state: MachineConnectionState.failed,
          portPath: path,
          reason: reason ?? 'Falha simulada',
        ));
        return;
      }
      _connected = true;
      _currentPort = path;
      _emit(ConnectionEvent(state: MachineConnectionState.connected, portPath: path));
    });
  }

  void _dropConnection() {
    _connectTimer?.cancel();
    _pollTimer?.cancel();
    _pollTimer = null;
    _abortLift();
    if (_firmwareTimer != null) {
      _firmwareTimer!.cancel();
      _firmwareTimer = null;
    }
    _connected = false;
    _control = _control.copyWith(run: RunState.stop, motorSelfCheck: false);
  }

  void _startPollTimer() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(Duration(milliseconds: _intervalMs), (_) => _onTick());
  }

  void _onTick() {
    _simMs += _intervalMs;
    if (_control.run == RunState.running) _runMs += _intervalMs;
    _emit(_buildStatus());
  }

  DeviceStatus _buildStatus() {
    final running = _control.run == RunState.running;
    final periodMs = repetitionPeriod.inMilliseconds;
    final phase = 2 * math.pi * _runMs / periodMs;
    final halfTravel = _params.maxLength * 0.25;
    var speed = 0.0;
    int force;
    int realForce;
    if (running) {
      _distance = (halfTravel * (1 - math.cos(phase))).round();
      speed = halfTravel * math.sin(phase) * 2 * math.pi / (periodMs / 1000);
      force = _control.force;
      realForce = math.max(0, (force * (1 + 0.1 * math.sin(phase))).round());
    } else {
      force = _params.inactiveForce;
      realForce = force;
    }
    return DeviceStatus(
      run: _control.run,
      mode: _control.mode,
      force: force,
      realForce: realForce,
      speed: speed,
      distance: _distance,
      pullNum: math.max(0, _runMs ~/ periodMs - _pullOffset),
      errorCode: _errorCode,
      temperature: 35 + math.min(_simMs / 60000, 10),
      liftMotorStatus: switch (_lift) {
        _LiftActivity.none => 0x00,
        _LiftActivity.adjusting => 0x01,
        _LiftActivity.selfChecking => 0x02,
      },
      liftMotorError1: _liftError1,
      liftMotorError2: _liftError2,
      verityCodeError: 0x00,
      tsMonotonicMs: _monotonicBaseMs + _simMs,
      tsEpochMs: _epochBaseMs + _simMs,
    );
  }

  void _startLift(
    _LiftActivity activity, {
    required Duration duration,
    required int remainingSec,
  }) {
    _lift = activity;
    _emit(LiftMotorEvent(phase: LiftMotorPhase.started, remainingSec: remainingSec));
    _liftTimer = Timer(duration, () {
      final finished = activity;
      _lift = _LiftActivity.none;
      if (finished == _LiftActivity.selfChecking) {
        _control = _control.copyWith(motorSelfCheck: false);
      }
      _emit(LiftMotorEvent(
        phase: simulateLiftMotorTimeout ? LiftMotorPhase.timeout : LiftMotorPhase.completed,
        remainingSec: 0,
      ));
    });
  }

  void _finishFirmware() {
    _firmwareTimer?.cancel();
    _firmwareTimer = null;
    if (_resumePollingAfterFirmware && _connected) _startPollTimer();
    _resumePollingAfterFirmware = false;
  }
}
