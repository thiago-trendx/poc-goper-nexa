import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'sdk850_bridge_method_channel.dart';

abstract class Sdk850BridgePlatform extends PlatformInterface {
  /// Constructs a Sdk850BridgePlatform.
  Sdk850BridgePlatform() : super(token: _token);

  static final Object _token = Object();

  static Sdk850BridgePlatform _instance = MethodChannelSdk850Bridge();

  /// The default instance of [Sdk850BridgePlatform] to use.
  ///
  /// Defaults to [MethodChannelSdk850Bridge].
  static Sdk850BridgePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [Sdk850BridgePlatform] when
  /// they register themselves.
  static set instance(Sdk850BridgePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
