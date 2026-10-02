import '../../shared/files/file_saver.dart';

/// Grava o texto do log em arquivo e devolve o caminho.
abstract class LogExporter {
  Future<String> save(String text);
}

/// Salva em `Android/data/<pacote>/files`, de onde o arquivo sai com `adb pull`
/// sem precisar de permissão de armazenamento.
class FileLogExporter implements LogExporter {
  const FileLogExporter();

  @override
  Future<String> save(String text) => saveTextFile(text, prefix: 'workbench_log', extension: 'txt');
}
