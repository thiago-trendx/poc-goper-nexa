import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poc_goper_nexa/data/machine_repository.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';
import 'package:sdk850_bridge/testing.dart';

void main() {
  group('streams por tipo de evento', () {
    test('cada stream entrega só o seu tipo', () {
      fakeAsync((async) {
        final gateway = FakeMachineGateway(connectDelay: Duration.zero);
        final repository = MachineRepository(gateway);
        final connections = <ConnectionEvent>[];
        final statuses = <DeviceStatus>[];
        final infos = <DeviceInfo>[];
        repository.connections.listen(connections.add);
        repository.statuses.listen(statuses.add);
        repository.deviceInfos.listen(infos.add);

        repository.autoConnect();
        async.elapse(const Duration(milliseconds: 10));
        repository.startPolling(intervalMs: 100);
        repository.queryDeviceInfo();
        async.elapse(const Duration(milliseconds: 350));

        expect(connections, hasLength(1));
        expect(statuses, hasLength(3));
        expect(infos, [FakeMachineGateway.defaultDeviceInfo]);

        repository.dispose();
        async.flushMicrotasks();
      });
    });

    test('erros do canal de eventos vão para eventErrors e o stream continua', () {
      fakeAsync((async) {
        final gateway = _ErroringGateway();
        final repository = MachineRepository(gateway);
        final errors = <Object>[];
        final connections = <ConnectionEvent>[];
        repository.eventErrors.listen(errors.add);
        repository.connections.listen(connections.add);

        gateway.emitError(const FormatException('tipo desconhecido'));
        gateway.emit(const ConnectionEvent(state: MachineConnectionState.connected));
        async.flushMicrotasks();

        expect(errors.single, isA<FormatException>());
        expect(connections, hasLength(1));

        repository.dispose();
        async.flushMicrotasks();
      });
    });
  });

  group('conexão e polling', () {
    test('initialize é chamado uma única vez, antes da primeira conexão', () {
      fakeAsync((async) {
        final gateway = _CountingGateway();
        final repository = MachineRepository(gateway);

        repository.autoConnect();
        repository.connect('/dev/ttyS3');
        repository.autoConnect();
        async.elapse(const Duration(milliseconds: 10));

        expect(gateway.initializeCalls, 1);
        expect(gateway.spFileName, 'workbench850_prefs');

        repository.dispose();
        async.flushMicrotasks();
      });
    });

    test('ler o cache de parâmetros inicializa o SDK antes, uma única vez', () {
      fakeAsync((async) {
        final gateway = _CountingGateway();
        final repository = MachineRepository(gateway);

        repository.getDeviceParams();
        repository.getControlParams();
        repository.getDeviceParams();
        async.flushMicrotasks();

        expect(gateway.initializeCalls, 1);

        repository.dispose();
        async.flushMicrotasks();
      });
    });

    test('pollingStates e isPolling acompanham start/stop', () {
      fakeAsync((async) {
        final gateway = FakeMachineGateway(connectDelay: Duration.zero);
        final repository = MachineRepository(gateway);
        final states = <bool>[];
        repository.pollingStates.listen(states.add);
        repository.autoConnect();
        async.elapse(const Duration(milliseconds: 10));

        repository.startPolling(intervalMs: 50);
        async.flushMicrotasks();
        expect(repository.isPolling, isTrue);
        expect(repository.pollingIntervalMs, 50);

        repository.stopPolling();
        async.flushMicrotasks();

        expect(states, [true, false]);
        expect(repository.isPolling, isFalse);

        repository.dispose();
        async.flushMicrotasks();
      });
    });

    test('perder a conexão marca o polling como parado', () {
      fakeAsync((async) {
        final gateway = FakeMachineGateway(connectDelay: Duration.zero);
        final repository = MachineRepository(gateway);
        repository.autoConnect();
        async.elapse(const Duration(milliseconds: 10));
        repository.startPolling();
        async.flushMicrotasks();
        expect(repository.isConnected, isTrue);

        gateway.simulateDisconnect(state: MachineConnectionState.error);
        async.flushMicrotasks();

        expect(repository.isConnected, isFalse);
        expect(repository.isPolling, isFalse);

        repository.dispose();
        async.flushMicrotasks();
      });
    });
  });

  group('haltForSafety', () {
    test('envia stop, espera dois ciclos e só então para o polling', () {
      fakeAsync((async) {
        final gateway = FakeMachineGateway(connectDelay: Duration.zero);
        final repository = MachineRepository(gateway);
        repository.autoConnect();
        async.elapse(const Duration(milliseconds: 10));
        repository.startPolling(intervalMs: 100);
        repository.setForce(10);
        repository.start();
        async.flushMicrotasks();

        repository.haltForSafety();
        async.flushMicrotasks();
        expect(gateway.controlSnapshot.run, RunState.stop);
        expect(gateway.isPolling, isTrue, reason: 'o STOP ainda precisa chegar ao controlador');

        async.elapse(const Duration(milliseconds: 199));
        expect(gateway.isPolling, isTrue);
        async.elapse(const Duration(milliseconds: 1));
        expect(gateway.isPolling, isFalse);
        expect(repository.isPolling, isFalse);

        repository.dispose();
        async.flushMicrotasks();
      });
    });

    test('sem conexão não lança e não deixa polling ativo', () {
      fakeAsync((async) {
        final gateway = FakeMachineGateway(connectDelay: Duration.zero);
        final repository = MachineRepository(gateway);

        Object? error;
        repository.haltForSafety().catchError((Object e) => error = e);
        async.flushMicrotasks();

        expect(error, isNull);
        expect(repository.isPolling, isFalse);

        repository.dispose();
        async.flushMicrotasks();
      });
    });
  });
}

/// Gateway que conta chamadas de `initialize`.
class _CountingGateway extends FakeMachineGateway {
  _CountingGateway() : super(connectDelay: Duration.zero);

  int initializeCalls = 0;
  String? spFileName;
  int? maxForceKg;

  @override
  Future<void> initialize({
    required String spFileName,
    int? baudRate,
    int? sendIntervalMs,
    int? testTimeMs,
    bool? logEnabled,
    int? maxForceKg,
  }) {
    initializeCalls++;
    this.spFileName = spFileName;
    this.maxForceKg = maxForceKg;
    return super.initialize(spFileName: spFileName, maxForceKg: maxForceKg);
  }
}

/// Gateway cujo stream de eventos o teste controla, inclusive com erros.
class _ErroringGateway extends FakeMachineGateway {
  _ErroringGateway() : super(connectDelay: Duration.zero);

  final _controller = StreamController<MachineEvent>.broadcast();

  @override
  Stream<MachineEvent> get events => _controller.stream;

  void emit(MachineEvent event) => _controller.add(event);
  void emitError(Object error) => _controller.addError(error);

  @override
  Future<void> dispose() async {
    await _controller.close();
    await super.dispose();
  }
}
