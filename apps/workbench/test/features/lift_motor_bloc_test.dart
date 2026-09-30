import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poc_goper_nexa/data/machine_repository.dart';
import 'package:poc_goper_nexa/features/lift_motor/lift_motor_bloc.dart';
import 'package:sdk850_bridge/testing.dart';

/// Monta gateway, repositório e Bloc já conectados, dentro de um `fakeAsync`.
({FakeMachineGateway gateway, MachineRepository repository, LiftMotorBloc bloc}) _setup(
  FakeAsync async, {
  bool timeout = false,
}) {
  final gateway = FakeMachineGateway(
    connectDelay: Duration.zero,
    liftMotorAdjustDuration: const Duration(seconds: 4),
    selfCheckDuration: const Duration(seconds: 6),
  )..simulateLiftMotorTimeout = timeout;
  final repository = MachineRepository(gateway);
  final bloc = LiftMotorBloc(repository);
  repository.autoConnect();
  async.elapse(const Duration(milliseconds: 10));
  return (gateway: gateway, repository: repository, bloc: bloc);
}

void _teardown(FakeAsync async, LiftMotorBloc bloc, MachineRepository repository) {
  bloc.close();
  repository.dispose();
  async.flushMicrotasks();
}

void main() {
  test('ajuste de posição: contagem regressiva e conclusão', () {
    fakeAsync((async) {
      final env = _setup(async);
      env.repository.startPolling(intervalMs: 100);
      async.flushMicrotasks();

      env.bloc.add(const PositionRequested(p1: 2, p2: 3));
      async.flushMicrotasks();
      expect(env.bloc.state.phase, LiftPhase.adjusting);
      // O fake informa 4 s de ajuste + 4 s de margem como tempo de segurança.
      expect(env.bloc.state.remainingSec, 8);
      expect(env.gateway.controlSnapshot.motorPosition1, 2);
      expect(env.gateway.controlSnapshot.motorPosition2, 3);

      async.elapse(const Duration(seconds: 2));
      expect(env.bloc.state.remainingSec, 6);
      expect(env.bloc.state.liftMotorStatus, 0x01);

      async.elapse(const Duration(seconds: 2));
      expect(env.bloc.state.phase, LiftPhase.completed);
      expect(env.bloc.state.remainingSec, 0);
      async.elapse(const Duration(milliseconds: 300));
      expect(env.bloc.state.liftMotorStatus, 0x00);

      _teardown(async, env.bloc, env.repository);
    });
  });

  test('autoteste usa o timeout pedido como contagem e conclui', () {
    fakeAsync((async) {
      final env = _setup(async);

      env.bloc.add(const SelfCheckRequested(timeoutSec: 130));
      async.flushMicrotasks();
      expect(env.bloc.state.phase, LiftPhase.selfChecking);
      expect(env.bloc.state.remainingSec, 130);
      expect(env.gateway.controlSnapshot.motorSelfCheck, isTrue);

      async.elapse(const Duration(seconds: 6));
      expect(env.bloc.state.phase, LiftPhase.completed);
      expect(env.gateway.controlSnapshot.motorSelfCheck, isFalse);

      _teardown(async, env.bloc, env.repository);
    });
  });

  test('timeout de segurança vira fase timeout', () {
    fakeAsync((async) {
      final env = _setup(async, timeout: true);

      env.bloc.add(const PositionRequested(p1: 1, p2: 1));
      async.elapse(const Duration(seconds: 4));

      expect(env.bloc.state.phase, LiftPhase.timeout);
      expect(env.bloc.state.busy, isFalse);

      _teardown(async, env.bloc, env.repository);
    });
  });

  test('pedido recusado volta para ocioso com o erro publicado', () {
    fakeAsync((async) {
      final env = _setup(async);

      env.bloc.add(const PositionRequested(p1: -1, p2: 0));
      async.flushMicrotasks();

      expect(env.bloc.state.phase, LiftPhase.idle);
      expect(env.bloc.state.error, 'Posição deve ser >= 0');
      expect(env.bloc.state.errorSeq, 1);

      _teardown(async, env.bloc, env.repository);
    });
  });

  test('segundo pedido durante o primeiro é descartado', () {
    fakeAsync((async) {
      final env = _setup(async);

      env.bloc.add(const PositionRequested(p1: 1, p2: 1));
      env.bloc.add(const PositionRequested(p1: 9, p2: 9));
      env.bloc.add(const SelfCheckRequested());
      async.flushMicrotasks();

      expect(env.gateway.controlSnapshot.motorPosition1, 1);
      expect(env.bloc.state.phase, LiftPhase.adjusting);
      expect(env.bloc.state.errorSeq, 0);

      _teardown(async, env.bloc, env.repository);
    });
  });

  test('erros dos motores do status aparecem no estado', () {
    fakeAsync((async) {
      final env = _setup(async);
      env.gateway.injectLiftMotorErrors(error1: 0x11, error2: 0x22);
      env.repository.startPolling(intervalMs: 100);
      async.elapse(const Duration(milliseconds: 300));

      expect(env.bloc.state.error1, 0x11);
      expect(env.bloc.state.error2, 0x22);

      _teardown(async, env.bloc, env.repository);
    });
  });

  test('evento liftMotor sem comando em andamento é ignorado', () {
    fakeAsync((async) {
      final env = _setup(async);

      env.gateway.setMotorPosition(p1: 1, p2: 1); // direto no gateway, sem passar pelo Bloc
      async.elapse(const Duration(seconds: 5));

      expect(env.bloc.state.phase, LiftPhase.idle);

      _teardown(async, env.bloc, env.repository);
    });
  });
}
