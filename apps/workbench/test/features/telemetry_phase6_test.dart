import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poc_goper_nexa/data/machine_repository.dart';
import 'package:poc_goper_nexa/features/telemetry/rate_test_cubit.dart';
import 'package:poc_goper_nexa/features/telemetry/telemetry_bloc.dart';
import 'package:poc_goper_nexa/features/telemetry/telemetry_export.dart';
import 'package:poc_goper_nexa/features/telemetry/telemetry_report.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';
import 'package:sdk850_bridge/testing.dart';

import '../helpers/fake_telemetry_exporter.dart';

DeviceStatus _status({
  int ts = 1000,
  int force = 12,
  double speed = 3.5,
  int distance = 40,
  int errorCode = 0,
}) =>
    DeviceStatus(
      run: RunState.running,
      mode: ForceMode.standard,
      force: 10,
      realForce: force,
      speed: speed,
      distance: distance,
      pullNum: 2,
      errorCode: errorCode,
      temperature: 25.04,
      liftMotorStatus: 0,
      liftMotorError1: 0,
      liftMotorError2: 0,
      verityCodeError: 0,
      tsMonotonicMs: ts,
      tsEpochMs: 1750000000000 + ts,
    );

({FakeMachineGateway gateway, MachineRepository repository, TelemetryBloc bloc, FakeTelemetryExporter exporter})
    _setupBloc(FakeAsync async) {
  final gateway = FakeMachineGateway(connectDelay: Duration.zero);
  final repository = MachineRepository(gateway);
  final exporter = FakeTelemetryExporter();
  final bloc = TelemetryBloc(repository, exporter: exporter)..add(const TelemetryStarted());
  repository.autoConnect();
  async.elapse(const Duration(milliseconds: 10));
  repository.startPolling(intervalMs: 100);
  async.flushMicrotasks();
  return (gateway: gateway, repository: repository, bloc: bloc, exporter: exporter);
}

void _teardownBloc(FakeAsync async, TelemetryBloc bloc, MachineRepository repository) {
  bloc.close();
  repository.dispose();
  async.flushMicrotasks();
}

