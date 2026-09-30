import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';

import '../../data/machine_repository.dart';
import '../../shared/safety/safety_limits.dart';
import '../../shared/widgets/feedback.dart';
import '../connection/connection_bloc.dart';
import '../device_params/device_params_bloc.dart';
import 'control_bloc.dart';

/// Painel de controle. Ao sair desta tela envia `stop()` e para o polling.
class ControlPage extends StatefulWidget {
  const ControlPage({super.key});

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> {
  late final MachineRepository _repository;
  ClearMode _clearMode = ClearMode.all;

  @override
  void initState() {
    super.initState();
    _repository = context.read<MachineRepository>();
  }

  @override
  void dispose() {
    unawaited(_repository.haltForSafety());
    super.dispose();
  }

  static const _modeLabels = {
    ForceMode.standard: 'Padrão',
    ForceMode.centripetal: 'Concêntrico',
    ForceMode.centrifugal: 'Excêntrico',
    ForceMode.velocity: 'Isocinético',
    ForceMode.elastic: 'Elástico',
  };

  static const _clearLabels = {
    ClearMode.none: 'Nenhum',
    ClearMode.first: 'Motor 1',
    ClearMode.second: 'Motor 2',
    ClearMode.all: 'Todos',
  };

  static String _runLabel(RunState? run) => switch (run) {
        null => 'Sem status',
        RunState.running => 'Em execução',
        RunState.stop => 'Parado (força base)',
        RunState.originReset => 'Redefinindo origem',
        RunState.errorRestore => 'Reset de erro',
      };

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<ControlBloc>();
    final limits = context.read<SafetyLimits>();
    final connected = context.watch<ConnectionBloc>().state.isConnected;
    final velocityRange = context.select((DeviceParamsBloc b) => b.state.params.velocityRange);

    return BlocConsumer<ControlBloc, ControlState>(
      listenWhen: (previous, current) => previous.errorSeq != current.errorSeq,
      listener: (context, state) {
        if (state.error != null) showMessage(context, state.error!, isError: true);
      },
      builder: (context, state) {
        final snapshot = state.snapshot;
        ValueChanged<int>? onCoefficient(CoefficientKind kind) =>
            connected ? (value) => bloc.add(CoefficientChanged(kind, value)) : null;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Section(
              title: 'Estado',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Chip(
                    key: const Key('reported_run'),
                    label: Text(_runLabel(state.reportedRun)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Em STOP o motor fica em força base e qualquer comando além de iniciar é ignorado.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Section(
              title: 'Execução',
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    key: const Key('control_start'),
                    onPressed: connected ? () => bloc.add(const StartPressed()) : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Iniciar'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('control_stop'),
                    onPressed: connected ? () => bloc.add(const StopPressed()) : null,
                    icon: const Icon(Icons.pause),
                    label: const Text('Parar'),
                  ),
                ],
              ),
            ),
            Section(
              title: 'Modo',
              child: SegmentedButton<ForceMode>(
                key: const Key('control_mode'),
                segments: [
                  for (final mode in ForceMode.values)
                    ButtonSegment(value: mode, label: Text(_modeLabels[mode]!)),
                ],
                selected: {snapshot.mode},
                onSelectionChanged: connected ? (value) => bloc.add(ModeChanged(value.first)) : null,
              ),
            ),
            Section(
              title: 'Carga: ${snapshot.force} kg (limite do app: ${limits.maxForceKg} kg)',
              child: Slider(
                key: const Key('control_force'),
                value: snapshot.force.clamp(0, limits.maxForceKg).toDouble(),
                min: 0,
                max: limits.maxForceKg.toDouble(),
                divisions: limits.maxForceKg,
                label: '${snapshot.force} kg',
                onChanged: connected ? (value) => bloc.add(ForceChanged(value.round())) : null,
              ),
            ),
            Section(
              title: 'Coeficientes do modo ativo',
              child: switch (snapshot.mode) {
                ForceMode.standard => const Text('Modo padrão: sem coeficientes'),
                ForceMode.centripetal => IntStepper(
                    label: 'Concêntrico',
                    value: snapshot.centripetal,
                    onChanged: onCoefficient(CoefficientKind.centripetal),
                  ),
                ForceMode.centrifugal => IntStepper(
                    label: 'Excêntrico',
                    value: snapshot.centrifugal,
                    onChanged: onCoefficient(CoefficientKind.centrifugal),
                  ),
                ForceMode.velocity => IntStepper(
                    label: 'Isocinético (0–$velocityRange)',
                    value: snapshot.velocity,
                    max: velocityRange,
                    onChanged: onCoefficient(CoefficientKind.velocity),
                  ),
                ForceMode.elastic => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IntStepper(
                        label: 'Elástico',
                        value: snapshot.elastic,
                        onChanged: onCoefficient(CoefficientKind.elastic),
                      ),
                      IntStepper(
                        label: 'Elástico máximo',
                        value: snapshot.maxElectric,
                        onChanged: connected ? (value) => bloc.add(ElasticMaxChanged(value)) : null,
                      ),
                    ],
                  ),
              },
            ),
            Section(
              title: 'Proteção e compensação',
              child: Wrap(
                spacing: 24,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<SafeMode>(
                    key: const Key('control_safe_mode'),
                    segments: const [
                      ButtonSegment(value: SafeMode.normal, label: Text('Normal (0)')),
                      ButtonSegment(value: SafeMode.fatigue, label: Text('Falha/fadiga (51)')),
                      ButtonSegment(value: SafeMode.protection, label: Text('Proteção (53)')),
                    ],
                    selected: {snapshot.safeMode},
                    onSelectionChanged: connected ? (value) => bloc.add(SafeModeChanged(value.first)) : null,
                  ),
                  IntStepper(
                    label: 'Força de compensação (kg)',
                    value: snapshot.balancingForce,
                    max: 25,
                    onChanged: connected ? (value) => bloc.add(BalancingForceChanged(value)) : null,
                  ),
                ],
              ),
            ),
            Section(
              title: 'Comandos de disparo único',
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton(
                    key: const Key('one_shot_origin'),
                    onPressed: connected ? () => bloc.add(const OneShotRequested(OneShotKind.originReset)) : null,
                    child: const Text('Redefinir origem'),
                  ),
                  OutlinedButton(
                    key: const Key('one_shot_error'),
                    onPressed: connected ? () => bloc.add(const OneShotRequested(OneShotKind.errorRestore)) : null,
                    child: const Text('Reset de erro'),
                  ),
                  DropdownButton<ClearMode>(
                    value: _clearMode,
                    items: [
                      for (final mode in ClearMode.values.where((m) => m != ClearMode.none))
                        DropdownMenuItem(value: mode, child: Text('Limpar: ${_clearLabels[mode]}')),
                    ],
                    onChanged: (mode) => setState(() => _clearMode = mode ?? _clearMode),
                  ),
                  OutlinedButton(
                    key: const Key('one_shot_clear'),
                    onPressed: connected
                        ? () => bloc.add(OneShotRequested(OneShotKind.clearData, clearMode: _clearMode))
                        : null,
                    child: const Text('Limpar dados'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
