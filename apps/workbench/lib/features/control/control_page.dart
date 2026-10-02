import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';

import '../../data/machine_repository.dart';
import '../../shared/safety/safety_limits.dart';
import '../../shared/widgets/feedback.dart';
import '../connection/connection_bloc.dart';
import '../device_params/device_params_bloc.dart';
import '../lift_motor/lift_motor_bloc.dart';
import '../telemetry/telemetry_bloc.dart';
import '../telemetry/telemetry_page.dart';
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
    // Sincroniza com os ControlParams atuais ao abrir a tela (leitura local, não envia nada).
    context.read<ControlBloc>().add(const ControlLoaded());
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

  /// Disparo único: sempre com confirmação, porque altera a origem, as contagens ou o estado do controlador.
  Future<void> _confirmOneShot(ControlBloc bloc, OneShotKind kind, {ClearMode clearMode = ClearMode.all}) async {
    final (title, message, label) = switch (kind) {
      OneShotKind.originReset => (
          'Redefinir a origem?',
          'A máquina redefine a origem do curso e as contagens de repetições são zeradas. '
              'Faça isso só com a máquina parada.',
          'Redefinir',
        ),
      OneShotKind.errorRestore => (
          'Enviar reset de erro?',
          'O controlador tenta restaurar os erros. Só com a máquina parada e a área livre.',
          'Enviar',
        ),
      OneShotKind.clearData => (
          'Limpar as contagens (${_clearLabels[clearMode]})?',
          'Zera as contagens de repetições. O comando é enviado uma única vez.',
          'Limpar',
        ),
    };
    final confirmed = await confirmAction(context, title: title, message: message, confirmLabel: label);
    if (confirmed && mounted) bloc.add(OneShotRequested(kind, clearMode: clearMode));
  }

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
    final minForce = context.select((DeviceParamsBloc b) => b.state.params.minForce);
    final maxLength = context.select((DeviceParamsBloc b) => b.state.params.maxLength);
    final pollingActive = context.select((ConnectionBloc b) => b.state.pollingActive);
    final forceRange = limits.forceRange(minForce);
    final silentSeconds = context.select((TelemetryBloc b) => b.state.silentSeconds);
    final liftBusy = context.select((LiftMotorBloc b) => b.state.busy);

    return BlocConsumer<ControlBloc, ControlState>(
      listenWhen: (previous, current) => previous.errorSeq != current.errorSeq,
      listener: (context, state) {
        if (state.error != null) showMessage(context, state.error!, isError: true);
      },
      builder: (context, state) {
        final snapshot = state.snapshot;
        final forceValid = forceRange != null && snapshot.force >= forceRange.min && snapshot.force <= forceRange.max;
        final canStart = connected && pollingActive && forceValid && !liftBusy;
        // Origem e reset de erro só valem com a máquina parada (a ponte também recusa).
        final stopped = snapshot.run != RunState.running && state.reportedRun != RunState.running;
        ValueChanged<int>? onCoefficient(CoefficientKind kind) =>
            connected ? (value) => bloc.add(CoefficientChanged(kind, value)) : null;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (state.reportedRun == RunState.running && silentSeconds >= TelemetryPage.silentWarningSeconds)
              Card(
                key: const Key('control_silent_warning'),
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.warning_amber),
                  title: Text('Sem resposta do controlador há $silentSeconds s com a máquina em execução'),
                  subtitle: const Text('Toque em STOP e verifique a máquina antes de continuar.'),
                ),
              ),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        key: const Key('control_start'),
                        onPressed: canStart ? () => bloc.add(const StartPressed()) : null,
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
                  if (connected && !canStart) ...[
                    const SizedBox(height: 8),
                    Text(
                      key: const Key('control_start_hint'),
                      liftBusy
                          ? 'Os motores de elevação estão em operação: aguarde o fim para iniciar.'
                          : !pollingActive
                          ? 'Para iniciar, ligue o polling na tela Conexão: sem ele a máquina não recebe o STOP.'
                          : forceRange == null
                              ? 'O limite de carga do app (${limits.maxForceKg} kg) está abaixo da força mínima ($minForce kg).'
                              : 'Para iniciar, ajuste a carga entre ${forceRange.min} e ${forceRange.max} kg.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
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
              title: forceRange == null
                  ? 'Carga: indisponível (limite do app ${limits.maxForceKg} kg abaixo da força mínima $minForce kg)'
                  : forceValid
                      ? 'Carga: ${snapshot.force} kg (faixa ${forceRange.min} a ${forceRange.max} kg; limite do app: ${limits.maxForceKg} kg)'
                      : 'Carga: ${snapshot.force} kg, fora da faixa (${forceRange.min} a ${forceRange.max} kg): ajuste o slider',
              child: Slider(
                key: const Key('control_force'),
                value: forceRange == null ? 0 : snapshot.force.clamp(forceRange.min, forceRange.max).toDouble(),
                min: forceRange == null ? 0 : forceRange.min.toDouble(),
                max: forceRange == null ? 1 : (forceRange.max == forceRange.min ? forceRange.max + 1.0 : forceRange.max.toDouble()),
                divisions: forceRange == null || forceRange.max == forceRange.min ? null : forceRange.max - forceRange.min,
                label: '${snapshot.force} kg',
                onChanged: connected && forceRange != null ? (value) => bloc.add(ForceChanged(value.round())) : null,
              ),
            ),
            Section(
              title: 'Coeficientes do modo ativo',
              child: switch (snapshot.mode) {
                ForceMode.standard => const Text('Modo padrão: sem coeficientes'),
                ForceMode.centripetal => IntStepper(
                    label: 'Concêntrico (0–6)',
                    value: snapshot.centripetal,
                    max: 6,
                    onChanged: onCoefficient(CoefficientKind.centripetal),
                  ),
                ForceMode.centrifugal => IntStepper(
                    label: 'Excêntrico (0–6)',
                    value: snapshot.centrifugal,
                    max: 6,
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
                        label: 'Elástico (0–10)',
                        value: snapshot.elastic,
                        max: 10,
                        onChanged: onCoefficient(CoefficientKind.elastic),
                      ),
                      IntStepper(
                        label: 'Curso elástico (1–$maxLength cm)',
                        value: snapshot.maxElectric,
                        min: 1,
                        max: maxLength,
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
                    onPressed: connected && stopped && !liftBusy
                        ? () => _confirmOneShot(bloc, OneShotKind.originReset)
                        : null,
                    child: const Text('Redefinir origem'),
                  ),
                  OutlinedButton(
                    key: const Key('one_shot_error'),
                    onPressed: connected && stopped && !liftBusy
                        ? () => _confirmOneShot(bloc, OneShotKind.errorRestore)
                        : null,
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
                    onPressed: connected && !liftBusy
                        ? () => _confirmOneShot(bloc, OneShotKind.clearData, clearMode: _clearMode)
                        : null,
                    child: const Text('Limpar dados'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Redefinir origem e Reset de erro só com a máquina parada. Cada comando é enviado uma única vez.',
                key: const Key('one_shot_hint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        );
      },
    );
  }
}
