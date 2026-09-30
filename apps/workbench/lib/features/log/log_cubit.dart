import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';

import '../../data/machine_repository.dart';

/// Uma linha do log: pacote tx/rx, mudança de conexão ou erro de evento.
class LogLine extends Equatable {
  const LogLine({required this.tsEpochMs, required this.text});

  final int tsEpochMs;
  final String text;

  @override
  List<Object?> get props => [tsEpochMs, text];
}

/// Log em memória, limitado às últimas [maxEntries] linhas.
class LogCubit extends Cubit<List<LogLine>> {
  LogCubit(this._repository, {this.maxEntries = 2000, int Function()? nowMs})
      : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
        super(const []) {
    _subscriptions = [
      _repository.logs.listen(_onPacket),
      _repository.connections.listen(_onConnection),
      _repository.statuses.listen(_onStatus),
      _repository.eventErrors.listen((e) => _add('Erro no canal de eventos: $e')),
    ];
  }

  final MachineRepository _repository;
  final int maxEntries;
  final int Function() _nowMs;
  late final List<StreamSubscription<Object?>> _subscriptions;
  DeviceStatus? _lastLoggedStatus;

  void _onPacket(LogEntry entry) {
    final direction = entry.direction == LogDirection.tx ? 'TX' : 'RX';
    final hex = entry.hex == null ? '' : ' ${entry.hex}';
    _add('$direction ${entry.packetType}$hex', tsEpochMs: entry.tsEpochMs);
  }

  void _onConnection(ConnectionEvent event) {
    final port = event.portPath == null ? '' : ' (${event.portPath})';
    final reason = event.reason == null ? '' : ': ${event.reason}';
    _add('Conexão ${event.state.name}$port$reason');
  }

  /// Registra o status só quando algo mudou além da temperatura e dos relógios: assim o log
  /// mostra o movimento do cabo, os erros e as mudanças de estado sem uma linha por ciclo.
  void _onStatus(DeviceStatus status) {
    final previous = _lastLoggedStatus;
    if (previous != null && _sameReading(previous, status)) return;
    _lastLoggedStatus = status;
    _add(
      'STATUS ${status.run.wire} modo=${status.mode.wire} força=${status.force} real=${status.realForce} '
      'vel=${status.speed.toStringAsFixed(1)} curso=${status.distance} rep=${status.pullNum} '
      'erro=${status.errorCode} motores=${status.liftMotorStatus}/${status.liftMotorError1}/${status.liftMotorError2} '
      'verif=${status.verityCodeError} temp=${status.temperature.toStringAsFixed(1)}',
      tsEpochMs: status.tsEpochMs,
    );
  }

  static bool _sameReading(DeviceStatus a, DeviceStatus b) =>
      a.run == b.run &&
      a.mode == b.mode &&
      a.force == b.force &&
      a.realForce == b.realForce &&
      a.speed == b.speed &&
      a.distance == b.distance &&
      a.pullNum == b.pullNum &&
      a.errorCode == b.errorCode &&
      a.liftMotorStatus == b.liftMotorStatus &&
      a.liftMotorError1 == b.liftMotorError1 &&
      a.liftMotorError2 == b.liftMotorError2 &&
      a.verityCodeError == b.verityCodeError;

  void _add(String text, {int? tsEpochMs}) {
    final lines = [...state, LogLine(tsEpochMs: tsEpochMs ?? _nowMs(), text: text)];
    emit(lines.length > maxEntries ? lines.sublist(lines.length - maxEntries) : lines);
  }

  void clear() {
    _lastLoggedStatus = null;
    emit(const []);
  }

  /// Texto pronto para exportar, uma linha por entrada com o horário em ISO 8601 (UTC).
  String exportText() => state
      .map((l) => '${DateTime.fromMillisecondsSinceEpoch(l.tsEpochMs, isUtc: true).toIso8601String()} ${l.text}')
      .join('\n');

  @override
  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    return super.close();
  }
}
