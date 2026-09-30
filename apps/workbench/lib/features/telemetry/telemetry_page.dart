import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../shared/widgets/feedback.dart';
import 'telemetry_bloc.dart';

/// Telemetria em tempo real. Gráficos e gravação em CSV entram na Fase 6.
class TelemetryPage extends StatelessWidget {
  const TelemetryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<TelemetryBloc>();
    return BlocBuilder<TelemetryBloc, TelemetryState>(
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
            Section(
              title: 'Taxa de atualização',
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    key: const Key('telemetry_rate'),
                    state.rateHz == null ? '— Hz' : '${state.rateHz!.toStringAsFixed(1)} Hz',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  FilledButton.icon(
                    key: const Key('telemetry_record'),
                    onPressed: () => bloc.add(const RecordingToggled()),
                    icon: Icon(state.recording ? Icons.stop : Icons.fiber_manual_record),
                    label: Text(state.recording ? 'Parar gravação (${state.recordedSamples})' : 'Gravar'),
                  ),
                  OutlinedButton(
                    key: const Key('telemetry_clear'),
                    onPressed: () => bloc.add(const TelemetryCleared()),
                    child: const Text('Limpar'),
                  ),
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
            const Text('Gráficos (força × tempo, velocidade × tempo, força × curso) e gravação em CSV: Fase 6.'),
          ],
        );
      },
    );
  }
}
