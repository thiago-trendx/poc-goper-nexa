
import 'sdk850_bridge_platform_interface.dart';

class Sdk850Bridge {
  Future<String?> getPlatformVersion() {
    return Sdk850BridgePlatform.instance.getPlatformVersion();
  }
}
