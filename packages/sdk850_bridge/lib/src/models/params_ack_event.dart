import 'device_params.dart';
import 'machine_event.dart';

/// Evento `paramsAck`: `DeviceParams` devolvido pelo controlador em `SEND_PARAMS`.
class ParamsAckEvent extends MachineEvent {
  const ParamsAckEvent(this.params);

  factory ParamsAckEvent.fromMap(Map<String, Object?> map) =>
      ParamsAckEvent(DeviceParams.fromMap(map));

  final DeviceParams params;

  @override
  String get type => 'paramsAck';

  @override
  Map<String, Object?> toMap() => {'type': type, ...params.toMap()};

  @override
  List<Object?> get props => [params];
}
