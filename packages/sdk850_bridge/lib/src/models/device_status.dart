import 'enums.dart';
import 'machine_event.dart';

/// Status do controlador (resposta de `CONTROL`), evento `status`.
class DeviceStatus extends MachineEvent {
  const DeviceStatus({
    required this.run,
    required this.mode,
    required this.force,
    required this.realForce,
    required this.speed,
    required this.distance,
    required this.pullNum,
    required this.errorCode,
    required this.temperature,
    required this.liftMotorStatus,
    required this.liftMotorError1,
    required this.liftMotorError2,
    required this.verityCodeError,
    required this.tsMonotonicMs,
    required this.tsEpochMs,
  });

  factory DeviceStatus.fromMap(Map<String, Object?> map) => DeviceStatus(
        run: RunState.fromWire(map['run']),
        mode: ForceMode.fromWire(map['mode']),
        force: readInt(map, 'force'),
        realForce: readInt(map, 'realForce'),
        speed: readDouble(map, 'speed'),
        distance: readInt(map, 'distance'),
        pullNum: readInt(map, 'pullNum'),
        errorCode: readInt(map, 'errorCode'),
        temperature: readDouble(map, 'temperature'),
        liftMotorStatus: readInt(map, 'liftMotorStatus'),
        liftMotorError1: readInt(map, 'liftMotorError1'),
        liftMotorError2: readInt(map, 'liftMotorError2'),
        verityCodeError: readInt(map, 'verityCodeError'),
        tsMonotonicMs: readInt(map, 'tsMonotonicMs'),
        tsEpochMs: readInt(map, 'tsEpochMs'),
      );

  final RunState run;
  final ForceMode mode;

  /// Força configurada, em kg.
  final int force;

  /// Força real. A unidade não está documentada (o demo exibe em kg).
  final int realForce;

  /// Velocidade do cabo, em cm/s.
  final double speed;

  /// Curso, em cm.
  final int distance;
  final int pullNum;
  final int errorCode;

  /// Temperatura do controlador, em °C.
  final double temperature;

  /// 0x00 parado, 0x01 em movimento, 0x02 em autoteste.
  final int liftMotorStatus;

  /// 0x00 = sem erro.
  final int liftMotorError1;
  final int liftMotorError2;

  /// 0x00 = OK, 0xAA = erro.
  final int verityCodeError;

  /// `SystemClock.elapsedRealtime()` no momento do recebimento.
  final int tsMonotonicMs;
  final int tsEpochMs;

  bool get hasError => errorCode != 0;
  bool get hasLiftMotorError => liftMotorError1 != 0 || liftMotorError2 != 0;
  bool get verityCodeOk => verityCodeError == 0x00;
  bool get liftMotorMoving => liftMotorStatus == 0x01;
  bool get liftMotorSelfChecking => liftMotorStatus == 0x02;

  @override
  String get type => 'status';

  @override
  Map<String, Object?> toMap() => {
        'type': type,
        'run': run.wire,
        'mode': mode.wire,
        'force': force,
        'realForce': realForce,
        'speed': speed,
        'distance': distance,
        'pullNum': pullNum,
        'errorCode': errorCode,
        'temperature': temperature,
        'liftMotorStatus': liftMotorStatus,
        'liftMotorError1': liftMotorError1,
        'liftMotorError2': liftMotorError2,
        'verityCodeError': verityCodeError,
        'tsMonotonicMs': tsMonotonicMs,
        'tsEpochMs': tsEpochMs,
      };

  @override
  List<Object?> get props => [
        run,
        mode,
        force,
        realForce,
        speed,
        distance,
        pullNum,
        errorCode,
        temperature,
        liftMotorStatus,
        liftMotorError1,
        liftMotorError2,
        verityCodeError,
        tsMonotonicMs,
        tsEpochMs,
      ];
}
