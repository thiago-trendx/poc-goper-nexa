import 'dart:async';

import 'package:sdk850_bridge/sdk850_bridge.dart';
import 'package:sdk850_bridge/testing.dart';

/// [FakeMachineGateway] que registra a ordem das chamadas e pode atrasar comandos,
/// para testar filas, debounce e o STOP que nunca espera outro comando.
class SpyGateway extends FakeMachineGateway {
  SpyGateway({
    super.connectDelay = Duration.zero,
    super.liftMotorAdjustDuration,
    super.selfCheckDuration,
    super.firmwareStepInterval,
    super.repetitionPeriod,
    this.commandDelay = Duration.zero,
  });

  /// Atraso aplicado a `setForce`, `setMode` e `setCoefficient`.
  Duration commandDelay;

  /// Registro das chamadas: `nome:start` e `nome:done` para comandos com atraso.
  final List<String> calls = [];

  final List<int> forces = [];

  Future<void> _delayed(String name, Future<void> Function() command) async {
    calls.add('$name:start');
    if (commandDelay > Duration.zero) await Future<void>.delayed(commandDelay);
    await command();
    calls.add('$name:done');
  }

  @override
  Future<void> setForce(int kg) {
    forces.add(kg);
    return _delayed('setForce', () => super.setForce(kg));
  }

  @override
  Future<void> setMode(ForceMode mode) => _delayed('setMode', () => super.setMode(mode));

  @override
  Future<void> setCoefficient(CoefficientKind kind, int value) =>
      _delayed('setCoefficient', () => super.setCoefficient(kind, value));

  @override
  Future<void> stop() {
    calls.add('stop:start');
    return super.stop().whenComplete(() => calls.add('stop:done'));
  }
}
