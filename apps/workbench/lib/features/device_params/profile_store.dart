import 'dart:convert';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';

/// Conjunto de parâmetros de calibração salvo com um nome.
class DeviceParamsProfile extends Equatable {
  const DeviceParamsProfile({required this.name, required this.params, required this.savedAt});

  factory DeviceParamsProfile.fromJson(Map<String, Object?> json) => DeviceParamsProfile(
        name: json['name'] as String,
        params: DeviceParams.fromMap(Map<String, Object?>.from(json['params'] as Map)),
        savedAt: DateTime.parse(json['savedAt'] as String),
      );

  final String name;
  final DeviceParams params;
  final DateTime savedAt;

  Map<String, Object?> toJson() => {
        'name': name,
        'savedAt': savedAt.toUtc().toIso8601String(),
        'params': params.toMap(),
      };

  @override
  List<Object?> get props => [name, params, savedAt];
}

/// Perfis de `DeviceParams` salvos em JSON, um arquivo por perfil.
abstract class ProfileStore {
  /// Nomes válidos: 1 a 40 caracteres entre letras, números, espaço, `-`, `_` e `.`, sem
  /// começar ou terminar com espaço ou ponto. Devolve a mensagem de erro, ou `null` se válido.
  static String? validateName(String name) {
    if (name.isEmpty || name.length > 40) return 'O nome deve ter de 1 a 40 caracteres';
    if (!RegExp(r'^[A-Za-z0-9_-][A-Za-z0-9 _.-]*$').hasMatch(name) || name.endsWith(' ') || name.endsWith('.')) {
      return 'Use letras, números, espaço, "-", "_" e "."; sem começar com espaço ou ponto nem terminar com espaço ou ponto';
    }
    return null;
  }

  /// Nomes dos perfis salvos, em ordem alfabética.
  Future<List<String>> list();

  Future<DeviceParamsProfile?> read(String name);

  /// Grava (ou substitui) o perfil [profile.name].
  Future<void> save(DeviceParamsProfile profile);

  Future<void> delete(String name);
}

/// [ProfileStore] em arquivos `<diretório>/<nome>.json`.
class FileProfileStore implements ProfileStore {
  FileProfileStore({Future<Directory> Function()? directory}) : _directory = directory ?? _defaultDirectory;

  final Future<Directory> Function() _directory;

  static Future<Directory> _defaultDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory('${documents.path}/profiles');
  }

  Future<File> _file(String name) async {
    final problem = ProfileStore.validateName(name);
    if (problem != null) throw ArgumentError.value(name, 'name', problem);
    final directory = await _directory();
    return File('${directory.path}/$name.json');
  }

  @override
  Future<List<String>> list() async {
    final directory = await _directory();
    if (!await directory.exists()) return const [];
    final names = <String>[];
    await for (final entity in directory.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        final base = entity.uri.pathSegments.last;
        names.add(base.substring(0, base.length - '.json'.length));
      }
    }
    return names..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  @override
  Future<DeviceParamsProfile?> read(String name) async {
    final file = await _file(name);
    if (!await file.exists()) return null;
    final json = jsonDecode(await file.readAsString());
    return DeviceParamsProfile.fromJson(Map<String, Object?>.from(json as Map));
  }

  @override
  Future<void> save(DeviceParamsProfile profile) async {
    final file = await _file(profile.name);
    await file.parent.create(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(profile.toJson()));
  }

  @override
  Future<void> delete(String name) async {
    final file = await _file(name);
    if (await file.exists()) await file.delete();
  }
}
