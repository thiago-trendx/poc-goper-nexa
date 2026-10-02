import 'package:poc_goper_nexa/features/telemetry/telemetry_export.dart';

/// Exportador que guarda o texto em memória, sem tocar no disco.
class FakeTelemetryExporter implements TelemetryExporter {
  final List<String> csvs = [];
  final List<String> reports = [];
  Object? failWith;

  @override
  Future<String> saveCsv(String text) async {
    if (failWith != null) throw failWith!;
    csvs.add(text);
    return '/fake/telemetria_${csvs.length}.csv';
  }

  @override
  Future<String> saveReport(String text) async {
    if (failWith != null) throw failWith!;
    reports.add(text);
    return '/fake/relatorio_${reports.length}.txt';
  }
}
