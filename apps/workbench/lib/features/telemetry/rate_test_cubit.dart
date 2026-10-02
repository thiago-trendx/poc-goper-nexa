import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';

import '../../data/machine_repository.dart';

/// Resultado de um intervalo de polling testado.
class RateSample extends Equatable {
  const RateSample({
    required this.intervalMs,
    required this.durationSec,
    required this.received,
    required this.hz,
    required this.responsePct,
    required this.maxGapMs,
  });

  final int intervalMs;
  final int durationSec;

  /// Status recebidos durante a janela.
  final int received;

  /// Status por segundo, medido com `tsMonotonicMs` entre o primeiro e o último recebido.
  final double hz;

  /// Status recebidos ÷ comandos que o intervalo pedido enviaria na janela (limitado a 100%).
  final double responsePct;

  /// Maior pausa entre dois status seguidos.
  final int maxGapMs;

  @override
  List<Object?> get props => [intervalMs, durationSec, received, hz, responsePct, maxGapMs];
}

enum RateTestPhase { idle, running, done, cancelled, failed }

class RateTestState extends Equatable {
  const RateTestState({
    this.phase = RateTestPhase.idle,
    this.results = const [],
    this.currentIntervalMs,
    this.elapsedSec = 0,
    this.message,
  });

  final RateTestPhase phase;
  final List<RateSample> results;

  /// Intervalo em teste agora e quantos segundos da janela já passaram.
  final int? currentIntervalMs;
  final int elapsedSec;

  /// Motivo de a execução ter falhado ou sido cancelada.
  final String? message;

  bool get running => phase == RateTestPhase.running;

  @override
  List<Object?> get props => [phase, results, currentIntervalMs, elapsedSec, message];
}

/// Mede a taxa de status para cada intervalo de polling (200, 100 e 50 ms por padrão).
///
/// Segurança: o polling começa sempre em STOP e o teste só roda com a máquina parada; se ela
/// entrar em execução no meio, o teste é cancelado. Ao terminar (por qualquer motivo) o polling
/// volta ao estado e ao intervalo de antes.
class RateTestCubit extends Cubit<RateTestState> {
  RateTestCubit(this._repository, {this.intervals = const [200, 100, 50], this.windowSec = 15})
      : super(const RateTestState());

  final MachineRepository _repository;
  final List<int> intervals;
  final int windowSec;
  bool _cancelRequested = false;

  /// [machineRunning] diz se a máquina está em execução (estado local ou reportado).
  Future<void> start({required bool Function() machineRunning}) async {
    if (state.running) return;
    if (!_repository.isConnected) {
      emit(const RateTestState(phase: RateTestPhase.failed, message: 'Conecte-se à máquina antes de testar.'));
      return;
    }
    if (machineRunning()) {
      emit(const RateTestState(phase: RateTestPhase.failed, message: 'Pare a máquina antes de testar a taxa.'));
      return;
    }

    final wasPolling = _repository.isPolling;
    final previousInterval = _repository.pollingIntervalMs;
    _cancelRequested = false;
    final results = <RateSample>[];
    String? stopReason;
    emit(const RateTestState(phase: RateTestPhase.running));

    try {
      for (final interval in intervals) {
        final sample = await _measure(interval, machineRunning, results, (reason) => stopReason = reason);
        if (sample == null) break;
        results.add(sample);
        emit(RateTestState(phase: RateTestPhase.running, results: List.of(results)));
      }
    } on MachineException catch (e) {
      stopReason = e.message ?? e.code;
    } finally {
      try {
        if (!isClosed && _repository.isConnected) {
          if (wasPolling) {
            await _repository.startPolling(intervalMs: previousInterval);
          } else {
            await _repository.stopPolling();
          }
        }
      } on MachineException catch (e) {
        stopReason ??= 'Não foi possível restaurar o polling: ${e.message ?? e.code}';
      }
    }

    if (isClosed) return;
    emit(RateTestState(
      phase: stopReason != null
          ? (_cancelRequested ? RateTestPhase.cancelled : RateTestPhase.failed)
          : RateTestPhase.done,
      results: List.of(results),
      message: stopReason,
    ));
  }

  void cancel() => _cancelRequested = true;

  @override
  Future<void> close() {
    _cancelRequested = true;
    return super.close();
  }

  /// Mede um intervalo; devolve nulo (e informa o motivo em [stop]) se o teste precisa parar.
  Future<RateSample?> _measure(
    int intervalMs,
    bool Function() machineRunning,
    List<RateSample> done,
    void Function(String reason) stop,
  ) async {
    final stamps = <int>[];
    final subscription = _repository.statuses.listen((s) => stamps.add(s.tsMonotonicMs));
    try {
      await _repository.startPolling(intervalMs: intervalMs);
      for (var second = 0; second < windowSec; second++) {
        emit(RateTestState(
          phase: RateTestPhase.running,
          results: List.of(done),
          currentIntervalMs: intervalMs,
          elapsedSec: second,
        ));
        await Future<void>.delayed(const Duration(seconds: 1));
        if (isClosed) return null;
        if (_cancelRequested) {
          stop('Teste cancelado.');
          return null;
        }
        if (machineRunning()) {
          stop('A máquina entrou em execução: teste interrompido.');
          return null;
        }
        if (!_repository.isConnected) {
          stop('A conexão com a máquina caiu durante o teste.');
          return null;
        }
      }
    } finally {
      unawaited(subscription.cancel());
    }
    return _sampleOf(intervalMs, stamps);
  }

  RateSample _sampleOf(int intervalMs, List<int> stamps) {
    var maxGap = 0;
    for (var i = 1; i < stamps.length; i++) {
      final gap = stamps[i] - stamps[i - 1];
      if (gap > maxGap) maxGap = gap;
    }
    final spanMs = stamps.length < 2 ? 0 : stamps.last - stamps.first;
    final expected = windowSec * 1000 / intervalMs;
    return RateSample(
      intervalMs: intervalMs,
      durationSec: windowSec,
      received: stamps.length,
      hz: spanMs > 0 ? (stamps.length - 1) * 1000 / spanMs : 0,
      responsePct: (stamps.length / expected * 100).clamp(0, 100).toDouble(),
      maxGapMs: maxGap,
    );
  }
}
