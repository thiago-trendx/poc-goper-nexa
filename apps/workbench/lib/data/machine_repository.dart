import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';

/// Única dona do [MachineGateway]. Blocs e widgets falam só com o repositório,
/// que expõe os eventos do gateway em streams por tipo.
class MachineRepository {
  MachineRepository(this._gateway, {this.spFileName = 'workbench850_prefs', this.maxForceKg}) {
    _subscription = _gateway.events.listen(_events.add, onError: _eventErrors.add);
    connections.listen(_onConnection);
  }

  final MachineGateway _gateway;

  /// Nome do arquivo de SharedPreferences usado pelo SDK (`DeviceManager.init`).
  final String spFileName;

  /// Limite de força de segurança do app, repassado ao lado nativo para ele recusar força acima dele
  /// mesmo que haja um erro nesta camada.
  final int? maxForceKg;

  final StreamController<MachineEvent> _events = StreamController.broadcast();
  final StreamController<Object> _eventErrors = StreamController.broadcast();
  final StreamController<bool> _pollingStates = StreamController.broadcast();
  late final StreamSubscription<MachineEvent> _subscription;

  Future<void>? _initialization;
  bool _disposed = false;
  bool _connected = false;
  bool _polling = false;
  int _pollingIntervalMs = 200;

  Stream<T> _of<T extends MachineEvent>() => _events.stream.where((e) => e is T).cast<T>();

  Stream<ConnectionEvent> get connections => _of<ConnectionEvent>();
  Stream<DeviceStatus> get statuses => _of<DeviceStatus>();
  Stream<DeviceInfo> get deviceInfos => _of<DeviceInfo>();
  Stream<ParamsAckEvent> get paramsAcks => _of<ParamsAckEvent>();
  Stream<LiftMotorEvent> get liftMotorEvents => _of<LiftMotorEvent>();
  Stream<FirmwareEvent> get firmwareEvents => _of<FirmwareEvent>();
  Stream<LogEntry> get logs => _of<LogEntry>();

  /// Eventos malformados ou erros do canal de eventos.
  Stream<Object> get eventErrors => _eventErrors.stream;

  /// Mudanças do estado do polling (`true` = ativo).
  Stream<bool> get pollingStates => _pollingStates.stream;

  bool get isConnected => _connected;
  bool get isPolling => _polling;
  int get pollingIntervalMs => _pollingIntervalMs;

  void _onConnection(ConnectionEvent event) {
    _connected = event.state == MachineConnectionState.connected;
    if (!_connected) _setPolling(false);
  }

  void _setPolling(bool value) {
    if (_polling == value) return;
    _polling = value;
    _pollingStates.add(value);
  }

  /// `DeviceManager.init` só pode rodar uma vez: chamadas simultâneas compartilham a mesma
  /// inicialização, e uma falha permite tentar de novo.
  Future<void> _ensureInitialized() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    try {
      await _gateway.initialize(spFileName: spFileName, logEnabled: kDebugMode, maxForceKg: maxForceKg);
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  // ---- Conexão ----

  Future<void> autoConnect() async {
    await _ensureInitialized();
    await _gateway.autoConnect();
  }

  Future<bool> connect(String portPath) async {
    await _ensureInitialized();
    return _gateway.connect(portPath);
  }

  /// Manda STOP antes de desconectar: desconectar não pode deixar a máquina em execução.
  Future<void> disconnect() async {
    await haltForSafety();
    await _gateway.disconnect();
  }
  Future<void> reconnect() => _gateway.reconnect();
  Future<ConnectionInfo> getConnectionInfo() => _gateway.getConnectionInfo();

  Future<void> startPolling({int intervalMs = 200}) async {
    await _gateway.startPolling(intervalMs: intervalMs);
    _pollingIntervalMs = intervalMs;
    _setPolling(true);
  }

  Future<void> stopPolling() async {
    await _gateway.stopPolling();
    _setPolling(false);
  }

  Future<void> queryDeviceInfo() => _gateway.queryDeviceInfo();

  // ---- Parâmetros ----

  /// Parâmetros guardados no `DeviceManager` (cache local; o controlador não tem comando de leitura).
  /// Inicializa o SDK antes, porque o `DeviceManager` precisa do `init` para ler o cache.
  Future<DeviceParams> getDeviceParams() async {
    await _ensureInitialized();
    return _gateway.getDeviceParams();
  }

  /// Só por ação explícita do usuário: nada envia parâmetros ao conectar.
  Future<void> sendDeviceParams(DeviceParams params) async {
    await _ensureInitialized();
    await _gateway.sendDeviceParams(params);
  }
  Future<ControlSnapshot> getControlParams() async {
    await _ensureInitialized();
    return _gateway.getControlParams();
  }

  // ---- Controle ----

  Future<void> start() => _gateway.start();

  /// STOP de emergência: chamado direto pelo botão fixo, sem passar por fila de Bloc.
  Future<void> stop() => _gateway.stop();

  /// Envia `stop()` e depois para o polling (ao fechar o app, ir para segundo plano, desconectar
  /// ou desligar o polling pela tela Conexão).
  ///
  /// Espera dois ciclos de polling entre os dois passos para que o STOP chegue ao
  /// controlador antes de o envio periódico parar. Falhas são ignoradas: o objetivo é
  /// deixar a máquina parada mesmo com a conexão já perdida.
  Future<void> haltForSafety() async {
    try {
      await _gateway.stop();
      if (_polling) await Future<void>.delayed(Duration(milliseconds: _pollingIntervalMs * 2));
    } on MachineException {
      // Sem conexão ou sem resposta: não há mais o que enviar.
    }
    if (_disposed) return;
    try {
      await stopPolling();
    } on MachineException {
      // Idem.
    }
  }

  Future<void> originReset() => _gateway.originReset();
  Future<void> errorRestore() => _gateway.errorRestore();
  Future<void> clearData(ClearMode mode) => _gateway.clearData(mode);
  Future<void> setForce(int kg) => _gateway.setForce(kg);
  Future<void> setMode(ForceMode mode) => _gateway.setMode(mode);
  Future<void> setCoefficient(CoefficientKind kind, int value) =>
      _gateway.setCoefficient(kind, value);
  Future<void> setElasticMax(int value) => _gateway.setElasticMax(value);
  Future<void> setSafeMode(SafeMode mode) => _gateway.setSafeMode(mode);
  Future<void> setBalancingForce(int kg) => _gateway.setBalancingForce(kg);

  // ---- Motores de elevação ----

  Future<void> setMotorPosition({required int p1, required int p2}) =>
      _gateway.setMotorPosition(p1: p1, p2: p2);
  Future<void> startMotorSelfCheck({int timeoutSec = 130}) =>
      _gateway.startMotorSelfCheck(timeoutSec: timeoutSec);

  // ---- Firmware ----

  Future<void> installFirmware({required int type, required String filePath, int? timeoutMs}) =>
      _gateway.installFirmware(type: type, filePath: filePath, timeoutMs: timeoutMs);
  Future<void> cancelFirmware() => _gateway.cancelFirmware();

  Future<void> dispose() async {
    _disposed = true;
    // A fonte dos eventos é descartada primeiro: timers e polling do gateway param antes de
    // qualquer espera.
    final gatewayDisposal = _gateway.dispose();
    await _subscription.cancel();
    await gatewayDisposal;
    await _events.close();
    await _eventErrors.close();
    await _pollingStates.close();
  }
}
