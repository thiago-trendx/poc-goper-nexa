import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';

/// Os três gráficos da telemetria, desenhados a partir do buffer circular de 60 s.
class TelemetryCharts extends StatelessWidget {
  const TelemetryCharts({super.key, required this.buffer});

  final List<DeviceStatus> buffer;

  /// Quantas amostras recentes entram no gráfico força × curso.
  static const strokeSamples = 240;

  @override
  Widget build(BuildContext context) {
    final last = buffer.isEmpty ? 0 : buffer.last.tsMonotonicMs;
    // Eixo do tempo: segundos antes da amostra mais recente (−60 a 0).
    double seconds(DeviceStatus s) => (s.tsMonotonicMs - last) / 1000;
    final recent = buffer.length > strokeSamples ? buffer.sublist(buffer.length - strokeSamples) : buffer;

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _ChartCard(
          chartKey: const Key('chart_force_time'),
          title: 'Força real × tempo',
          xLabel: 's (últimos 60 s)',
          yLabel: 'força real',
          spots: [for (final s in buffer) FlSpot(seconds(s), s.realForce.toDouble())],
          minX: -60,
          maxX: 0,
        ),
        _ChartCard(
          chartKey: const Key('chart_speed_time'),
          title: 'Velocidade × tempo',
          xLabel: 's (últimos 60 s)',
          yLabel: 'cm/s',
          spots: [for (final s in buffer) FlSpot(seconds(s), s.speed)],
          minX: -60,
          maxX: 0,
        ),
        _ChartCard(
          chartKey: const Key('chart_force_stroke'),
          title: 'Força real × curso',
          xLabel: 'curso (cm)',
          yLabel: 'força real',
          spots: [for (final s in recent) FlSpot(s.distance.toDouble(), s.realForce.toDouble())],
        ),
      ],
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.chartKey,
    required this.title,
    required this.xLabel,
    required this.yLabel,
    required this.spots,
    this.minX,
    this.maxX,
  });

  final Key chartKey;
  final String title;
  final String xLabel;
  final String yLabel;
  final List<FlSpot> spots;
  final double? minX;
  final double? maxX;

  /// Faixa do eixo com folga e sempre com altura > 0 (valores iguais quebrariam o gráfico).
  static (double, double) _range(Iterable<double> values, {double floor = 0}) {
    if (values.isEmpty) return (floor, floor + 1);
    final low = math.min(values.reduce(math.min), floor);
    final high = values.reduce(math.max);
    final pad = math.max((high - low) * 0.1, 0.5);
    return (low, high + pad);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (lowY, highY) = _range(spots.map((s) => s.y));
    final (lowX, highX) = minX != null ? (minX!, maxX!) : _range(spots.map((s) => s.x));
    return SizedBox(
      width: 420,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              Text('$yLabel × $xLabel', style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              SizedBox(
                height: 180,
                child: spots.length < 2
                    ? Center(child: Text('Aguardando dados…', key: Key('${(chartKey as ValueKey).value}_empty')))
                    : LineChart(
                        key: chartKey,
                        duration: Duration.zero,
                        LineChartData(
                          minX: lowX,
                          maxX: highX,
                          minY: lowY,
                          maxY: highY,
                          lineTouchData: const LineTouchData(enabled: false),
                          gridData: const FlGridData(show: true),
                          borderData: FlBorderData(show: true),
                          titlesData: const FlTitlesData(
                            topTitles: AxisTitles(),
                            rightTitles: AxisTitles(),
                            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 24)),
                          ),
                          lineBarsData: [
                            LineChartBarData(
                              spots: spots,
                              isCurved: false,
                              barWidth: 2,
                              color: theme.colorScheme.primary,
                              dotData: const FlDotData(show: false),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