void main() {
  group('CSV', () {
    test('cabeçalho fixo e uma linha por status, com ponto decimal', () {
      final csv = TelemetryCsv.build([_status(ts: 1000), _status(ts: 1200, force: 15, speed: 0)]);
      final lines = csv.trim().split('\n');

      expect(lines.first, TelemetryCsv.header.join(','));
      expect(lines, hasLength(3));
      expect(lines[1], '1750000001000,1000,RUNNING,STANDARD,10,12,3.5,40,2,0,25.0,0,0,0,0');
      expect(lines[2].split(',')[5], '15');
      expect(lines[2].split(',')[6], '0.0');
    });

    test('sem linhas só tem o cabeçalho', () {
      expect(TelemetryCsv.build(const []).trim(), TelemetryCsv.header.join(','));
    });
  });

  group('gravação', () {
    test('parar a gravação salva o CSV com todas as amostras', () {
      fakeAsync((async) {
        final env = _setupBloc(async);
        env.bloc.add(const RecordingToggled());
        async.elapse(const Duration(seconds: 1));
        env.bloc.add(const RecordingToggled());
        async.elapse(const Duration(milliseconds: 100));

        expect(env.exporter.csvs, hasLength(1));
        final lines = env.exporter.csvs.single.trim().split('\n');
        expect(lines.length - 1, inInclusiveRange(9, 11), reason: '~10 status em 1 s a 100 ms');
        expect(env.bloc.state.recording, isFalse);
        expect(env.bloc.state.savedPath, '/fake/telemetria_1.csv');
        expect(env.bloc.state.saveError, isNull);
        expect(env.bloc.state.saveSeq, 1);

        _teardownBloc(async, env.bloc, env.repository);
      });
    });

    test('parar sem nenhuma amostra avisa e não grava arquivo', () {
      fakeAsync((async) {
        final env = _setupBloc(async);
        env.repository.stopPolling();
        async.flushMicrotasks();

        env.bloc.add(const RecordingToggled());
        async.flushMicrotasks();
        env.bloc.add(const RecordingToggled());
        async.flushMicrotasks();

        expect(env.exporter.csvs, isEmpty);
        expect(env.bloc.state.saveError, contains('Nenhuma amostra gravada'));
        expect(env.bloc.state.saveSeq, 1);

        _teardownBloc(async, env.bloc, env.repository);
      });
    });

    test('falha ao gravar o arquivo vira saveError e a gravação termina', () {
      fakeAsync((async) {
        final env = _setupBloc(async);
        env.exporter.failWith = 'disco cheio';
        env.bloc.add(const RecordingToggled());
        async.elapse(const Duration(milliseconds: 500));
        env.bloc.add(const RecordingToggled());
        async.flushMicrotasks();

        expect(env.bloc.state.saveError, contains('disco cheio'));
        expect(env.bloc.state.savedPath, isNull);
        expect(env.bloc.state.recording, isFalse);

        _teardownBloc(async, env.bloc, env.repository);
      });
    });

    test('ligar de novo começa uma gravação nova, sem as amostras da anterior', () {
      fakeAsync((async) {
        final env = _setupBloc(async);
        env.bloc.add(const RecordingToggled());
        async.elapse(const Duration(seconds: 1));
        env.bloc.add(const RecordingToggled());
        async.flushMicrotasks();
        env.bloc.add(const RecordingToggled());
        async.elapse(const Duration(milliseconds: 500));
        env.bloc.add(const RecordingToggled());
        async.flushMicrotasks();

        final second = env.exporter.csvs.last.trim().split('\n').length - 1;
        expect(second, lessThan(8));

        _teardownBloc(async, env.bloc, env.repository);
      });
    });

    test('sem exportador o erro é publicado', () {
      fakeAsync((async) {
        final gateway = FakeMachineGateway(connectDelay: Duration.zero);
        final repository = MachineRepository(gateway);
        final bloc = TelemetryBloc(repository)..add(const TelemetryStarted());
        repository.autoConnect();
        async.elapse(const Duration(milliseconds: 10));
        repository.startPolling(intervalMs: 100);
        bloc.add(const RecordingToggled());
        async.elapse(const Duration(milliseconds: 500));
        bloc.add(const RecordingToggled());
        async.flushMicrotasks();

        expect(bloc.state.saveError, contains('indisponível'));

        _teardownBloc(async, bloc, repository);
      });
    });
  });

  group('erros observados', () {
    test('contam por origem e código, uma vez por status', () {
      fakeAsync((async) {
        final env = _setupBloc(async);
        env.gateway.injectErrorCode(9);
        env.gateway.injectLiftMotorErrors(error1: 0x11);
        async.elapse(const Duration(seconds: 1));

        final errors = env.bloc.state.observedErrors;
        final code = errors.singleWhere((e) => e.source == ErrorSource.errorCode);
        final lift = errors.singleWhere((e) => e.source == ErrorSource.liftMotor1);
        expect(code.code, 9);
        expect(code.count, inInclusiveRange(9, 11));
        expect(lift.code, 0x11);
        expect(errors.where((e) => e.source == ErrorSource.liftMotor2), isEmpty);

        _teardownBloc(async, env.bloc, env.repository);
      });
    });

    test('um código novo vira outra linha e o primeiro instante é guardado', () {
      fakeAsync((async) {
        final env = _setupBloc(async);
        env.gateway.injectErrorCode(9);
        async.elapse(const Duration(milliseconds: 500));
        final firstSeen = env.bloc.state.observedErrors.single.firstEpochMs;
        env.gateway.injectErrorCode(12);
        async.elapse(const Duration(milliseconds: 500));

        final errors = env.bloc.state.observedErrors;
        expect(errors.map((e) => e.code), containsAll([9, 12]));
        expect(errors.firstWhere((e) => e.code == 9).firstEpochMs, firstSeen);

        _teardownBloc(async, env.bloc, env.repository);
      });
    });

    test('sem erro a tabela fica vazia e Cleared não apaga o que foi observado', () {
      fakeAsync((async) {
        final env = _setupBloc(async);
        async.elapse(const Duration(milliseconds: 500));
        expect(env.bloc.state.observedErrors, isEmpty);

        env.gateway.injectErrorCode(9);
        async.elapse(const Duration(milliseconds: 500));
        env.bloc.add(const TelemetryCleared());
        async.flushMicrotasks();

        expect(env.bloc.state.buffer, isEmpty);
        expect(env.bloc.state.observedErrors, isNotEmpty);

        _teardownBloc(async, env.bloc, env.repository);
      });
    });
  });

  group('teste de taxa', () {
    ({FakeMachineGateway gateway, MachineRepository repository, RateTestCubit cubit}) setup(
      FakeAsync async, {
      bool polling = true,
      int previousInterval = 200,
    }) {
      final gateway = FakeMachineGateway(connectDelay: Duration.zero);
      final repository = MachineRepository(gateway);
      repository.autoConnect();
      async.elapse(const Duration(milliseconds: 10));
      if (polling) repository.startPolling(intervalMs: previousInterval);
      async.flushMicrotasks();
      final cubit = RateTestCubit(repository, windowSec: 2);
      return (gateway: gateway, repository: repository, cubit: cubit);
    }

    void teardown(FakeAsync async, RateTestCubit cubit, MachineRepository repository) {
      cubit.close();
      repository.dispose();
      async.flushMicrotasks();
    }

    test('mede os três intervalos e devolve o polling ao que estava', () {
      fakeAsync((async) {
        final env = setup(async, previousInterval: 150);

        unawaited(env.cubit.start(machineRunning: () => false));
        async.elapse(const Duration(seconds: 8));
        async.flushMicrotasks();

        final state = env.cubit.state;
        expect(state.phase, RateTestPhase.done);
        expect(state.results.map((r) => r.intervalMs), [200, 100, 50]);
        expect(state.results[0].hz, closeTo(5, 0.5));
        expect(state.results[1].hz, closeTo(10, 0.5));
        expect(state.results[2].hz, closeTo(20, 1));
        expect(state.results.every((r) => r.responsePct >= 90), isTrue);
        expect(state.results.every((r) => r.maxGapMs <= 250), isTrue);
        expect(env.repository.isPolling, isTrue);
        expect(env.repository.pollingIntervalMs, 150, reason: 'volta ao intervalo de antes');

        teardown(async, env.cubit, env.repository);
      });
    });

    test('se o polling estava desligado, termina desligado', () {
      fakeAsync((async) {
        final env = setup(async, polling: false);

        unawaited(env.cubit.start(machineRunning: () => false));
        async.elapse(const Duration(seconds: 8));
        async.flushMicrotasks();

        expect(env.cubit.state.phase, RateTestPhase.done);
        expect(env.repository.isPolling, isFalse);

        teardown(async, env.cubit, env.repository);
      });
    });

    test('recusa com a máquina em execução e não mexe no polling', () {
      fakeAsync((async) {
        final env = setup(async);

        unawaited(env.cubit.start(machineRunning: () => true));
        async.flushMicrotasks();

        expect(env.cubit.state.phase, RateTestPhase.failed);
        expect(env.cubit.state.message, contains('Pare a máquina'));
        expect(env.repository.pollingIntervalMs, 200);

        teardown(async, env.cubit, env.repository);
      });
    });

    test('recusa sem conexão', () {
      fakeAsync((async) {
        final repository = MachineRepository(FakeMachineGateway(connectDelay: Duration.zero));
        final cubit = RateTestCubit(repository, windowSec: 2);

        unawaited(cubit.start(machineRunning: () => false));
        async.flushMicrotasks();

        expect(cubit.state.phase, RateTestPhase.failed);
        expect(cubit.state.message, contains('Conecte-se'));

        teardown(async, cubit, repository);
      });
    });

    test('a máquina entrar em execução interrompe o teste e restaura o polling', () {
      fakeAsync((async) {
        final env = setup(async);
        var running = false;

        unawaited(env.cubit.start(machineRunning: () => running));
        async.elapse(const Duration(milliseconds: 2500));
        running = true;
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();

        expect(env.cubit.state.phase, RateTestPhase.failed);
        expect(env.cubit.state.message, contains('entrou em execução'));
        expect(env.cubit.state.results, hasLength(1), reason: 'o 1º intervalo já tinha terminado');
        expect(env.repository.pollingIntervalMs, 200);

        teardown(async, env.cubit, env.repository);
      });
    });

    test('cancelar termina como cancelado e restaura o polling', () {
      fakeAsync((async) {
        final env = setup(async);

        unawaited(env.cubit.start(machineRunning: () => false));
        async.elapse(const Duration(milliseconds: 500));
        env.cubit.cancel();
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();

        expect(env.cubit.state.phase, RateTestPhase.cancelled);
        expect(env.repository.pollingIntervalMs, 200);
        expect(env.repository.isPolling, isTrue);

        teardown(async, env.cubit, env.repository);
      });
    });

    test('a conexão cair no meio interrompe o teste', () {
      fakeAsync((async) {
        final env = setup(async);

        unawaited(env.cubit.start(machineRunning: () => false));
        async.elapse(const Duration(milliseconds: 500));
        env.repository.disconnect();
        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();

        expect(env.cubit.state.phase, RateTestPhase.failed);
        expect(env.cubit.state.message, contains('conexão'));

        teardown(async, env.cubit, env.repository);
      });
    });
  });

  group('relatório', () {
    const results = [
      RateSample(intervalMs: 200, durationSec: 15, received: 59, hz: 4.0, responsePct: 98, maxGapMs: 230),
      RateSample(intervalMs: 100, durationSec: 15, received: 123, hz: 8.2, responsePct: 82, maxGapMs: 1600),
      RateSample(intervalMs: 50, durationSec: 15, received: 4, hz: 0.3, responsePct: 1, maxGapMs: 9000),
    ];

    test('estável é o menor intervalo com resposta >= 90%; maior taxa é a de mais Hz', () {
      expect(TelemetryReport.mostStable(results)!.intervalMs, 200);
      expect(TelemetryReport.highestRate(results)!.intervalMs, 100);
      expect(TelemetryReport.mostStable([results[2]]), isNull);
      expect(TelemetryReport.highestRate(const []), isNull);
    });

    test('texto traz a tabela, a conclusão e os erros', () {
      final text = TelemetryReport.build(
        generatedAt: DateTime.utc(2026, 10, 2, 12),
        results: results,
        errors: const [
          ObservedError(source: ErrorSource.errorCode, code: 9, count: 3, firstEpochMs: 1750000000000),
        ],
        deviceInfo: const DeviceInfo(softwareNum: '9170080', versionCode: 41, produceCode: 'L850T0'),
      );

      expect(text, contains('2026-10-02T12:00:00.000Z'));
      expect(text, contains('9170080'));
      expect(text, contains('200 ms | 15 s | 59 | 4.0 | 98% | 230 ms'));
      expect(text, contains('Taxa estável (resposta ≥ 90%): intervalo de 200 ms, 4.0 Hz.'));
      expect(text, contains('Maior taxa de dados: intervalo de 100 ms, 8.2 Hz'));
      expect(text, contains('errorCode | 9 (0x9) | 3 |'));
      expect(text, contains('não confirmado pelo fabricante'));
    });

    test('sem teste e sem erros o relatório diz isso', () {
      final text = TelemetryReport.build(
        generatedAt: DateTime.utc(2026, 10, 2),
        results: const [],
        errors: const [],
      );

      expect(text, contains('Nenhum intervalo foi testado'));
      expect(text, contains('Nenhum código de erro diferente de 0'));
    });

    test('nenhum intervalo estável é dito com clareza', () {
      final text = TelemetryReport.build(
        generatedAt: DateTime.utc(2026, 10, 2),
        results: [results[2]],
        errors: const [],
      );

      expect(text, contains('nenhum intervalo testado atingiu'));
    });
  });
}
