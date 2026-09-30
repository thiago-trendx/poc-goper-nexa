/// Enum cujo valor trafega no canal como texto (o `name()` do enum Kotlin).
abstract interface class WireEnum {
  String get wire;
}

/// Converte o texto recebido do canal no enum correspondente.
///
/// Lança [FormatException] se o valor não existir, para que um valor novo
/// vindo do lado nativo nunca seja confundido com um valor válido.
T parseWire<T extends WireEnum>(List<T> values, Object? raw, String enumName) {
  for (final value in values) {
    if (value.wire == raw) return value;
  }
  throw FormatException('Valor inválido para $enumName: $raw');
}

/// Estado de execução (`RunState` do SDK).
enum RunState implements WireEnum {
  running('RUNNING'),
  stop('STOP'),
  originReset('ORIGIN_RESET'),
  errorRestore('ERROR_RESTORE');

  const RunState(this.wire);

  @override
  final String wire;

  static RunState fromWire(Object? raw) => parseWire(values, raw, 'RunState');
}

/// Modo de força (`ForceMode` do SDK).
enum ForceMode implements WireEnum {
  standard('STANDARD'),
  centripetal('CENTRIPETAL'),
  centrifugal('CENTRIFUGAL'),
  velocity('VELOCITY'),
  elastic('ELASTIC');

  const ForceMode(this.wire);

  @override
  final String wire;

  static ForceMode fromWire(Object? raw) => parseWire(values, raw, 'ForceMode');
}

/// Zeragem de contadores (`ClearMode` do SDK).
enum ClearMode implements WireEnum {
  none('NONE'),
  first('FIRST'),
  second('SECOND'),
  all('ALL');

  const ClearMode(this.wire);

  @override
  final String wire;

  static ClearMode fromWire(Object? raw) => parseWire(values, raw, 'ClearMode');
}

/// Modo de proteção: 0 = normal, 51 = falha/fadiga (力竭), 53 = proteção.
enum SafeMode {
  normal(0),
  fatigue(51),
  protection(53);

  const SafeMode(this.value);

  /// Valor inteiro enviado ao controlador.
  final int value;

  static SafeMode fromValue(Object? raw) {
    for (final mode in values) {
      if (mode.value == raw) return mode;
    }
    throw FormatException('Valor inválido para SafeMode: $raw');
  }
}

/// Coeficiente ajustável de `setCoefficient`.
enum CoefficientKind implements WireEnum {
  /// Concêntrico.
  centripetal,

  /// Excêntrico.
  centrifugal,

  /// Isocinético (de 0 até `velocityRange`).
  velocity,
  elastic;

  @override
  String get wire => name;

  static CoefficientKind fromWire(Object? raw) =>
      parseWire(values, raw, 'CoefficientKind');
}
