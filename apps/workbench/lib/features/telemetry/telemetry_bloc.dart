import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';

import '../../data/machine_repository.dart';

// ---- Eventos ----

sealed class TelemetryEvent extends Equatable {
  const TelemetryEvent();

  @override
  List<Object?> get props => [];
}

/// Começa a acompanhar o status da máquina.
class TelemetryStarted extends TelemetryEvent {
  const TelemetryStarted();
}

class RecordingToggled extends TelemetryEvent {
  const RecordingToggled();
}

class TelemetryCleared extends TelemetryEvent {
  const TelemetryCleared();
}

class _SecondElapsed extends TelemetryEvent {
  const _SecondElapsed();
}

// ---- Estado ----

class TelemetryState extends Equatable {
  const TelemetryState({
    this.latest,
    this.buffer = const [],
    this.rateHz,
    this.recording = false,
    this.recordedSamples = 0,
    this.silentSeconds = 0,
  });

  final DeviceStatus? latest;

  /// Últimos [TelemetryBloc.windowMs] ms de status, do mais antigo ao mais novo.
  final List<DeviceStatus> buffer;

  /// Taxa medida de status por segundo; nula com menos de dois status.
  final double? rateHz;
  final bool recording;

  /// Amostras contadas desde que a gravação foi ligada. A gravação em CSV entra na Fase 6.
  final int recordedSamples;

  /// Segundos seguidos sem nenhum status novo. Zera a cada status recebido; só faz sentido
  /// enquanto o polling está ligado (quem decide avisar é a tela).
  final int silentSeconds;

  TelemetryState copyWith({
    DeviceStatus? latest,
    List<DeviceStatus>? buffer,
    double? rateHz,
    bool? recording,
    int? recordedSamples,
    int? silentSeconds,
    bool clearRate = false,
  }) =>
      TelemetryState(
        latest: latest ?? this.latest,
        buffer: buffer ?? this.buffer,
        rateHz: clearRate ? null : rateHz ?? this.rateHz,
        recording: recording ?? this.recording,
        recordedSamples: recordedSamples ?? this.recordedSamples,
        silentSeconds: silentSeconds ?? this.silentSeconds,
      );

  @override
  List<Object?> get props => [latest, buffer, rateHz, recording, recordedSamples, silentSeconds];
}

// ---- Bloc ----

/// Telemetria: último status, buffer circular de 60 s e taxa medida (Hz).
///
/// A taxa usa `tsMonotonicMs` (não o relógio do app), então reflete o intervalo real entre
/// as amostras recebidas.
class TelemetryBloc extends Bloc<TelemetryEvent, TelemetryState> {
  TelemetryBloc(this._repository) : super(const TelemetryState()) {
    on<TelemetryStarted>(_onStarted);
    on<RecordingToggled>(_onRecordingToggled);
    on<TelemetryCleared>(_onCleared);
    on<_SecondElapsed>(_onSecondElapsed);
  }

  /// Janela do buffer circular.
  static const windowMs = 60000;

  /// Quantas amostras recentes entram no cálculo da taxa.
  static const rateSamples = 20;

  final MachineRepository _repository;
  Timer? _ticker;
  bool _statusSinceTick = false;

  Future<void> _onStarted(TelemetryStarted event, Emitter<TelemetryState> emit) {
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => add(const _SecondElapsed()));
    return emit.forEach<DeviceStatus>(_repository.statuses, onData: _withStatus);
  }

  void _onSecondElapsed(_SecondElapsed event, Emitter<TelemetryState> emit) {
    final silent = _statusSinceTick ? 0 : state.silentSeconds + 1;
    _statusSinceTick = false;
    if (silent != state.silentSeconds) emit(state.copyWith(silentSeconds: silent));
  }

  TelemetryState _withStatus(DeviceStatus status) {
    _statusSinceTick = true;
    final buffer = [...state.buffer, status];
    while (buffer.length > 1 && status.tsMonotonicMs - buffer.first.tsMonotonicMs > windowMs) {
      buffer.removeAt(0);
    }
    return state.copyWith(
      latest: status,
      buffer: buffer,
      rateHz: _rateOf(buffer),
      recordedSamples: state.recording ? state.recordedSamples + 1 : state.recordedSamples,
      silentSeconds: 0,
    );
  }

  static double? _rateOf(List<DeviceStatus> buffer) {
    final recent = buffer.length > rateSamples ? buffer.sublist(buffer.length - rateSamples) : buffer;
    if (recent.length < 2) return null;
    final elapsedMs = recent.last.tsMonotonicMs - recent.first.tsMonotonicMs;
    if (elapsedMs <= 0) return null;
    return (recent.length - 1) * 1000 / elapsedMs;
  }

  void _onRecordingToggled(RecordingToggled event, Emitter<TelemetryState> emit) {
    emit(state.copyWith(recording: !state.recording, recordedSamples: 0));
  }

  void _onCleared(TelemetryCleared event, Emitter<TelemetryState> emit) {
    emit(TelemetryState(recording: state.recording, latest: state.latest));
  }

  @override
  Future<void> close() {
    _ticker?.cancel();
    return super.close();
  }
}
