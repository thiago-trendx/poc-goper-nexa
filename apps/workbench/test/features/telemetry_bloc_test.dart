import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poc_goper_nexa/data/machine_repository.dart';
import 'package:poc_goper_nexa/features/telemetry/telemetry_bloc.dart';
import 'package:sdk850_bridge/testing.dart';

({FakeMachineGateway gateway, MachineRepository repository, TelemetryBloc bloc}) _setup(
  FakeAsync async, {
  int intervalMs = 100,
}) {
  final gateway = FakeMachineGateway(connectDelay: Duration.zero);
  final repository = MachineRepository(gateway);
  final bloc = TelemetryBloc(repository)..add(const TelemetryStarted());
  repository.autoConnect();
  async.elapse(const Duration(milliseconds: 10));
  repository.startPolling(intervalMs: intervalMs);
  async.flushMicrotasks();
  return (gateway: gateway, repository: repository, bloc: bloc);
}

void _teardown(FakeAsync async, TelemetryBloc bloc, MachineRepository repository) {
  bloc.close();
  repository.dispose();
  async.flushMicrotasks();
}

void main() {
  test('guarda o último status e mede a taxa pelo tsMonotonicMs', () {
    fakeAsync((async) {
      final env = _setup(async, intervalMs: 100);
      async.elapse(const Duration(seconds: 3));

      final state = env.bloc.state;
      expect(state.latest, isNotNull);
      expect(state.buffer, hasLength(30));
      expect(state.rateHz, closeTo(10, 0.001));

      _teardown(async, env.bloc, env.repository);
    });
  });

  test('a taxa acompanha a mudança do intervalo de polling', () {
    fakeAsync((async) {
      final env = _setup(async, intervalMs: 200);
      async.elapse(const Duration(seconds: 5));
      expect(env.bloc.state.rateHz, closeTo(5, 0.001));

      env.repository.startPolling(intervalMs: 50);
      async.elapse(const Duration(seconds: 2));
      expect(env.bloc.state.rateHz, closeTo(20, 0.001));

      _teardown(async, env.bloc, env.repository);
    });
  });

  test('sem ao menos dois status a taxa é nula', () {
    fakeAsync((async) {
      final env = _setup(async, intervalMs: 100);
      expect(env.bloc.state.rateHz, isNull);

      async.elapse(const Duration(milliseconds: 100));
      expect(env.bloc.state.buffer, hasLength(1));
      expect(env.bloc.state.rateHz, isNull);

      _teardown(async, env.bloc, env.repository);
    });
  });

  test('o buffer circular guarda só os últimos 60 s', () {
    fakeAsync((async) {
      final env = _setup(async, intervalMs: 100);
      async.elapse(const Duration(seconds: 90));

      final buffer = env.bloc.state.buffer;
      expect(buffer.last.tsMonotonicMs - buffer.first.tsMonotonicMs, lessThanOrEqualTo(TelemetryBloc.windowMs));
      expect(buffer, hasLength(601));
      expect(env.bloc.state.latest, buffer.last);

      _teardown(async, env.bloc, env.repository);
    });
  });

  test('a gravação conta amostras só enquanto está ligada', () {
    fakeAsync((async) {
      final env = _setup(async, intervalMs: 100);
      async.elapse(const Duration(seconds: 1));
      expect(env.bloc.state.recordedSamples, 0);

      env.bloc.add(const RecordingToggled());
      async.elapse(const Duration(seconds: 1));
      expect(env.bloc.state.recording, isTrue);
      expect(env.bloc.state.recordedSamples, 10);

      env.bloc.add(const RecordingToggled());
      async.elapse(const Duration(seconds: 1));
      expect(env.bloc.state.recording, isFalse);
      expect(env.bloc.state.recordedSamples, 0);

      _teardown(async, env.bloc, env.repository);
    });
  });

  test('Cleared esvazia o buffer e a taxa, mantendo o último valor e a gravação', () {
    fakeAsync((async) {
      final env = _setup(async, intervalMs: 100);
      env.bloc.add(const RecordingToggled());
      async.elapse(const Duration(seconds: 1));
      final latest = env.bloc.state.latest;

      env.repository.stopPolling();
      async.flushMicrotasks();
      env.bloc.add(const TelemetryCleared());
      async.flushMicrotasks();

      expect(env.bloc.state.buffer, isEmpty);
      expect(env.bloc.state.rateHz, isNull);
      expect(env.bloc.state.latest, latest);
      expect(env.bloc.state.recording, isTrue);

      _teardown(async, env.bloc, env.repository);
    });
  });
}
