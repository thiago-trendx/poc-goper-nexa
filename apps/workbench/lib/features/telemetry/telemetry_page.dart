import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../shared/widgets/feedback.dart';
import '../connection/connection_bloc.dart';
import '../control/control_bloc.dart';
import 'rate_test_cubit.dart';
import 'telemetry_bloc.dart';
import 'telemetry_charts.dart';
import 'telemetry_export.dart';
import 'telemetry_report.dart';

/// Telemetria em tempo real: valores, gráficos, gravação em CSV, teste de taxa e relatório.
class TelemetryPage extends StatelessWidget {
  const TelemetryPage({super.key});

  /// Segundos sem status, com o polling ligado, a partir dos quais a tela avisa.
  static const silentWarningSeconds = 3;

  /// A máquina está em execução, pelo estado local ou pelo que ela reportou.
  static bool _machineRunning(BuildContext context) => context.read<ControlBloc>().state.machineRunning;

  static Future<void> _saveReport(BuildContext context) async {
    final exporter = context.read<TelemetryExporter>();
    final text = TelemetryReport.build(
      generatedAt: DateTime.now(),
      results: context.read<RateTestCubit>().state.results,
      errors: context.read<TelemetryBloc>().state.observedErrors,
      deviceInfo: context.read<ConnectionBloc>().state.deviceInfo,
    );
    try {
      final path = await exporter.saveReport(text);
      if (context.mounted) showMessage(context, 'Relatório salvo em $path');
    } catch (e) {
      if (context.mounted) showMessage(context, 'Falha ao salvar o relatório: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<TelemetryBloc>();
    final polling = context.select((ConnectionBloc b) => b.state.pollingActive);
    return BlocConsumer<TelemetryBloc, TelemetryState>(
      listenWhen: (previous, current) => previous.saveSeq != current.saveSeq,
      listener: (context, state) {
        if (state.saveError != null) {
          showMessage(context, state.saveError!, isError: true);
        } else if (state.savedPath != null) {
          showMessage(context, 'CSV salvo em ${state.savedPath}');
        }
      },
      builder: (context, state) {
        final s = state.latest;
        final metrics = <(String, String)>[
          ('Força real', s == null ? '—' : '${s.realForce}'),
          ('Força configurada', s == null ? '—' : '${s.force} kg'),
          ('Velocidade', s == null ? '—' : '${s.speed.toStringAsFixed(1)} cm/s'),
          ('Curso', s == null ? '—' : '${s.distance} cm'),
          ('Repetições', s == null ? '—' : '${s.pullNum}'),
          ('Temperatura', s == null ? '—' : '${s.temperature.toStringAsFixed(1)} °C'),
          ('Código de erro', s == null ? '—' : '${s.errorCode}'),
          ('Estado', s == null ? '—' : s.run.name),
          ('Modo', s == null ? '—' : s.mode.name),
        ];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!polling)
              Card(
                key: const Key('telemetry_frozen'),
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: const ListTile(
                  leading: Icon(Icons.pause_circle_outline),
                  title: Text('Polling parado: os valores abaixo estão congelados.'),
                  subtitle: Text('Ligue o polling na tela Conexão para voltar a atualizar.'),
                ),
              ),
            if (polling && state.silentSeconds >= silentWarningSeconds)
              Card(
                key: const Key('telemetry_silent'),
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.portable_wifi_off),
                  title: Text('Sem resposta do controlador há ${state.silentSeconds} s.'),
                  subtitle: const Text(
                    'O polling pode estar rápido demais (na bancada, ~56 ms não obteve resposta). '
                    'Escolha um intervalo maior na tela Conexão.',
                  ),
                ),
              ),
            Section(
              title: 'Taxa de atualização',
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    key: const Key('telemetry_rate'),
                    !polling || state.rateHz == null ? '— Hz' : '${state.rateHz!.toStringAsFixed(1)} Hz',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  FilledButton.icon(
                    key: const Key('telemetry_record'),
                    onPressed: () => bloc.add(const RecordingToggled()),
                    icon: Icon(state.recording ? Icons.stop : Icons.fiber_manual_record),
                    label: Text(state.recording ? 'Salvar gravação (CSV) · ${state.recordedSamples}' : 'Gravar'),
                  ),
                  OutlinedButton(
                    key: const Key('telemetry_clear'),
                    onPressed: () => bloc.add(const TelemetryCleared()),
                    child: const Text('Limpar gráficos'),
                  ),
                  if (state.recordingFull)
                    Text(
                      'Limite de ${TelemetryBloc.maxRecordedSamples} amostras: pare a gravação para salvar.',
                      key: const Key('telemetry_record_full'),
                    ),
                  if (state.savedPath != null)
                    SelectableText('Último CSV: ${state.savedPath}', key: const Key('telemetry_saved_path')),
                ],
              ),
            ),
            Section(
              title: 'Valores',
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final (label, value) in metrics)
                    SizedBox(
                      width: 220,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(label, style: Theme.of(context).textTheme.labelMedium),
                              const SizedBox(height: 4),
                              Text(value, style: Theme.of(context).textTheme.headlineSmall),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (s != null && (s.hasError || s.hasLiftMotorError || !s.verityCodeOk))
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.warning_amber),
                  title: Text('errorCode ${s.errorCode} · motores ${s.liftMotorError1}/${s.liftMotorError2}'
                      '${s.verityCodeOk ? '' : ' · erro de verificação'}'),
                ),
              ),
            Section(title: 'Gráficos', child: TelemetryCharts(buffer: state.buffer)),
            Section(
              title: 'Códigos de erro observados',
              child: state.observedErrors.isEmpty
                  ? const Text('Nenhum código diferente de 0 visto nesta sessão.', key: Key('telemetry_no_errors'))
                  : Table(
                      key: const Key('telemetry_errors_table'),
                      defaultColumnWidth: const IntrinsicColumnWidth(),
                      children: [
                        const TableRow(children: [
                          Padding(padding: EdgeInsets.all(6), child: Text('Origem')),
                          Padding(padding: EdgeInsets.all(6), child: Text('Código')),
                          Padding(padding: EdgeInsets.all(6), child: Text('Ocorrências')),
                        ]),
                        for (final e in state.observedErrors)
                          TableRow(children: [
                            Padding(padding: const EdgeInsets.all(6), child: Text(e.source.label)),
                            Padding(
                              padding: const EdgeInsets.all(6),
                              child: Text('${e.code} (0x${e.code.toRadixString(16).toUpperCase()})'),
                            ),
                            Padding(padding: const EdgeInsets.all(6), child: Text('${e.count}')),
                          ]),
                      ],
                    ),
            ),
            const Section(title: 'Teste de taxa e relatório', child: _RateTestSection()),
          ],
        );
      },
    );
  }
}

