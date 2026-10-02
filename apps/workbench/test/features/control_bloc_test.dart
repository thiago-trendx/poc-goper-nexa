import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poc_goper_nexa/data/machine_repository.dart';
import 'package:poc_goper_nexa/features/control/control_bloc.dart';
import 'package:poc_goper_nexa/shared/safety/safety_limits.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';

import '../helpers/spy_gateway.dart';

const _settle = Duration(milliseconds: 40);
const _debounce = Duration(milliseconds: 20);

void main() {
  late SpyGateway gateway;
  late MachineRepository repository;

  Future<void> connect() async {
    await repository.autoConnect();
    await Future<void>.delayed(_settle);
  }

  ControlBloc build({SafetyLimits limits = const SafetyLimits()}) =>
      ControlBloc(repository, limits: limits, forceDebounce: _debounce);

  setUp(() {
    gateway = SpyGateway();
    repository = MachineRepository(gateway);
  });

  tearDown(() => repository.dispose());

  group('execução', () {
    blocTest<ControlBloc, ControlState>(
      'Start e Stop atualizam o snapshot e a máquina',
      build: build,
      act: (bloc) async {
        await connect();
        await repository.startPolling(intervalMs: 20);
        bloc.add(const ForceChanged(10));
        await Future<void>.delayed(_settle);
        bloc.add(const StartPressed());
        await Future<void>.delayed(_settle);
        expect(gateway.controlSnapshot.run, RunState.running);
        bloc.add(const StopPressed());
      },
      wait: _settle,
      verify: (bloc) {
        expect(bloc.state.snapshot.run, RunState.stop);
        expect(gateway.controlSnapshot.run, RunState.stop);
      },
    );

    blocTest<ControlBloc, ControlState>(
      'sem conexão o comando falha e o erro é publicado',
      build: build,
      act: (bloc) => bloc.add(const ModeChanged(ForceMode.elastic)),
      wait: _settle,
      expect: () => [
        const ControlState(error: 'Sem conexão com a máquina', errorSeq: 1),
      ],
    );

    blocTest<ControlBloc, ControlState>(
      'o estado reportado pela máquina segue o status recebido',
      build: build,
      act: (bloc) async {
        await connect();
        await repository.startPolling(intervalMs: 10);
        await repository.setForce(10);
        await repository.start();
      },
      wait: const Duration(milliseconds: 100),
      verify: (bloc) => expect(bloc.state.reportedRun, RunState.running),
    );

    blocTest<ControlBloc, ControlState>(
      'Loaded lê o ControlSnapshot da máquina',
      build: build,
      act: (bloc) async {
        await connect();
        await repository.setMode(ForceMode.elastic);
        bloc.add(const ControlLoaded());
      },
      wait: _settle,
      verify: (bloc) => expect(bloc.state.snapshot.mode, ForceMode.elastic),
    );
  });

  group('início seguro (Fase 4)', () {
    blocTest<ControlBloc, ControlState>(
      'Iniciar com a carga fora da faixa pede para definir a carga e não envia nada',
      build: build,
      act: (bloc) async {
        await connect();
        await repository.startPolling(intervalMs: 20);
        bloc.add(const StartPressed()); // força 0: o valor inicial é inválido
      },
      wait: _settle,
      verify: (bloc) {
        expect(bloc.state.error, 'Defina a carga entre 5 e 30 kg antes de iniciar');
        expect(bloc.state.snapshot.run, RunState.stop);
        expect(gateway.controlSnapshot.run, RunState.stop);
        expect(gateway.forces, isEmpty, reason: 'nada foi enviado à máquina');
      },
    );

    blocTest<ControlBloc, ControlState>(
      'Iniciar reafirma a carga definida e só então inicia',
      build: build,
      act: (bloc) async {
        await connect();
        await repository.startPolling(intervalMs: 20);
        bloc.add(const ForceChanged(12));
        await Future<void>.delayed(_settle);
        gateway.calls.clear();
        bloc.add(const StartPressed());
      },
      wait: _settle,
      verify: (bloc) {
        expect(gateway.forces, [12, 12], reason: 'uma vez pelo slider e outra ao iniciar');
        expect(gateway.calls, ['setForce:start', 'setForce:done']);
        expect(gateway.controlSnapshot.run, RunState.running);
        expect(bloc.state.snapshot.run, RunState.running);
      },
    );

    blocTest<ControlBloc, ControlState>(
      'Iniciar com o polling desligado publica o motivo e não inicia',
      build: build,
      act: (bloc) async {
        await connect();
        bloc.add(const ForceChanged(10));
        await Future<void>.delayed(_settle);
        bloc.add(const StartPressed());
      },
      wait: _settle,
      verify: (bloc) {
        expect(bloc.state.error, contains('Ligue o polling antes de iniciar'));
        expect(gateway.controlSnapshot.run, RunState.stop);
        expect(bloc.state.snapshot.run, RunState.stop);
      },
    );

    blocTest<ControlBloc, ControlState>(
      'com o limite do app abaixo da força mínima nenhuma carga é válida e Iniciar explica',
      build: () => build(limits: const SafetyLimits(maxForceKg: 3)),
      act: (bloc) async {
        await connect();
        await repository.startPolling(intervalMs: 20);
        bloc
          ..add(const ForceChanged(3))
          ..add(const StartPressed());
      },
      wait: _settle,
      verify: (bloc) {
        expect(bloc.state.error, 'O limite de carga do app (3 kg) está abaixo da força mínima (5 kg)');
        expect(gateway.forces, isEmpty);
        expect(gateway.controlSnapshot.run, RunState.stop);
      },
    );

    blocTest<ControlBloc, ControlState>(
      'carga abaixo da força mínima da calibração sobe para o mínimo e avisa',
      build: build,
      act: (bloc) async {
        await connect();
        bloc.add(const ForceChanged(2));
      },
      wait: _debounce * 4,
      verify: (bloc) {
        expect(bloc.state.snapshot.force, 5);
        expect(bloc.state.errorSeq, 1);
        expect(gateway.forces, [5]);
      },
    );

    blocTest<ControlBloc, ControlState>(
      'a força mínima vem da calibração atual, não de um valor fixo',
      build: () => ControlBloc(repository, forceDebounce: _debounce, minForceKg: () => 8),
      act: (bloc) async {
        await connect();
        bloc.add(const ForceChanged(6));
      },
      wait: _debounce * 4,
      verify: (bloc) {
        expect(bloc.state.snapshot.force, 8);
        expect(gateway.forces, [8]);
      },
    );
  });

  group('força', () {
    blocTest<ControlBloc, ControlState>(
      'vários valores seguidos enviam só o último (debounce)',
      build: build,
      act: (bloc) async {
        await connect();
        bloc
          ..add(const ForceChanged(5))
          ..add(const ForceChanged(10))
          ..add(const ForceChanged(15));
      },
      wait: _debounce * 4,
      verify: (bloc) {
        expect(gateway.forces, [15]);
        expect(gateway.controlSnapshot.force, 15);
        expect(bloc.state.snapshot.force, 15);
      },
    );

    blocTest<ControlBloc, ControlState>(
      'a tela mostra o valor na hora, antes do envio',
      build: build,
      act: (bloc) async {
        await connect();
        bloc.add(const ForceChanged(12));
      },
      wait: Duration.zero,
      verify: (bloc) {
        expect(bloc.state.snapshot.force, 12);
        expect(gateway.forces, isEmpty, reason: 'ainda dentro do debounce');
      },
    );

    blocTest<ControlBloc, ControlState>(
      'valor acima do limite do app é cortado e avisado',
      build: () => build(limits: const SafetyLimits(maxForceKg: 30)),
      act: (bloc) async {
        await connect();
        bloc.add(const ForceChanged(45));
      },
      wait: _debounce * 4,
      verify: (bloc) {
        expect(bloc.state.snapshot.force, 30);
        expect(gateway.forces, [30]);
        expect(bloc.state.errorSeq, 1);
      },
    );

    blocTest<ControlBloc, ControlState>(
      'valor recusado pela máquina volta para o valor real e publica o erro',
      build: () => build(limits: const SafetyLimits(maxForceKg: 150)),
      act: (bloc) async {
        await connect();
        bloc.add(const ForceChanged(120)); // a máquina aceita até 100 kg
      },
      wait: _debounce * 4,
      verify: (bloc) {
        expect(bloc.state.snapshot.force, 0);
        expect(bloc.state.errorSeq, 1);
        expect(gateway.controlSnapshot.force, 0);
      },
    );
  });

  group('parâmetros de controle', () {
    blocTest<ControlBloc, ControlState>(
      'modo, coeficientes, elástico máximo, proteção e compensação chegam à máquina',
      build: build,
      act: (bloc) async {
        await connect();
        bloc
          ..add(const ModeChanged(ForceMode.velocity))
          ..add(const CoefficientChanged(CoefficientKind.velocity, 7))
          ..add(const CoefficientChanged(CoefficientKind.centripetal, 3))
          ..add(const ElasticMaxChanged(70))
          ..add(const SafeModeChanged(SafeMode.protection))
          ..add(const BalancingForceChanged(12));
      },
      wait: _settle,
      verify: (bloc) {
        final expected = gateway.controlSnapshot;
        expect(expected.mode, ForceMode.velocity);
        expect(expected.velocity, 7);
        expect(expected.centripetal, 3);
        expect(expected.maxElectric, 70);
        expect(expected.safeMode, SafeMode.protection);
        expect(expected.balancingForce, 12);
        expect(bloc.state.snapshot, expected);
      },
    );

    blocTest<ControlBloc, ControlState>(
      'comando recusado não altera o snapshot da tela',
      build: build,
      act: (bloc) async {
        await connect();
        bloc.add(const BalancingForceChanged(30)); // máximo é 25
      },
      wait: _settle,
      verify: (bloc) {
        expect(bloc.state.snapshot.balancingForce, 0);
        expect(bloc.state.errorSeq, 1);
      },
    );

    blocTest<ControlBloc, ControlState>(
      'comandos entram em fila e chegam na ordem',
      build: build,
      act: (bloc) async {
        await connect();
        gateway.commandDelay = const Duration(milliseconds: 15);
        bloc
          ..add(const ModeChanged(ForceMode.elastic))
          ..add(const CoefficientChanged(CoefficientKind.elastic, 2))
          ..add(const ModeChanged(ForceMode.standard));
      },
      wait: const Duration(milliseconds: 120),
      verify: (_) => expect(gateway.calls, [
        'setMode:start',
        'setMode:done',
        'setCoefficient:start',
        'setCoefficient:done',
        'setMode:start',
        'setMode:done',
      ]),
    );
  });

  group('disparo único', () {
    blocTest<ControlBloc, ControlState>(
      'cada tipo de disparo único vai para o gateway sem mudar o snapshot',
      build: build,
      act: (bloc) async {
        await connect();
        gateway.injectErrorCode(9);
        bloc
          ..add(const OneShotRequested(OneShotKind.errorRestore))
          ..add(const OneShotRequested(OneShotKind.originReset))
          ..add(const OneShotRequested(OneShotKind.clearData, clearMode: ClearMode.first));
      },
      wait: _settle,
      verify: (bloc) {
        expect(bloc.state.snapshot, const ControlSnapshot());
        expect(bloc.state.error, isNull);
      },
    );
  });

  group('STOP', () {
    test('nunca espera um comando lento da fila', () async {
      final bloc = build();
      await connect();
      gateway.commandDelay = const Duration(milliseconds: 100);

      bloc.add(const ModeChanged(ForceMode.elastic)); // ocupa a fila por 100 ms
      await Future<void>.delayed(const Duration(milliseconds: 10));
      bloc.add(const StopPressed());
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(gateway.calls.indexOf('stop:done'), lessThan(gateway.calls.indexOf('setMode:done')));
      await bloc.close();
    });
  });
}
