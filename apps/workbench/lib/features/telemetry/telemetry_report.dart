import 'package:sdk850_bridge/sdk850_bridge.dart';

import 'rate_test_cubit.dart';
import 'telemetry_bloc.dart';

/// Relatório de texto com a taxa de status por intervalo de polling e os códigos de erro vistos.
abstract final class TelemetryReport {
  /// Resposta mínima para um intervalo contar como estável.
  static const stableResponsePct = 90.0;

  /// Menor intervalo testado com resposta ≥ [stableResponsePct]; nulo se nenhum atingiu.
  static RateSample? mostStable(List<RateSample> results) {
    final stable = results.where((r) => r.responsePct >= stableResponsePct).toList()
      ..sort((a, b) => a.intervalMs.compareTo(b.intervalMs));
    return stable.isEmpty ? null : stable.first;
  }

  /// Intervalo que entregou mais status por segundo, estável ou não.
  static RateSample? highestRate(List<RateSample> results) {
    if (results.isEmpty) return null;
    return results.reduce((a, b) => b.hz > a.hz ? b : a);
  }

  static String build({
    required DateTime generatedAt,
    required List<RateSample> results,
    required List<ObservedError> errors,
    DeviceInfo? deviceInfo,
  }) {
    final out = StringBuffer()
      ..writeln('Relatório de telemetria — Workbench 850')
      ..writeln('Gerado em ${generatedAt.toIso8601String()}');
    if (deviceInfo != null) {
      out.writeln('Controlador: software ${deviceInfo.softwareNum}, versão ${deviceInfo.versionCode}, '
          'código de produção ${deviceInfo.produceCode}');
    }
    out
      ..writeln('Tudo abaixo é observado na bancada, não confirmado pelo fabricante.')
      ..writeln()
      ..writeln('1. Taxa de status por intervalo de polling');
    if (results.isEmpty) {
      out.writeln('Nenhum intervalo foi testado (use "Teste de taxa" na tela Telemetria).');
    } else {
      out
        ..writeln('Intervalo | Janela | Recebidos | Taxa (Hz) | Resposta | Maior pausa')
        ..writeln('--- | --- | --- | --- | --- | ---');
      for (final r in results) {
        out.writeln('${r.intervalMs} ms | ${r.durationSec} s | ${r.received} | ${r.hz.toStringAsFixed(1)} | '
            '${r.responsePct.toStringAsFixed(0)}% | ${r.maxGapMs} ms');
      }
      final stable = mostStable(results);
      final highest = highestRate(results);
      out.writeln();
      out.writeln(stable == null
          ? 'Taxa estável (resposta ≥ ${stableResponsePct.toStringAsFixed(0)}%): nenhum intervalo testado atingiu.'
          : 'Taxa estável (resposta ≥ ${stableResponsePct.toStringAsFixed(0)}%): intervalo de ${stable.intervalMs} ms, '
              '${stable.hz.toStringAsFixed(1)} Hz.');
      if (highest != null) {
        out.writeln('Maior taxa de dados: intervalo de ${highest.intervalMs} ms, ${highest.hz.toStringAsFixed(1)} Hz '
            '(resposta ${highest.responsePct.toStringAsFixed(0)}%, maior pausa ${highest.maxGapMs} ms).');
      }
    }
    out
      ..writeln()
      ..writeln('2. Códigos de erro observados');
    if (errors.isEmpty) {
      out.writeln('Nenhum código de erro diferente de 0 foi visto nesta sessão.');
    } else {
      out
        ..writeln('Origem | Código | Ocorrências | Primeira vez (relógio do aparelho)')
        ..writeln('--- | --- | --- | ---');
      for (final e in errors) {
        final first = DateTime.fromMillisecondsSinceEpoch(e.firstEpochMs, isUtc: true).toIso8601String();
        out.writeln('${e.source.label} | ${e.code} (0x${e.code.toRadixString(16).toUpperCase()}) | ${e.count} | $first');
      }
      out.writeln('O significado de cada código depende da tabela do fabricante (pergunta em aberto).');
    }
    return out.toString();
  }
}
