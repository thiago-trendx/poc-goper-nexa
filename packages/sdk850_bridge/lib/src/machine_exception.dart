/// Códigos de erro do contrato do canal (seção 6.1 do plano).
abstract final class MachineErrorCode {
  static const notConnected = 'NOT_CONNECTED';
  static const invalidArgs = 'INVALID_ARGS';
  static const outOfRange = 'OUT_OF_RANGE';
  static const busy = 'BUSY';
  static const sdkError = 'SDK_ERROR';
}

/// Falha de um comando enviado à máquina.
class MachineException implements Exception {
  const MachineException(this.code, [this.message, this.details]);

  /// Um dos códigos de [MachineErrorCode].
  final String code;
  final String? message;
  final Object? details;

  bool get isNotConnected => code == MachineErrorCode.notConnected;

  @override
  String toString() => 'MachineException($code${message == null ? '' : ': $message'})';
}
