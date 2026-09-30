import 'package:flutter_test/flutter_test.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';

const _status = DeviceStatus(
  run: RunState.running,
  mode: ForceMode.centripetal,
  force: 20,
  realForce: 21,
  speed: -12.5,
  distance: 48,
  pullNum: 7,
  errorCode: 3,
  temperature: 36.5,
  liftMotorStatus: 1,
  liftMotorError1: 0,
  liftMotorError2: 2,
  verityCodeError: 0,
  tsMonotonicMs: 123456,
  tsEpochMs: 1750000123456,
);

const _params = DeviceParams(
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

void main() {
  group('fromMap/toMap', () {
    final events = <String, MachineEvent>{
      'status': _status,
      'deviceInfo': const DeviceInfo(softwareNum: 'SW-1', versionCode: 41, produceCode: 'P-9'),
      'paramsAck': const ParamsAckEvent(_params),
      'connection (connected)': const ConnectionEvent(
        state: MachineConnectionState.connected,
        portPath: '/dev/ttyS3',
      ),
      'connection (failed)': const ConnectionEvent(
        state: MachineConnectionState.failed,
        portPath: '/dev/ttyS3',
        reason: 'timeout',
      ),
      'liftMotor': const LiftMotorEvent(phase: LiftMotorPhase.started, remainingSec: 130),
      'firmware (progress)': const FirmwareEvent(phase: FirmwarePhase.progress, progress: 40),
      'firmware (error)': const FirmwareEvent(phase: FirmwarePhase.error, message: 'falhou'),
      'log': const LogEntry(
        direction: LogDirection.tx,
        packetType: 'CONTROL',
        hex: 'AA55',
        tsEpochMs: 1750000000000,
      ),
    };

    for (final entry in events.entries) {
      test('${entry.key} sobrevive ao ciclo toMap -> fromMap', () {
        final map = entry.value.toMap();
        expect(map['type'], entry.value.type);
        expect(MachineEvent.fromMap(map), entry.value);
      });
    }

    test('aceita o Map<Object?, Object?> que o canal entrega', () {
      final Map<Object?, Object?> raw = Map<Object?, Object?>.from(_status.toMap());
      expect(MachineEvent.fromMap(raw), _status);
    });

    test('DeviceParams, ControlSnapshot e ConnectionInfo sobrevivem ao ciclo', () {
      expect(DeviceParams.fromMap(_params.toMap()), _params);
      const control = ControlSnapshot(
        run: RunState.running,
        mode: ForceMode.elastic,
        force: 15,
        centripetal: 1,
        centrifugal: 2,
        velocity: 3,
        elastic: 4,
        safeMode: SafeMode.protection,
        clearMode: ClearMode.second,
        motorPosition1: 2,
        motorPosition2: 3,
        motorSelfCheck: true,
        balancingForce: 10,
        maxElectric: 60,
        needSetOrigin: true,
        needErrorRestor: true,
      );
      expect(ControlSnapshot.fromMap(control.toMap()), control);
      const info = ConnectionInfo(state: PortState.connected, portPath: '/dev/ttyS3');
      expect(ConnectionInfo.fromMap(info.toMap()), info);
    });

    test('toMap usa o name() do enum Kotlin e o valor inteiro do safeMode', () {
      final map = const ControlSnapshot(
        run: RunState.originReset,
        clearMode: ClearMode.all,
        safeMode: SafeMode.fatigue,
      ).toMap();
      expect(map['run'], 'ORIGIN_RESET');
      expect(map['clearMode'], 'ALL');
      expect(map['safeMode'], 51);
    });

    test('ParamsAckEvent usa os campos de DeviceParams no mesmo nível do type', () {
      final map = const ParamsAckEvent(_params).toMap();
      expect(map['type'], 'paramsAck');
      expect(map['minForce'], 5);
      expect(map['orginMinDistance'], 5);
    });
  });

  group('entradas inválidas', () {
    test('type desconhecido', () {
      expect(() => MachineEvent.fromMap({'type': 'nope'}), throwsFormatException);
    });

    test('enum inválido', () {
      final map = _status.toMap()..['run'] = 'PAUSED';
      expect(() => MachineEvent.fromMap(map), throwsFormatException);
    });

    test('campo obrigatório ausente', () {
      final map = _status.toMap()..remove('force');
      expect(() => MachineEvent.fromMap(map), throwsFormatException);
    });

    test('campo com tipo errado', () {
      final map = _status.toMap()..['force'] = 'vinte';
      expect(() => MachineEvent.fromMap(map), throwsFormatException);
    });

    test('valor inválido de SafeMode', () {
      expect(() => SafeMode.fromValue(7), throwsFormatException);
    });
  });

  group('DeviceStatus', () {
    test('getters de conveniência', () {
      expect(_status.hasError, isTrue);
      expect(_status.hasLiftMotorError, isTrue);
      expect(_status.verityCodeOk, isTrue);
      expect(_status.liftMotorMoving, isTrue);
      expect(_status.liftMotorSelfChecking, isFalse);
    });
  });

  group('DeviceParams.validate', () {
    test('valores válidos não geram erro', () {
      expect(_params.validate(), isEmpty);
    });

    test('limites inferior e superior de cada campo são válidos', () {
      for (final field in DeviceParamField.values) {
        expect(_params.withField(field, field.min).validate(), isEmpty, reason: field.key);
        expect(_params.withField(field, field.max).validate(), isEmpty, reason: field.key);
      }
    });

    test('um passo fora da faixa gera erro só naquele campo', () {
      for (final field in DeviceParamField.values) {
        final below = _params.withField(field, field.min - 1).validate();
        final above = _params.withField(field, field.max + 1).validate();
        expect(below.keys, [field], reason: '${field.key} abaixo');
        expect(above.keys, [field], reason: '${field.key} acima');
      }
    });

    test('withField altera somente o campo pedido', () {
      for (final field in DeviceParamField.values) {
        final changed = _params.withField(field, field.max);
        expect(changed.valueOf(field), field.max);
        for (final other in DeviceParamField.values.where((f) => f != field)) {
          expect(changed.valueOf(other), _params.valueOf(other), reason: other.key);
        }
      }
    });

    test('faixas seguem o Javadoc', () {
      expect(DeviceParamField.minForce.rangeLabel, 'Entre 5 e 20 kg');
      expect(DeviceParamField.velocityRange.rangeLabel, 'Entre 0 e 50');
      expect(DeviceParamField.maxForce.max, 150);
      expect(DeviceParamField.ratedSpeed.max, 2000);
    });
  });

  test('ControlSnapshot.coefficient devolve o coeficiente certo', () {
    const control = ControlSnapshot(centripetal: 1, centrifugal: 2, velocity: 3, elastic: 4);
    expect(control.coefficient(CoefficientKind.centripetal), 1);
    expect(control.coefficient(CoefficientKind.centrifugal), 2);
    expect(control.coefficient(CoefficientKind.velocity), 3);
    expect(control.coefficient(CoefficientKind.elastic), 4);
  });
}
