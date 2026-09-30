import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Grava o texto do log em arquivo e devolve o caminho.
abstract class LogExporter {
  Future<String> save(String text);
}

/// Salva em `Android/data/<pacote>/files`, de onde o arquivo sai com `adb pull`
/// sem precisar de permissão de armazenamento.
class FileLogExporter implements LogExporter {
  const FileLogExporter();

  @override
  Future<String> save(String text) async {
    final directory = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final file = File('${directory.path}/workbench_log_$stamp.txt');
    await file.writeAsString(text);
    return file.path;
  }
}
