import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'sdk850_bridge_platform_interface.dart';

/// An implementation of [Sdk850BridgePlatform] that uses method channels.
class MethodChannelSdk850Bridge extends Sdk850BridgePlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('sdk850_bridge');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
