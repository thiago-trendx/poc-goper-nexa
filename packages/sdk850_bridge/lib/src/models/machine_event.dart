import 'package:equatable/equatable.dart';

import 'connection_event.dart';
import 'device_info.dart';
import 'device_status.dart';
import 'firmware_event.dart';
import 'lift_motor_event.dart';
import 'log_entry.dart';
import 'params_ack_event.dart';

/// Evento enviado pelo lado nativo (contrato do canal, seção 6.2 do plano).
///
/// No canal, todo evento é um `Map` com o tipo no campo `type`.
abstract class MachineEvent extends Equatable {
  const MachineEvent();

  /// Converte o `Map` do canal no evento tipado.
  ///
  /// Lança [FormatException] para um `type` desconhecido.
  factory MachineEvent.fromMap(Map<Object?, Object?> map) {
    final data = asStringMap(map);
    switch (data['type']) {
      case 'connection':
        return ConnectionEvent.fromMap(data);
      case 'status':
        return DeviceStatus.fromMap(data);
      case 'deviceInfo':
        return DeviceInfo.fromMap(data);
      case 'paramsAck':
        return ParamsAckEvent.fromMap(data);
      case 'liftMotor':
        return LiftMotorEvent.fromMap(data);
      case 'firmware':
        return FirmwareEvent.fromMap(data);
      case 'log':
        return LogEntry.fromMap(data);
      default:
        throw FormatException('Tipo de evento desconhecido: ${data['type']}');
    }
  }

  /// Valor do campo `type` deste evento.
  String get type;

  Map<String, Object?> toMap();
}

/// Converte o `Map<Object?, Object?>` do canal em `Map<String, Object?>`.
Map<String, Object?> asStringMap(Object? raw) {
  if (raw is! Map) {
    throw FormatException('Esperado um Map, recebido: $raw');
  }
  return raw.map((key, value) => MapEntry(key as String, value));
}

/// Lê um inteiro obrigatório de [map], com erro claro se faltar ou tiver outro tipo.
int readInt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is int) return value;
  if (value is num && value == value.roundToDouble()) return value.toInt();
  throw FormatException('Campo "$key" deve ser inteiro, recebido: $value');
}

/// Lê um número decimal obrigatório de [map].
double readDouble(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is num) return value.toDouble();
  throw FormatException('Campo "$key" deve ser numérico, recebido: $value');
}

/// Lê um texto obrigatório de [map].
String readString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is String) return value;
  throw FormatException('Campo "$key" deve ser texto, recebido: $value');
}

/// Lê um booleano obrigatório de [map].
bool readBool(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is bool) return value;
  throw FormatException('Campo "$key" deve ser booleano, recebido: $value');
}
