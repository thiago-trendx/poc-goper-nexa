import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Grava [text] em `<prefixo>_<data>.<extensão>` e devolve o caminho.
///
/// Salva em `Android/data/<pacote>/files`, de onde o arquivo sai com `adb pull` sem precisar de
/// permissão de armazenamento; sem armazenamento externo, usa os documentos do app.
Future<String> saveTextFile(String text, {required String prefix, required String extension}) async {
  final directory = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
  final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
  final file = File('${directory.path}/${prefix}_$stamp.$extension');
  await file.writeAsString(text);
  return file.path;
}
