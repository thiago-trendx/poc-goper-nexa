import 'enums.dart';
import 'machine_event.dart';

/// Sentido do pacote registrado no log.
enum LogDirection implements WireEnum {
  tx,
  rx;

  @override
  String get wire => name;

  static LogDirection fromWire(Object? raw) => parseWire(values, raw, 'LogDirection');
}

/// Evento `log` (emitido somente em debug).
class LogEntry extends MachineEvent {
  const LogEntry({
    required this.direction,
    required this.packetType,
    required this.tsEpochMs,
    this.hex,
  });

  factory LogEntry.fromMap(Map<String, Object?> map) => LogEntry(
        direction: LogDirection.fromWire(map['direction']),
        packetType: readString(map, 'packetType'),
        hex: map['hex'] as String?,
        tsEpochMs: readInt(map, 'tsEpochMs'),
      );

  final LogDirection direction;
  final String packetType;
  final String? hex;
  final int tsEpochMs;

  @override
  String get type => 'log';

  @override
  Map<String, Object?> toMap() => {
        'type': type,
        'direction': direction.wire,
        'packetType': packetType,
        if (hex != null) 'hex': hex,
        'tsEpochMs': tsEpochMs,
      };

  @override
  List<Object?> get props => [direction, packetType, hex, tsEpochMs];
}
