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
      _repository.eventErrors.listen((e) => _add('Erro no canal de eventos: $e')),
    ];
  }

  final MachineRepository _repository;
  final int maxEntries;
  final int Function() _nowMs;
  late final List<StreamSubscription<Object?>> _subscriptions;

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

  void _add(String text, {int? tsEpochMs}) {
    final lines = [...state, LogLine(tsEpochMs: tsEpochMs ?? _nowMs(), text: text)];
    emit(lines.length > maxEntries ? lines.sublist(lines.length - maxEntries) : lines);
  }

  void clear() => emit(const []);

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
