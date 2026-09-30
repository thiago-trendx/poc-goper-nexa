import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methods = MethodChannel('sdk850_bridge/methods');
  const eventChannel = EventChannel('sdk850_bridge/events');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late MethodChannelGateway gateway;
  late List<MethodCall> calls;

  void mockMethods(Future<Object?> Function(MethodCall call)? handler) {
    messenger.setMockMethodCallHandler(methods, (call) {
      calls.add(call);
      return handler?.call(call) ?? Future<Object?>.value();
    });
  }

  setUp(() {
    calls = [];
    gateway = MethodChannelGateway();
    mockMethods(null);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockStreamHandler(eventChannel, null);
  });

  group('argumentos enviados seguem o contrato', () {
    test('startPolling', () async {
      await gateway.startPolling(intervalMs: 100);
      expect(calls.single.method, 'startPolling');
      expect(calls.single.arguments, {'intervalMs': 100});
    });

    test('startPolling usa 200 ms por padrão', () async {
      await gateway.startPolling();
      expect(calls.single.arguments, {'intervalMs': 200});
    });

    test('initialize omite argumentos opcionais ausentes', () async {
      await gateway.initialize(spFileName: 'sp', baudRate: 115200);
      expect(calls.single.arguments, {'spFileName': 'sp', 'baudRate': 115200});
    });

    test('clearData envia o name() do enum', () async {
      await gateway.clearData(ClearMode.first);
      expect(calls.single.arguments, {'mode': 'FIRST'});
    });

    test('setCoefficient, setSafeMode e setMotorPosition', () async {
      await gateway.setCoefficient(CoefficientKind.centrifugal, 7);
      await gateway.setSafeMode(SafeMode.fatigue);
      await gateway.setMotorPosition(p1: 2, p2: 3);
      expect(calls[0].arguments, {'kind': 'centrifugal', 'value': 7});
      expect(calls[1].arguments, {'value': 51});
      expect(calls[2].arguments, {'p1': 2, 'p2': 3});
    });

    test('startMotorSelfCheck usa 130 s por padrão', () async {
      await gateway.startMotorSelfCheck();
      expect(calls.single.arguments, {'timeoutSec': 130});
    });

    test('sendDeviceParams envia os campos da calibração', () async {
      await gateway.sendDeviceParams(DeviceParams.lowerBounds());
      expect(calls.single.arguments, DeviceParams.lowerBounds().toMap());
    });
  });

  group('respostas', () {
    test('connect devolve o bool do nativo', () async {
      mockMethods((_) async => true);
      expect(await gateway.connect('/dev/ttyS3'), isTrue);
      expect(calls.single.arguments, {'portPath': '/dev/ttyS3'});
    });

    test('getDeviceParams converte o Map em DeviceParams', () async {
      mockMethods((_) async => DeviceParams.lowerBounds().toMap());
      expect(await gateway.getDeviceParams(), DeviceParams.lowerBounds());
    });

    test('getConnectionInfo converte o Map em ConnectionInfo', () async {
      mockMethods((_) async => {'state': 'SCANNING', 'portPath': null});
      expect(
        await gateway.getConnectionInfo(),
        const ConnectionInfo(state: PortState.scanning),
      );
    });
  });

  group('erros', () {
    test('PlatformException vira MachineException com o mesmo código', () async {
      mockMethods((_) async => throw PlatformException(code: 'OUT_OF_RANGE', message: 'fora'));
      await expectLater(
        gateway.setForce(999),
        throwsA(isA<MachineException>()
            .having((e) => e.code, 'code', MachineErrorCode.outOfRange)
            .having((e) => e.message, 'message', 'fora')),
      );
    });

    test('método nativo ausente vira SDK_ERROR', () async {
      messenger.setMockMethodCallHandler(methods, null);
      await expectLater(
        gateway.start(),
        throwsA(isA<MachineException>()
            .having((e) => e.code, 'code', MachineErrorCode.sdkError)
            .having((e) => e.message, 'message', contains('start'))),
      );
    });
  });

  group('eventos', () {
    test('converte os Maps do canal em eventos tipados', () async {
      final status = {
        'type': 'connection',
        'state': 'connected',
        'portPath': '/dev/ttyS3',
      };
      messenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(onListen: (arguments, sink) {
          sink.success(status);
          sink.endOfStream();
        }),
      );

      final event = await gateway.events.first;
      expect(
        event,
        const ConnectionEvent(state: MachineConnectionState.connected, portPath: '/dev/ttyS3'),
      );
    });

    test('evento malformado chega como erro do stream', () async {
      messenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(onListen: (arguments, sink) {
          sink.success({'type': 'desconhecido'});
          sink.endOfStream();
        }),
      );

      await expectLater(gateway.events, emitsError(isA<FormatException>()));
    });
  });
}
