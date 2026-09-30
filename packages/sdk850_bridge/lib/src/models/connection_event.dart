import 'package:equatable/equatable.dart';

import 'enums.dart';
import 'machine_event.dart';

/// Estado da conexão informado pelos callbacks do SDK.
enum MachineConnectionState implements WireEnum {
  connected,
  failed,
  disconnected,
  error;

  @override
  String get wire => name;

  static MachineConnectionState fromWire(Object? raw) =>
      parseWire(values, raw, 'MachineConnectionState');
}

/// Evento `connection`.
class ConnectionEvent extends MachineEvent {
  const ConnectionEvent({required this.state, this.portPath, this.reason});

  factory ConnectionEvent.fromMap(Map<String, Object?> map) => ConnectionEvent(
        state: MachineConnectionState.fromWire(map['state']),
        portPath: map['portPath'] as String?,
        reason: map['reason'] as String?,
      );

  final MachineConnectionState state;
  final String? portPath;
  final String? reason;

  @override
  String get type => 'connection';

  @override
  Map<String, Object?> toMap() => {
        'type': type,
        'state': state.wire,
        'portPath': portPath,
        if (reason != null) 'reason': reason,
      };

  @override
  List<Object?> get props => [state, portPath, reason];
}

/// `SerialPortManager.State` do SDK.
enum PortState implements WireEnum {
  idle('IDLE'),
  scanning('SCANNING'),
  connected('CONNECTED'),
  closed('CLOSED');

  const PortState(this.wire);

  @override
  final String wire;

  static PortState fromWire(Object? raw) => parseWire(values, raw, 'PortState');
}

/// Resposta de `getConnectionInfo`.
class ConnectionInfo extends Equatable {
  const ConnectionInfo({required this.state, this.portPath});

  factory ConnectionInfo.fromMap(Map<String, Object?> map) => ConnectionInfo(
        state: PortState.fromWire(map['state']),
        portPath: map['portPath'] as String?,
      );

  final PortState state;
  final String? portPath;

  Map<String, Object?> toMap() => {'state': state.wire, 'portPath': portPath};

  @override
  List<Object?> get props => [state, portPath];
}
