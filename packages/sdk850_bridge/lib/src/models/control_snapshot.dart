import 'package:equatable/equatable.dart';

import 'enums.dart';
import 'machine_event.dart';

/// Retrato do `ControlParams` reenviado a cada ciclo de polling.
class ControlSnapshot extends Equatable {
  const ControlSnapshot({
    this.run = RunState.stop,
    this.mode = ForceMode.standard,
    this.force = 0,
    this.centripetal = 0,
    this.centrifugal = 0,
    this.velocity = 0,
    this.elastic = 0,
    this.safeMode = SafeMode.normal,
    this.clearMode = ClearMode.none,
    this.motorPosition1 = 0,
    this.motorPosition2 = 0,
    this.motorSelfCheck = false,
    this.balancingForce = 0,
    this.maxElectric = 50,
    this.needSetOrigin = false,
    this.needErrorRestor = false,
  });

  factory ControlSnapshot.fromMap(Map<String, Object?> map) => ControlSnapshot(
        run: RunState.fromWire(map['run']),
        mode: ForceMode.fromWire(map['mode']),
        force: readInt(map, 'force'),
        centripetal: readInt(map, 'centripetal'),
        centrifugal: readInt(map, 'centrifugal'),
        velocity: readInt(map, 'velocity'),
        elastic: readInt(map, 'elastic'),
        safeMode: SafeMode.fromValue(map['safeMode']),
        clearMode: ClearMode.fromWire(map['clearMode']),
        motorPosition1: readInt(map, 'motorPosition1'),
        motorPosition2: readInt(map, 'motorPosition2'),
        motorSelfCheck: readBool(map, 'motorSelfCheck'),
        balancingForce: readInt(map, 'balancingForce'),
        maxElectric: readInt(map, 'maxElectric'),
        needSetOrigin: readBool(map, 'needSetOrigin'),
        needErrorRestor: readBool(map, 'needErrorRestor'),
      );

  final RunState run;
  final ForceMode mode;

  /// Força, em kg.
  final int force;
  final int centripetal;
  final int centrifugal;
  final int velocity;
  final int elastic;
  final SafeMode safeMode;
  final ClearMode clearMode;
  final int motorPosition1;
  final int motorPosition2;
  final bool motorSelfCheck;

  /// Força fixa de compensação de atrito no retorno, de 0 a 25 kg.
  final int balancingForce;

  /// Curso/força elástica máxima (padrão 50).
  final int maxElectric;
  final bool needSetOrigin;
  final bool needErrorRestor;

  ControlSnapshot copyWith({
    RunState? run,
    ForceMode? mode,
    int? force,
    int? centripetal,
    int? centrifugal,
    int? velocity,
    int? elastic,
    SafeMode? safeMode,
    ClearMode? clearMode,
    int? motorPosition1,
    int? motorPosition2,
    bool? motorSelfCheck,
    int? balancingForce,
    int? maxElectric,
    bool? needSetOrigin,
    bool? needErrorRestor,
  }) =>
      ControlSnapshot(
        run: run ?? this.run,
        mode: mode ?? this.mode,
        force: force ?? this.force,
        centripetal: centripetal ?? this.centripetal,
        centrifugal: centrifugal ?? this.centrifugal,
        velocity: velocity ?? this.velocity,
        elastic: elastic ?? this.elastic,
        safeMode: safeMode ?? this.safeMode,
        clearMode: clearMode ?? this.clearMode,
        motorPosition1: motorPosition1 ?? this.motorPosition1,
        motorPosition2: motorPosition2 ?? this.motorPosition2,
        motorSelfCheck: motorSelfCheck ?? this.motorSelfCheck,
        balancingForce: balancingForce ?? this.balancingForce,
        maxElectric: maxElectric ?? this.maxElectric,
        needSetOrigin: needSetOrigin ?? this.needSetOrigin,
        needErrorRestor: needErrorRestor ?? this.needErrorRestor,
      );

  /// Valor do coeficiente [kind].
  int coefficient(CoefficientKind kind) => switch (kind) {
        CoefficientKind.centripetal => centripetal,
        CoefficientKind.centrifugal => centrifugal,
        CoefficientKind.velocity => velocity,
        CoefficientKind.elastic => elastic,
      };

  Map<String, Object?> toMap() => {
        'run': run.wire,
        'mode': mode.wire,
        'force': force,
        'centripetal': centripetal,
        'centrifugal': centrifugal,
        'velocity': velocity,
        'elastic': elastic,
        'safeMode': safeMode.value,
        'clearMode': clearMode.wire,
        'motorPosition1': motorPosition1,
        'motorPosition2': motorPosition2,
        'motorSelfCheck': motorSelfCheck,
        'balancingForce': balancingForce,
        'maxElectric': maxElectric,
        'needSetOrigin': needSetOrigin,
        'needErrorRestor': needErrorRestor,
      };

  @override
  List<Object?> get props => [
        run,
        mode,
        force,
        centripetal,
        centrifugal,
        velocity,
        elastic,
        safeMode,
        clearMode,
        motorPosition1,
        motorPosition2,
        motorSelfCheck,
        balancingForce,
        maxElectric,
        needSetOrigin,
        needErrorRestor,
      ];
}
