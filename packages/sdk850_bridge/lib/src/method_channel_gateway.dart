import 'package:flutter/services.dart';

import 'machine_exception.dart';
import 'machine_gateway.dart';
import 'models/connection_event.dart';
import 'models/control_snapshot.dart';
import 'models/device_params.dart';
import 'models/enums.dart';
import 'models/machine_event.dart';

/// Implementação real do [MachineGateway], falando com o lado Kotlin pelos
/// canais `sdk850_bridge/methods` e `sdk850_bridge/events`.
class MethodChannelGateway implements MachineGateway {
  MethodChannelGateway({MethodChannel? methodChannel, EventChannel? eventChannel})
      : _methods = methodChannel ?? const MethodChannel('sdk850_bridge/methods'),
        _eventChannel = eventChannel ?? const EventChannel('sdk850_bridge/events');

  final MethodChannel _methods;
  final EventChannel _eventChannel;

  @override
  late final Stream<MachineEvent> events =
      _eventChannel.receiveBroadcastStream().map((raw) => MachineEvent.fromMap(asStringMap(raw)));

  /// Invoca [method] e traduz falhas do canal em [MachineException].
  Future<T?> _invoke<T>(String method, [Map<String, Object?>? arguments]) async {
    try {
      return await _methods.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw MachineException(e.code, e.message, e.details);
    } on MissingPluginException {
      throw MachineException(
        MachineErrorCode.sdkError,
        'Método nativo não implementado: $method',
      );
    }
  }

  Future<Map<String, Object?>> _invokeMap(String method) async {
    final raw = await _invoke<Object>(method);
    return asStringMap(raw);
  }

  @override
  Future<void> initialize({
    required String spFileName,
    int? baudRate,
    int? sendIntervalMs,
    int? testTimeMs,
    bool? logEnabled,
  }) =>
      _invoke<void>('initialize', {
        'spFileName': spFileName,
        if (baudRate != null) 'baudRate': baudRate,
        if (sendIntervalMs != null) 'sendIntervalMs': sendIntervalMs,
        if (testTimeMs != null) 'testTimeMs': testTimeMs,
        if (logEnabled != null) 'logEnabled': logEnabled,
      });

  @override
  Future<void> autoConnect() => _invoke<void>('autoConnect');

  @override
  Future<bool> connect(String portPath) async =>
      await _invoke<bool>('connect', {'portPath': portPath}) ?? false;

  @override
  Future<void> disconnect() => _invoke<void>('disconnect');

  @override
  Future<void> reconnect() => _invoke<void>('reconnect');

  @override
  Future<ConnectionInfo> getConnectionInfo() async =>
      ConnectionInfo.fromMap(await _invokeMap('getConnectionInfo'));

  @override
  Future<void> startPolling({int intervalMs = 200}) =>
      _invoke<void>('startPolling', {'intervalMs': intervalMs});

  @override
  Future<void> stopPolling() => _invoke<void>('stopPolling');

  @override
  Future<void> queryDeviceInfo() => _invoke<void>('queryDeviceInfo');

  @override
  Future<DeviceParams> getDeviceParams() async =>
      DeviceParams.fromMap(await _invokeMap('getDeviceParams'));

  @override
  Future<void> sendDeviceParams(DeviceParams params) =>
      _invoke<void>('sendDeviceParams', params.toMap());

  @override
  Future<ControlSnapshot> getControlParams() async =>
      ControlSnapshot.fromMap(await _invokeMap('getControlParams'));

  @override
  Future<void> start() => _invoke<void>('start');

  @override
  Future<void> stop() => _invoke<void>('stop');

  @override
  Future<void> originReset() => _invoke<void>('originReset');

  @override
  Future<void> errorRestore() => _invoke<void>('errorRestore');

  @override
  Future<void> clearData(ClearMode mode) => _invoke<void>('clearData', {'mode': mode.wire});

  @override
  Future<void> setForce(int kg) => _invoke<void>('setForce', {'kg': kg});

  @override
  Future<void> setMode(ForceMode mode) => _invoke<void>('setMode', {'mode': mode.wire});

  @override
  Future<void> setCoefficient(CoefficientKind kind, int value) =>
      _invoke<void>('setCoefficient', {'kind': kind.wire, 'value': value});

  @override
  Future<void> setElasticMax(int value) => _invoke<void>('setElasticMax', {'value': value});

  @override
  Future<void> setSafeMode(SafeMode mode) => _invoke<void>('setSafeMode', {'value': mode.value});

  @override
  Future<void> setBalancingForce(int kg) => _invoke<void>('setBalancingForce', {'kg': kg});

  @override
  Future<void> setMotorPosition({required int p1, required int p2}) =>
      _invoke<void>('setMotorPosition', {'p1': p1, 'p2': p2});

  @override
  Future<void> startMotorSelfCheck({int timeoutSec = 130}) =>
      _invoke<void>('startMotorSelfCheck', {'timeoutSec': timeoutSec});

  @override
  Future<void> installFirmware({
    required int type,
    required String filePath,
    int? timeoutMs,
  }) =>
      _invoke<void>('installFirmware', {
        'type': type,
        'filePath': filePath,
        if (timeoutMs != null) 'timeoutMs': timeoutMs,
      });

  @override
  Future<void> cancelFirmware() => _invoke<void>('cancelFirmware');

  @override
  Future<void> dispose() async {}
}
