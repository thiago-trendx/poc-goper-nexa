import 'models/connection_event.dart';
import 'models/control_snapshot.dart';
import 'models/device_params.dart';
import 'models/enums.dart';
import 'models/machine_event.dart';

/// Interface da máquina 850: um método por item do contrato do canal (seção 6.2 do plano).
///
/// Implementações: `MethodChannelGateway` (real) e `FakeMachineGateway` (sem hardware).
/// Toda falha vira uma `MachineException` com um dos códigos de `MachineErrorCode`.
abstract class MachineGateway {
  /// Eventos do lado nativo (broadcast).
  Stream<MachineEvent> get events;

  Future<void> initialize({
    required String spFileName,
    int? baudRate,
    int? sendIntervalMs,
    int? testTimeMs,
    bool? logEnabled,
  });

  /// Varre as portas; o resultado chega por evento `connection`.
  Future<void> autoConnect();

  /// Conecta em [portPath]; o resultado final também chega por evento `connection`.
  Future<bool> connect(String portPath);
  Future<void> disconnect();
  Future<void> reconnect();
  Future<ConnectionInfo> getConnectionInfo();

  /// Inicia o loop nativo que reenvia `Cmd.control` a cada [intervalMs].
  Future<void> startPolling({int intervalMs = 200});
  Future<void> stopPolling();

  /// O resultado chega por evento `deviceInfo`.
  Future<void> queryDeviceInfo();

  Future<DeviceParams> getDeviceParams();

  /// A confirmação chega por evento `paramsAck`.
  Future<void> sendDeviceParams(DeviceParams params);
  Future<ControlSnapshot> getControlParams();

  Future<void> start();
  Future<void> stop();
  Future<void> originReset();
  Future<void> errorRestore();

  /// Disparo único: nunca deve ser reenviado continuamente.
  Future<void> clearData(ClearMode mode);

  /// [kg] em kg.
  Future<void> setForce(int kg);
  Future<void> setMode(ForceMode mode);
  Future<void> setCoefficient(CoefficientKind kind, int value);
  Future<void> setElasticMax(int value);
  Future<void> setSafeMode(SafeMode mode);

  /// [kg] de 0 a 25.
  Future<void> setBalancingForce(int kg);

  /// Para o movimento antes de alterar as posições; acompanhamento por evento `liftMotor`.
  Future<void> setMotorPosition({required int p1, required int p2});

  /// [timeoutSec] padrão do demo: 130 s.
  Future<void> startMotorSelfCheck({int timeoutSec = 130});

  /// [type]: 1 = placa adaptadora, 2 = controlador. Progresso por evento `firmware`.
  Future<void> installFirmware({
    required int type,
    required String filePath,
    int? timeoutMs,
  });
  Future<void> cancelFirmware();

  /// Libera timers e streams. O gateway não pode ser usado depois.
  Future<void> dispose();
}
