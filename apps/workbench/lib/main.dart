import 'package:flutter/material.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';
import 'package:sdk850_bridge/testing.dart';

import 'app.dart';
import 'shared/safety/safety_limits.dart';

/// Escolhe o gateway por `--dart-define=GATEWAY=fake|device` (padrão: `fake`, sem hardware).
/// Limite de carga do app: `--dart-define=MAX_FORCE_KG=<kg>` (padrão 30).
MachineGateway _gatewayFromEnvironment() {
  const name = String.fromEnvironment('GATEWAY', defaultValue: 'fake');
  return switch (name) {
    'fake' => FakeMachineGateway(),
    'device' => MethodChannelGateway(),
    _ => throw ArgumentError.value(name, 'GATEWAY', 'Use "fake" ou "device"'),
  };
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(WorkbenchApp(
    gateway: _gatewayFromEnvironment(),
    limits: SafetyLimits.fromEnvironment(),
  ));
}
