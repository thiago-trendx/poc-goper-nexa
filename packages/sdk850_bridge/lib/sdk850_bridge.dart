/// Ponte Flutter (somente Android) para o SDK 850 da máquina de força.
///
/// Use [MachineGateway] como contrato; `MethodChannelGateway` fala com o hardware e o
/// `FakeMachineGateway` (em `package:sdk850_bridge/testing.dart`) simula a máquina.
library;

export 'src/machine_exception.dart';
export 'src/machine_gateway.dart';
export 'src/method_channel_gateway.dart';
export 'src/models/connection_event.dart';
export 'src/models/control_snapshot.dart';
export 'src/models/device_info.dart';
export 'src/models/device_params.dart';
export 'src/models/device_status.dart';
export 'src/models/enums.dart';
export 'src/models/firmware_event.dart';
export 'src/models/lift_motor_event.dart';
export 'src/models/log_entry.dart';
export 'src/models/machine_event.dart' show MachineEvent;
export 'src/models/params_ack_event.dart';
