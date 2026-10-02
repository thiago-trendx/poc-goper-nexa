import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';
import 'package:sdk850_bridge/testing.dart';

/// Cria um gateway conectado e coleta os eventos emitidos a partir daí.
({FakeMachineGateway gateway, List<MachineEvent> events}) _connected(
  FakeAsync async, {
  FakeMachineGateway? gateway,
}) {
  final g = gateway ?? FakeMachineGateway();
  final events = <MachineEvent>[];
  g.events.listen(events.add);
  g.autoConnect();
  async.elapse(g.connectDelay);
  return (gateway: g, events: events);
}

/// Devolve a [MachineException] lançada por [call], ou `null` se não houve falha.
MachineException? _failure(FakeAsync async, Future<Object?> call) {
  MachineException? failure;
  call.then<void>((_) {}, onError: (Object error) {
    failure = error as MachineException;
  });
  async.flushMicrotasks();
  return failure;
}

void main() {
  group('conexão', () {
    test('comandos falham com NOT_CONNECTED antes de conectar', () {
      fakeAsync((async) {
        final g = FakeMachineGateway();
        expect(_failure(async, g.start())?.code, MachineErrorCode.notConnected);
        expect(_failure(async, g.startPolling())?.code, MachineErrorCode.notConnected);
      });
    });

    test('autoConnect emite connected após o atraso configurado', () {
      fakeAsync((async) {
        final g = FakeMachineGateway(connectDelay: const Duration(seconds: 1));
        final events = <MachineEvent>[];
        g.events.listen(events.add);

        g.autoConnect();
        async.elapse(const Duration(milliseconds: 999));
        expect(events, isEmpty);
        async.elapse(const Duration(milliseconds: 1));

        expect(events, [
          const ConnectionEvent(
            state: MachineConnectionState.connected,
            portPath: '/dev/ttyFAKE0',
          ),
        ]);
      });
    });

    test('autoConnectShouldFail emite failed e mantém desconectado', () {
      fakeAsync((async) {
        final g = FakeMachineGateway()..autoConnectShouldFail = true;
        final events = <MachineEvent>[];
        g.events.listen(events.add);

        g.autoConnect();
        async.elapse(g.connectDelay);

        expect((events.single as ConnectionEvent).state, MachineConnectionState.failed);
        expect(g.isConnected, isFalse);
      });
    });

    test('connect valida o caminho e devolve true', () {
      fakeAsync((async) {
        final g = FakeMachineGateway();
        expect(_failure(async, g.connect(' '))?.code, MachineErrorCode.invalidArgs);

        bool? result;
        g.connect('/dev/ttyS3').then((v) => result = v);
        async.elapse(g.connectDelay);
        expect(result, isTrue);
        expect(g.isConnected, isTrue);
      });
    });

    test('simulateDisconnect para o polling e avisa por evento', () {
      fakeAsync((async) {
        final c = _connected(async);
        c.gateway.startPolling();
        async.flushMicrotasks();
        expect(c.gateway.isPolling, isTrue);

        c.gateway.simulateDisconnect(state: MachineConnectionState.error, reason: 'cabo solto');
        async.flushMicrotasks();

        expect(c.gateway.isPolling, isFalse);
        expect(c.gateway.isConnected, isFalse);
        expect(c.events.last, isA<ConnectionEvent>()
            .having((e) => e.state, 'state', MachineConnectionState.error)
            .having((e) => e.reason, 'reason', 'cabo solto'));
        expect(_failure(async, c.gateway.stop())?.code, MachineErrorCode.notConnected);
      });
    });

    test('getConnectionInfo reflete idle, scanning e connected', () async {
      final g = FakeMachineGateway(connectDelay: Duration.zero);
      expect((await g.getConnectionInfo()).state, PortState.idle);
      await g.autoConnect();
      expect((await g.getConnectionInfo()).state, PortState.scanning);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final info = await g.getConnectionInfo();
      expect(info.state, PortState.connected);
      expect(info.portPath, '/dev/ttyFAKE0');
      await g.dispose();
    });
  });

  group('polling e status', () {
    test('emite um status por intervalo, com relógio simulado', () {
      fakeAsync((async) {
        final c = _connected(async);
        c.events.clear();

        c.gateway.startPolling(intervalMs: 100);
        async.elapse(const Duration(milliseconds: 500));

        final statuses = c.events.whereType<DeviceStatus>().toList();
        expect(statuses, hasLength(5));
        for (var i = 1; i < statuses.length; i++) {
          expect(statuses[i].tsMonotonicMs - statuses[i - 1].tsMonotonicMs, 100);
          expect(statuses[i].tsEpochMs - statuses[i - 1].tsEpochMs, 100);
        }
      });
    });

    test('stopPolling interrompe o status', () {
      fakeAsync((async) {
        final c = _connected(async);
        c.gateway.startPolling();
        async.elapse(const Duration(seconds: 1));
        c.gateway.stopPolling();
        async.flushMicrotasks();
        c.events.clear();

        async.elapse(const Duration(seconds: 1));
        expect(c.events, isEmpty);
      });
    });

    test('em STOP a força é a inactiveForce e a máquina fica parada', () {
      fakeAsync((async) {
        final c = _connected(async);
        c.gateway.setForce(30);
        c.gateway.startPolling();
        async.elapse(const Duration(seconds: 1));

        final status = c.events.whereType<DeviceStatus>().last;
        expect(status.run, RunState.stop);
        expect(status.force, FakeMachineGateway.defaultParams.inactiveForce);
        expect(status.speed, 0);
        expect(status.distance, 0);
      });
    });

    test('em RUNNING força e curso variam e as repetições são contadas', () {
      fakeAsync((async) {
        final c = _connected(async);
        c.gateway.startPolling(intervalMs: 100);
        c.gateway
          ..setForce(40)
          ..start();
        async.elapse(const Duration(seconds: 7));

        final statuses = c.events.whereType<DeviceStatus>().toList();
        expect(statuses.every((s) => s.run == RunState.running && s.force == 40), isTrue);
        expect(statuses.map((s) => s.distance).toSet().length, greaterThan(5));
        expect(statuses.map((s) => s.realForce).toSet().length, greaterThan(1));
        expect(statuses.any((s) => s.speed < 0), isTrue);
        expect(statuses.any((s) => s.speed > 0), isTrue);
        expect(statuses.last.pullNum, 2); // 7 s / 3 s por repetição
      });
    });

    test('setMode, coeficientes, safeMode e balancingForce vão para o ControlSnapshot', () {
      fakeAsync((async) {
        final c = _connected(async);
        final g = c.gateway;
        g
          ..setMode(ForceMode.velocity)
          ..setCoefficient(CoefficientKind.velocity, 12)
          ..setCoefficient(CoefficientKind.elastic, 4)
          ..setElasticMax(60)
          ..setSafeMode(SafeMode.protection)
          ..setBalancingForce(10);
        async.flushMicrotasks();

        expect(g.controlSnapshot.mode, ForceMode.velocity);
        expect(g.controlSnapshot.velocity, 12);
        expect(g.controlSnapshot.elastic, 4);
        expect(g.controlSnapshot.maxElectric, 60);
        expect(g.controlSnapshot.safeMode, SafeMode.protection);
        expect(g.controlSnapshot.balancingForce, 10);
      });
    });

    test('valores fora da faixa viram OUT_OF_RANGE e não alteram o estado', () {
      fakeAsync((async) {
        final g = _connected(async).gateway;
        final maxForce = g.deviceParams.maxForce;

        expect(_failure(async, g.setForce(maxForce + 1))?.code, MachineErrorCode.outOfRange);
        expect(_failure(async, g.setForce(-1))?.code, MachineErrorCode.outOfRange);
        expect(_failure(async, g.setBalancingForce(26))?.code, MachineErrorCode.outOfRange);
        expect(
          _failure(async, g.setCoefficient(CoefficientKind.velocity, g.deviceParams.velocityRange + 1))?.code,
          MachineErrorCode.outOfRange,
        );
        expect(g.controlSnapshot, const ControlSnapshot());
      });
    });

    test('erros injetados aparecem no status e errorRestore os limpa', () {
      fakeAsync((async) {
        final c = _connected(async);
        c.gateway
          ..injectErrorCode(7)
          ..injectLiftMotorErrors(error1: 1, error2: 2)
          ..startPolling();
        async.elapse(const Duration(milliseconds: 400));
        expect(c.events.whereType<DeviceStatus>().last.errorCode, 7);
        expect(c.events.whereType<DeviceStatus>().last.hasLiftMotorError, isTrue);

        c.gateway.errorRestore();
        async.elapse(const Duration(milliseconds: 400));
        expect(c.events.whereType<DeviceStatus>().last.hasError, isFalse);
        expect(c.events.whereType<DeviceStatus>().last.hasLiftMotorError, isFalse);
      });
    });

    test('failNextCommand falha só o próximo comando', () {
      fakeAsync((async) {
        final g = _connected(async).gateway;
        g.failNextCommand(const MachineException(MachineErrorCode.sdkError, 'boom'));

        expect(_failure(async, g.setMode(ForceMode.elastic))?.code, MachineErrorCode.sdkError);
        expect(g.controlSnapshot.mode, ForceMode.standard, reason: 'o comando que falhou não foi aplicado');
        expect(_failure(async, g.setMode(ForceMode.elastic)), isNull);
        expect(g.controlSnapshot.mode, ForceMode.elastic);
      });
    });
  });

  group('controle (Fase 4)', () {
    test('a força inicial é inválida: start recusa até o app definir a força', () {
      fakeAsync((async) {
        final g = _connected(async).gateway;
        g.startPolling();
        async.flushMicrotasks();

        final failure = _failure(async, g.start());

        expect(failure?.code, MachineErrorCode.outOfRange);
        expect(failure?.message, contains('Defina a força antes de iniciar'));
        expect(g.controlSnapshot.run, RunState.stop);
      });
    });

    test('start sem polling ligado vira SDK_ERROR e não muda o estado', () {
      fakeAsync((async) {
        final g = _connected(async).gateway;
        g.setForce(10);

        final failure = _failure(async, g.start());

        expect(failure?.code, MachineErrorCode.sdkError);
        expect(failure?.message, contains('Ligue o polling'));
        expect(g.controlSnapshot.run, RunState.stop);
      });
    });

    test('a força vai de minForce a maxForce da calibração', () {
      fakeAsync((async) {
        final g = _connected(async).gateway;
        final min = g.deviceParams.minForce;
        final max = g.deviceParams.maxForce;

        g.setForce(min);
        g.setForce(max);
        async.flushMicrotasks();
        expect(g.controlSnapshot.force, max);

        for (final kg in [0, min - 1, max + 1]) {
          final failure = _failure(async, g.setForce(kg));
          expect(failure?.code, MachineErrorCode.outOfRange, reason: '$kg kg');
          expect(failure?.message, contains('entre $min e $max kg'));
        }
        expect(g.controlSnapshot.force, max, reason: 'valor recusado não é aplicado');
      });
    });

    test('o limite de segurança do app vale além da calibração', () {
      fakeAsync((async) {
        final g = FakeMachineGateway(connectDelay: Duration.zero);
        g.initialize(spFileName: 'sp', maxForceKg: 30);
        g.autoConnect();
        async.elapse(const Duration(milliseconds: 10));

        g.setForce(30);
        final failure = _failure(async, g.setForce(31));

        expect(failure?.code, MachineErrorCode.outOfRange);
        expect(failure?.message, contains('limite de segurança do app: 30 kg'));
        expect(g.controlSnapshot.force, 30);
      });
    });

    test('start recusa uma força acima do limite de segurança do app', () {
      fakeAsync((async) {
        final g = FakeMachineGateway(connectDelay: Duration.zero);
        g.initialize(spFileName: 'sp', maxForceKg: 20);
        g.autoConnect();
        async.elapse(const Duration(milliseconds: 10));
        g.setForce(20);
        g.startPolling();
        async.flushMicrotasks();

        // o limite diminui (novo initialize) com a força antiga ainda aplicada
        g.disconnect();
        g.initialize(spFileName: 'sp', maxForceKg: 10);
        g.autoConnect();
        async.elapse(const Duration(milliseconds: 10));
        g.startPolling();
        async.flushMicrotasks();

        expect(_failure(async, g.start())?.code, MachineErrorCode.outOfRange);
        expect(g.controlSnapshot.run, RunState.stop);
      });
    });

    test('maxForceKg inválido no initialize vira INVALID_ARGS', () {
      fakeAsync((async) {
        final g = FakeMachineGateway();

        expect(_failure(async, g.initialize(spFileName: 'sp', maxForceKg: 0))?.code, MachineErrorCode.invalidArgs);
        expect(_failure(async, g.initialize(spFileName: 'sp', maxForceKg: -3))?.code, MachineErrorCode.invalidArgs);
      });
    });

    test('coeficientes seguem as faixas do demo e do velocityRange', () {
      fakeAsync((async) {
        final g = _connected(async).gateway;
        final limits = {
          CoefficientKind.centripetal: 6,
          CoefficientKind.centrifugal: 6,
          CoefficientKind.elastic: 10,
          CoefficientKind.velocity: g.deviceParams.velocityRange,
        };

        for (final entry in limits.entries) {
          g.setCoefficient(entry.key, 0);
          g.setCoefficient(entry.key, entry.value);
          async.flushMicrotasks();
          expect(g.controlSnapshot.coefficient(entry.key), entry.value);
          expect(_failure(async, g.setCoefficient(entry.key, entry.value + 1))?.code, MachineErrorCode.outOfRange,
              reason: '${entry.key.name} acima');
          expect(_failure(async, g.setCoefficient(entry.key, -1))?.code, MachineErrorCode.outOfRange,
              reason: '${entry.key.name} abaixo');
        }
      });
    });

    test('o curso elástico vai de 1 ao comprimento máximo do cabo', () {
      fakeAsync((async) {
        final g = _connected(async).gateway;
        final max = g.deviceParams.maxLength;

        g.setElasticMax(1);
        g.setElasticMax(max);
        async.flushMicrotasks();

        expect(g.controlSnapshot.maxElectric, max);
        expect(_failure(async, g.setElasticMax(0))?.code, MachineErrorCode.outOfRange);
        expect(_failure(async, g.setElasticMax(max + 1))?.code, MachineErrorCode.outOfRange);
      });
    });

    test('pausar ou religar o polling, ou perder a conexão, volta o estado para STOP', () {
      fakeAsync((async) {
        final g = _connected(async).gateway;
        void run() {
          g.startPolling();
          g.setForce(10);
          g.start();
          async.flushMicrotasks();
          expect(g.controlSnapshot.run, RunState.running);
        }

        run();
        g.stopPolling();
        async.flushMicrotasks();
        expect(g.controlSnapshot.run, RunState.stop, reason: 'stopPolling');

        run();
        g.startPolling(intervalMs: 100);
        async.flushMicrotasks();
        expect(g.controlSnapshot.run, RunState.stop, reason: 'religar o polling reinicia em STOP');

        run();
        g.simulateDisconnect();
        expect(g.controlSnapshot.run, RunState.stop, reason: 'perda de conexão');
      });
    });
  });

  group('informações e parâmetros', () {
    test('queryDeviceInfo emite deviceInfo', () {
      fakeAsync((async) {
        final c = _connected(async);
        c.gateway.queryDeviceInfo();
        async.flushMicrotasks();
        async.elapse(Duration.zero);

        expect(c.events.whereType<DeviceInfo>().single, FakeMachineGateway.defaultDeviceInfo);
      });
    });

    test('sendDeviceParams valida a faixa e confirma por paramsAck', () {
      fakeAsync((async) {
        final c = _connected(async);
        final g = c.gateway;
        final invalid = g.deviceParams.withField(DeviceParamField.minForce, 99);
        expect(_failure(async, g.sendDeviceParams(invalid))?.code, MachineErrorCode.outOfRange);
        expect(c.events.whereType<ParamsAckEvent>(), isEmpty);

        final valid = g.deviceParams.withField(DeviceParamField.minForce, 10);
        g.sendDeviceParams(valid);
        async.flushMicrotasks();
        async.elapse(Duration.zero);

        expect(c.events.whereType<ParamsAckEvent>().single.params, valid);
        expect(g.deviceParams, valid);
      });
    });

    test('ackFor faz o controlador devolver valores diferentes dos enviados', () {
      fakeAsync((async) {
        final c = _connected(async);
        final g = c.gateway..ackFor = (sent) => sent.withField(DeviceParamField.minForce, 12);
        final sent = g.deviceParams.withField(DeviceParamField.minForce, 10);

        g.sendDeviceParams(sent);
        async.flushMicrotasks();
        async.elapse(Duration.zero);

        expect(c.events.whereType<ParamsAckEvent>().single.params.minForce, 12);
        expect(g.deviceParams.minForce, 12, reason: 'o cache guarda o que o controlador devolveu');
      });
    });

    test('dropParamsAck aceita o envio mas nunca confirma', () {
      fakeAsync((async) {
        final c = _connected(async);
        final g = c.gateway..dropParamsAck = true;

        g.sendDeviceParams(g.deviceParams.withField(DeviceParamField.minForce, 10));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 5));

        expect(c.events.whereType<ParamsAckEvent>(), isEmpty);
      });
    });

    test('getDeviceParams e getControlParams funcionam sem conexão', () async {
      final g = FakeMachineGateway();
      expect(await g.getDeviceParams(), FakeMachineGateway.defaultParams);
      expect(await g.getControlParams(), const ControlSnapshot());
      await g.dispose();
    });
  });

  group('motores de elevação', () {
    test('setMotorPosition para o movimento, sinaliza o status e conclui no prazo', () {
      fakeAsync((async) {
        final c = _connected(async);
        final g = c.gateway;
        g.startPolling(intervalMs: 100);
        g.setForce(10);
        g.start();
        async.elapse(const Duration(milliseconds: 300));
        c.events.clear();

        g.setMotorPosition(p1: 2, p2: 3);
        async.flushMicrotasks();

        expect(g.controlSnapshot.run, RunState.stop);
        expect(g.controlSnapshot.motorPosition1, 2);
        expect(g.controlSnapshot.motorPosition2, 3);
        expect(c.events.whereType<LiftMotorEvent>().single.phase, LiftMotorPhase.started);

        async.elapse(const Duration(seconds: 2));
        expect(c.events.whereType<DeviceStatus>().last.liftMotorMoving, isTrue);

        async.elapse(const Duration(seconds: 2));
        expect(c.events.whereType<LiftMotorEvent>().last.phase, LiftMotorPhase.completed);
        async.elapse(const Duration(milliseconds: 200));
        expect(c.events.whereType<DeviceStatus>().last.liftMotorStatus, 0);
      });
    });

    test('segundo ajuste durante o primeiro falha com BUSY', () {
      fakeAsync((async) {
        final g = _connected(async).gateway;
        g.startPolling(intervalMs: 100);
        g.setForce(10);
        g.setMotorPosition(p1: 1, p2: 1);
        async.flushMicrotasks();

        expect(_failure(async, g.setMotorPosition(p1: 2, p2: 2))?.code, MachineErrorCode.busy);
        expect(_failure(async, g.startMotorSelfCheck())?.code, MachineErrorCode.busy);
        expect(_failure(async, g.start())?.code, MachineErrorCode.busy);
        expect(_failure(async, g.originReset())?.code, MachineErrorCode.busy);
        expect(_failure(async, g.errorRestore())?.code, MachineErrorCode.busy);
        expect(_failure(async, g.clearData(ClearMode.all))?.code, MachineErrorCode.busy);
      });
    });

    test('ajuste e autoteste exigem o polling ligado', () {
      fakeAsync((async) {
        final g = _connected(async).gateway;

        expect(_failure(async, g.setMotorPosition(p1: 1, p2: 1))?.code, MachineErrorCode.sdkError);
        expect(_failure(async, g.startMotorSelfCheck())?.code, MachineErrorCode.sdkError);
        expect(g.controlSnapshot.motorSelfCheck, isFalse);
      });
    });

    test('ajustar para as posições atuais é recusado', () {
      fakeAsync((async) {
        final g = _connected(async).gateway;
        g.startPolling(intervalMs: 100);

        expect(_failure(async, g.setMotorPosition(p1: 0, p2: 0))?.code, MachineErrorCode.invalidArgs);
      });
    });

    test('parar o polling durante o autoteste aborta como timeout e desliga o flag', () {
      fakeAsync((async) {
        final c = _connected(async);
        final g = c.gateway;
        g.startPolling(intervalMs: 100);
        g.startMotorSelfCheck();
        async.flushMicrotasks();
        expect(g.controlSnapshot.motorSelfCheck, isTrue);

        g.stopPolling();
        async.flushMicrotasks();

        expect(c.events.whereType<LiftMotorEvent>().last.phase, LiftMotorPhase.timeout);
        expect(g.controlSnapshot.motorSelfCheck, isFalse);
        expect(g.controlSnapshot.run, RunState.stop);
        async.elapse(const Duration(minutes: 5));
        expect(c.events.whereType<LiftMotorEvent>().length, 2, reason: 'started e timeout, nada depois');
      });
    });

    test('perder a conexão durante o ajuste publica timeout', () {
      fakeAsync((async) {
        final c = _connected(async);
        final g = c.gateway;
        g.startPolling(intervalMs: 100);
        g.setMotorPosition(p1: 2, p2: 2);
        async.flushMicrotasks();

        g.disconnect();
        async.flushMicrotasks();

        expect(c.events.whereType<LiftMotorEvent>().last.phase, LiftMotorPhase.timeout);
      });
    });

    test('origem e reset de erro só com a máquina parada', () {
      fakeAsync((async) {
        final g = _connected(async).gateway;
        g.startPolling(intervalMs: 100);
        g.setForce(10);
        g.start();
        async.flushMicrotasks();

        expect(_failure(async, g.originReset())?.code, MachineErrorCode.busy);
        expect(_failure(async, g.errorRestore())?.code, MachineErrorCode.busy);
        expect(_failure(async, g.clearData(ClearMode.all)), isNull, reason: 'limpar dados vale em execução');
      });
    });

    test('autoteste reporta o timeout de segurança e volta motorSelfCheck para false', () {
      fakeAsync((async) {
        final c = _connected(async);
        final g = c.gateway;
        g.startPolling(intervalMs: 100);
        g.startMotorSelfCheck(timeoutSec: 130);
        async.flushMicrotasks();

        final started = c.events.whereType<LiftMotorEvent>().single;
        expect(started.remainingSec, 130);
        expect(g.controlSnapshot.motorSelfCheck, isTrue);
        async.elapse(const Duration(seconds: 1));
        expect(c.events.whereType<DeviceStatus>().last.liftMotorSelfChecking, isTrue);

        async.elapse(g.selfCheckDuration);
        expect(c.events.whereType<LiftMotorEvent>().last.phase, LiftMotorPhase.completed);
        expect(g.controlSnapshot.motorSelfCheck, isFalse);
      });
    });

    test('simulateLiftMotorTimeout termina com timeout', () {
      fakeAsync((async) {
        final c = _connected(async);
        c.gateway.simulateLiftMotorTimeout = true;
        c.gateway.startPolling(intervalMs: 100);
        c.gateway.setMotorPosition(p1: 1, p2: 1);
        async.elapse(c.gateway.liftMotorAdjustDuration);

        expect(c.events.whereType<LiftMotorEvent>().last.phase, LiftMotorPhase.timeout);
      });
    });

    test('posição negativa e timeout inválido são rejeitados', () {
      fakeAsync((async) {
        final g = _connected(async).gateway;
        g.startPolling(intervalMs: 100);
        expect(_failure(async, g.setMotorPosition(p1: -1, p2: 0))?.code, MachineErrorCode.outOfRange);
        expect(_failure(async, g.startMotorSelfCheck(timeoutSec: 0))?.code, MachineErrorCode.outOfRange);
        expect(_failure(async, g.startMotorSelfCheck(timeoutSec: 601))?.code, MachineErrorCode.outOfRange);
      });
    });
  });

  group('firmware', () {
    test('instala em etapas, pausa o polling e o retoma no final', () {
      fakeAsync((async) {
        final c = _connected(async);
        final g = c.gateway;
        g.startPolling();
        async.flushMicrotasks();

        g.installFirmware(type: 2, filePath: '/sdcard/fw.bin');
        async.flushMicrotasks();
        expect(g.isPolling, isFalse);

        async.elapse(g.firmwareStepInterval * 4);

        final phases = c.events.whereType<FirmwareEvent>().toList();
        expect(phases.first.phase, FirmwarePhase.sending);
        expect(
          phases.where((e) => e.phase == FirmwarePhase.progress).map((e) => e.progress),
          [25, 50, 75, 100],
        );
        expect(phases.last.phase, FirmwarePhase.success);
        expect(g.isPolling, isTrue);
      });
    });

    test('cancelFirmware emite erro e retoma o polling', () {
      fakeAsync((async) {
        final c = _connected(async);
        final g = c.gateway;
        g.startPolling();
        g.installFirmware(type: 1, filePath: 'fw.bin');
        async.elapse(g.firmwareStepInterval);

        g.cancelFirmware();
        async.flushMicrotasks();

        expect(c.events.whereType<FirmwareEvent>().last.phase, FirmwarePhase.error);
        expect(g.isPolling, isTrue);
        async.elapse(g.firmwareStepInterval * 4);
        expect(c.events.whereType<FirmwareEvent>().any((e) => e.phase == FirmwarePhase.success), isFalse);
      });
    });

    test('tipo e caminho inválidos são rejeitados; segunda instalação falha com BUSY', () {
      fakeAsync((async) {
        final g = _connected(async).gateway;
        expect(_failure(async, g.installFirmware(type: 3, filePath: 'fw.bin'))?.code, MachineErrorCode.invalidArgs);
        expect(_failure(async, g.installFirmware(type: 1, filePath: ''))?.code, MachineErrorCode.invalidArgs);

        g.installFirmware(type: 1, filePath: 'fw.bin');
        async.flushMicrotasks();
        expect(_failure(async, g.installFirmware(type: 1, filePath: 'fw.bin'))?.code, MachineErrorCode.busy);
      });
    });
  });

  test('dispose encerra o stream de eventos', () async {
    final g = FakeMachineGateway();
    final done = g.events.drain<void>();
    await g.dispose();
    await done;
  });
}
