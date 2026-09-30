import 'package:poc_goper_nexa/features/device_params/profile_store.dart';

/// [ProfileStore] em memória, com falha injetável.
class MemoryProfileStore implements ProfileStore {
  final Map<String, DeviceParamsProfile> profiles = {};

  /// Quando definido, toda operação lança esta exceção.
  Exception? failure;

  void _check() {
    final error = failure;
    if (error != null) throw error;
  }

  @override
  Future<List<String>> list() async {
    _check();
    return profiles.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  @override
  Future<DeviceParamsProfile?> read(String name) async {
    _check();
    return profiles[name];
  }

  @override
  Future<void> save(DeviceParamsProfile profile) async {
    _check();
    profiles[profile.name] = profile;
  }

  @override
  Future<void> delete(String name) async {
    _check();
    profiles.remove(name);
  }
}