class _RateTestSection extends StatelessWidget {
  const _RateTestSection();

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<ConnectionBloc>().state.isConnected;
    return BlocBuilder<RateTestCubit, RateTestState>(
      builder: (context, test) {
        final cubit = context.read<RateTestCubit>();
        final errors = context.select((TelemetryBloc b) => b.state.observedErrors);
        final stable = TelemetryReport.mostStable(test.results);
        final highest = TelemetryReport.highestRate(test.results);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Liga o polling em ${cubit.intervals.join(', ')} ms, ${cubit.windowSec} s cada, com a máquina parada, '
              'e mede quantos status chegam. No fim o polling volta ao que estava.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton(
                  key: const Key('rate_test_start'),
                  onPressed: connected && !test.running
                      ? () => cubit.start(machineRunning: () => TelemetryPage._machineRunning(context))
                      : null,
                  child: const Text('Iniciar teste de taxa'),
                ),
                OutlinedButton(
                  key: const Key('rate_test_cancel'),
                  onPressed: test.running ? cubit.cancel : null,
                  child: const Text('Cancelar'),
                ),
                OutlinedButton(
                  key: const Key('report_save'),
                  // Durante o teste o relatório sairia incompleto (faltando os últimos intervalos).
                  onPressed: !test.running && (test.results.isNotEmpty || errors.isNotEmpty)
                      ? () => TelemetryPage._saveReport(context)
                      : null,
                  child: const Text('Salvar relatório'),
                ),
              ],
            ),
            if (test.running && test.currentIntervalMs != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Testando ${test.currentIntervalMs} ms: ${test.elapsedSec}/${cubit.windowSec} s',
                  key: const Key('rate_test_progress'),
                ),
              ),
            if (test.message != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(test.message!, key: const Key('rate_test_message')),
              ),
            if (test.results.isNotEmpty) ...[
              const SizedBox(height: 8),
              Table(
                key: const Key('rate_test_table'),
                defaultColumnWidth: const IntrinsicColumnWidth(),
                children: [
                  const TableRow(children: [
                    Padding(padding: EdgeInsets.all(6), child: Text('Intervalo')),
                    Padding(padding: EdgeInsets.all(6), child: Text('Recebidos')),
                    Padding(padding: EdgeInsets.all(6), child: Text('Taxa')),
                    Padding(padding: EdgeInsets.all(6), child: Text('Resposta')),
                    Padding(padding: EdgeInsets.all(6), child: Text('Maior pausa')),
                  ]),
                  for (final r in test.results)
                    TableRow(children: [
                      Padding(padding: const EdgeInsets.all(6), child: Text('${r.intervalMs} ms')),
                      Padding(padding: const EdgeInsets.all(6), child: Text('${r.received}')),
                      Padding(padding: const EdgeInsets.all(6), child: Text('${r.hz.toStringAsFixed(1)} Hz')),
                      Padding(padding: const EdgeInsets.all(6), child: Text('${r.responsePct.toStringAsFixed(0)}%')),
                      Padding(padding: const EdgeInsets.all(6), child: Text('${r.maxGapMs} ms')),
                    ]),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                key: const Key('rate_test_summary'),
                stable == null
                    ? 'Nenhum intervalo testado teve resposta de ${TelemetryReport.stableResponsePct.toStringAsFixed(0)}% ou mais.'
                    : 'Mais estável (resposta ≥ ${TelemetryReport.stableResponsePct.toStringAsFixed(0)}%): '
                        '${stable.intervalMs} ms, ${stable.hz.toStringAsFixed(1)} Hz.'
                        '${highest != null && highest != stable ? ' Maior taxa de dados: ${highest.intervalMs} ms, ${highest.hz.toStringAsFixed(1)} Hz.' : ''}',
              ),
            ],
          ],
        );
      },
    );
  }
}
