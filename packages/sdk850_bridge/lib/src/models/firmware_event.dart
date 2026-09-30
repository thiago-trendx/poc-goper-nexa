import 'enums.dart';
import 'machine_event.dart';

/// Fase da instalação de firmware.
enum FirmwarePhase implements WireEnum {
  sending,
  progress,
  success,
  error;

  @override
  String get wire => name;

  static FirmwarePhase fromWire(Object? raw) => parseWire(values, raw, 'FirmwarePhase');
}

/// Evento `firmware`. [progress] (0–100) só existe na fase `progress`;
/// [message] acompanha a fase `error`.
class FirmwareEvent extends MachineEvent {
  const FirmwareEvent({required this.phase, this.progress, this.message});

  factory FirmwareEvent.fromMap(Map<String, Object?> map) => FirmwareEvent(
        phase: FirmwarePhase.fromWire(map['phase']),
        progress: map['progress'] == null ? null : readInt(map, 'progress'),
        message: map['message'] as String?,
      );

  final FirmwarePhase phase;
  final int? progress;
  final String? message;

  @override
  String get type => 'firmware';

  @override
  Map<String, Object?> toMap() => {
        'type': type,
        'phase': phase.wire,
        if (progress != null) 'progress': progress,
        if (message != null) 'message': message,
      };

  @override
  List<Object?> get props => [phase, progress, message];
}
