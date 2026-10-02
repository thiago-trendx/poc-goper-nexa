import 'package:sdk850_bridge/sdk850_bridge.dart';

import '../../shared/files/file_saver.dart';

/// Grava os arquivos da telemetria e devolve o caminho de cada um.
abstract class TelemetryExporter {
  Future<String> saveCsv(String text);
  Future<String> saveReport(String text);
}

/// Mesmo destino do log: `Android/data/<pacote>/files`, acessível por `adb pull`.
class FileTelemetryExporter implements TelemetryExporter {
  const FileTelemetryExporter();

  @override
  Future<String> saveCsv(String text) => saveTextFile(text, prefix: 'workbench_telemetria', extension: 'csv');

  @override
  Future<String> saveReport(String text) => saveTextFile(text, prefix: 'workbench_relatorio', extension: 'txt');
}

/// CSV da telemetria: um status por linha, ponto como separador decimal e vírgula entre campos.
abstract final class TelemetryCsv {
  static const header = [
    'tsEpochMs',
    'tsMonotonicMs',
    'run',
    'mode',
    'force',
    'realForce',
    'speed',
    'distance',
    'pullNum',
    'errorCode',
    'temperature',
    'liftMotorStatus',
    'liftMotorError1',
    'liftMotorError2',
    'verityCodeError',
  ];

  static String build(Iterable<DeviceStatus> rows) {
    final buffer = StringBuffer()..writeln(header.join(','));
    for (final s in rows) {
      buffer.writeln([
        s.tsEpochMs,
        s.tsMonotonicMs,
        s.run.wire,
        s.mode.wire,
        s.force,
        s.realForce,
        s.speed.toStringAsFixed(1),
        s.distance,
        s.pullNum,
        s.errorCode,
        s.temperature.toStringAsFixed(1),
        s.liftMotorStatus,
        s.liftMotorError1,
        s.liftMotorError2,
        s.verityCodeError,
      ].join(','));
    }
    return buffer.toString();
  }
}
