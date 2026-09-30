import 'package:flutter_test/flutter_test.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';
import 'package:sdk850_bridge/sdk850_bridge_platform_interface.dart';
import 'package:sdk850_bridge/sdk850_bridge_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockSdk850BridgePlatform
    with MockPlatformInterfaceMixin
    implements Sdk850BridgePlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final Sdk850BridgePlatform initialPlatform = Sdk850BridgePlatform.instance;

  test('$MethodChannelSdk850Bridge is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelSdk850Bridge>());
  });

  test('getPlatformVersion', () async {
    Sdk850Bridge sdk850BridgePlugin = Sdk850Bridge();
    MockSdk850BridgePlatform fakePlatform = MockSdk850BridgePlatform();
    Sdk850BridgePlatform.instance = fakePlatform;

    expect(await sdk850BridgePlugin.getPlatformVersion(), '42');
  });
}
