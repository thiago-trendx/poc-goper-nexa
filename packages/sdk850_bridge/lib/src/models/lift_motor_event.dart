import 'enums.dart';
import 'machine_event.dart';

/// Fase de um ajuste de posição ou autoteste dos motores de elevação.
enum LiftMotorPhase implements WireEnum {
  started,
  completed,
  timeout;

  @override
  String get wire => name;

  static LiftMotorPhase fromWire(Object? raw) => parseWire(values, raw, 'LiftMotorPhase');
}

/// Evento `liftMotor`. [remainingSec] é o tempo restante até o timeout de segurança.
class LiftMotorEvent extends MachineEvent {
  const LiftMotorEvent({required this.phase, required this.remainingSec});

  factory LiftMotorEvent.fromMap(Map<String, Object?> map) => LiftMotorEvent(
        phase: LiftMotorPhase.fromWire(map['phase']),
        remainingSec: readInt(map, 'remainingSec'),
      );

  final LiftMotorPhase phase;
  final int remainingSec;

  @override
  String get type => 'liftMotor';

  @override
  Map<String, Object?> toMap() => {
        'type': type,
        'phase': phase.wire,
        'remainingSec': remainingSec,
      };

  @override
  List<Object?> get props => [phase, remainingSec];
}
