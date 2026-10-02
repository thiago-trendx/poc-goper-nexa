import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';

import '../../data/machine_repository.dart';
import 'telemetry_export.dart';

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

// ---- Erros observados ----

/// De onde veio o código de erro.
enum ErrorSource {
  errorCode('errorCode'),
  liftMotor1('liftMotorError1'),
  liftMotor2('liftMotorError2'),
  verity('verityCodeError');

  const ErrorSource(this.label);

  final String label;
}

/// Um código de erro diferente de zero visto no status, com quantas vezes apareceu.
class ObservedError extends Equatable {
  const ObservedError({
    required this.source,
    required this.code,
    required this.count,
    required this.firstEpochMs,
  });

  final ErrorSource source;
  final int code;
  final int count;

  /// Relógio do aparelho (`tsEpochMs`) do primeiro status com esse código.
  final int firstEpochMs;

  ObservedError seenAgain() =>
      ObservedError(source: source, code: code, count: count + 1, firstEpochMs: firstEpochMs);

  @override
  List<Object?> get props => [source, code, count, firstEpochMs];
}

// ---- Estado ----

class TelemetryState extends Equatable {
  const TelemetryState({
    this.latest,
    this.buffer = const [],
    this.rateHz,
    this.recording = false,
    this.recordedSamples = 0,
    this.recordingFull = false,
    this.savedPath,
    this.saveError,
    this.saveSeq = 0,
    this.observedErrors = const [],
    this.silentSeconds = 0,
  });

  final DeviceStatus? latest;

  /// Últimos [TelemetryBloc.windowMs] ms de status, do mais antigo ao mais novo.
  final List<DeviceStatus> buffer;

  /// Taxa medida de status por segundo; nula com menos de dois status.
  final double? rateHz;
  final bool recording;

  /// Amostras gravadas desde que a gravação foi ligada.
  final int recordedSamples;

  /// A gravação chegou a [TelemetryBloc.maxRecordedSamples]: as seguintes não são guardadas.
  final bool recordingFull;

  /// Caminho do último CSV salvo, ou o motivo de não ter salvo; [saveSeq] muda a cada tentativa
  /// para a tela avisar de novo.
  final String? savedPath;
  final String? saveError;
  final int saveSeq;

  /// Códigos de erro diferentes de zero vistos desde que o app abriu (a tabela do relatório).
  final List<ObservedError> observedErrors;

  /// Segundos seguidos sem nenhum status novo. Zera a cada status recebido; só faz sentido
  /// enquanto o polling está ligado (quem decide avisar é a tela).
  final int silentSeconds;

  TelemetryState copyWith({
    DeviceStatus? latest,
    List<DeviceStatus>? buffer,
    double? rateHz,
    bool? recording,
    int? recordedSamples,
    bool? recordingFull,
    List<ObservedError>? observedErrors,
    int? silentSeconds,
    bool clearRate = false,
  }) =>
      TelemetryState(
        latest: latest ?? this.latest,
        buffer: buffer ?? this.buffer,
        rateHz: clearRate ? null : rateHz ?? this.rateHz,
        recording: recording ?? this.recording,
        recordedSamples: recordedSamples ?? this.recordedSamples,
        recordingFull: recordingFull ?? this.recordingFull,
        savedPath: savedPath,
        saveError: saveError,
        saveSeq: saveSeq,
        observedErrors: observedErrors ?? this.observedErrors,
        silentSeconds: silentSeconds ?? this.silentSeconds,
      );

  /// Resultado de uma tentativa de salvar o CSV (um dos dois vem nulo).
  TelemetryState withSaveResult({String? path, String? error}) => TelemetryState(
        latest: latest,
        buffer: buffer,
        rateHz: rateHz,
        recording: recording,
        recordedSamples: recordedSamples,
        recordingFull: recordingFull,
        savedPath: path,
        saveError: error,
        saveSeq: saveSeq + 1,
        observedErrors: observedErrors,
        silentSeconds: silentSeconds,
      );

  @override
  List<Object?> get props => [
        latest,
        buffer,
        rateHz,
        recording,
        recordedSamples,
        recordingFull,
        savedPath,
        saveError,
        saveSeq,
        observedErrors,
        silentSeconds,
      ];
}

// ---- Bloc ----

/// Telemetria: último status, buffer circular de 60 s e taxa medida (Hz).
///
/// A taxa usa `tsMonotonicMs` (não o relógio do app), então reflete o intervalo real entre
/// as amostras recebidas.
class TelemetryBloc extends Bloc<TelemetryEvent, TelemetryState> {
  TelemetryBloc(this._repository, {TelemetryExporter? exporter})
      : _exporter = exporter,
        super(const TelemetryState()) {
    on<TelemetryStarted>(_onStarted);
    on<RecordingToggled>(_onRecordingToggled);
    on<TelemetryCleared>(_onCleared);
    on<_SecondElapsed>(_onSecondElapsed);
  }

  /// Janela do buffer circular.
  static const windowMs = 60000;

  /// Quantas amostras recentes entram no cálculo da taxa.
  static const rateSamples = 20;

  /// Teto de amostras guardadas em memória numa gravação (~7 h a 4 Hz).
  static const maxRecordedSamples = 100000;

  final MachineRepository _repository;
  final TelemetryExporter? _exporter;
  Timer? _ticker;
  bool _statusSinceTick = false;
  final List<DeviceStatus> _recorded = [];

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
    var recordedSamples = state.recordedSamples;
    var full = state.recordingFull;
    if (state.recording && !full) {
      if (_recorded.length < maxRecordedSamples) {
        _recorded.add(status);
        recordedSamples = _recorded.length;
      }
      full = _recorded.length >= maxRecordedSamples;
    }
    return state.copyWith(
      latest: status,
      buffer: buffer,
      rateHz: _rateOf(buffer),
      recordedSamples: recordedSamples,
      recordingFull: full,
      observedErrors: _withObservedErrors(status),
      silentSeconds: 0,
    );
  }

  /// Soma os códigos de erro diferentes de zero deste status; devolve a mesma lista se não há nenhum.
  List<ObservedError>? _withObservedErrors(DeviceStatus status) {
    final seen = <(ErrorSource, int)>[
      if (status.errorCode != 0) (ErrorSource.errorCode, status.errorCode),
      if (status.liftMotorError1 != 0) (ErrorSource.liftMotor1, status.liftMotorError1),
      if (status.liftMotorError2 != 0) (ErrorSource.liftMotor2, status.liftMotorError2),
      if (status.verityCodeError != 0) (ErrorSource.verity, status.verityCodeError),
    ];
    if (seen.isEmpty) return null;
    final errors = [...state.observedErrors];
    for (final (source, code) in seen) {
      final index = errors.indexWhere((e) => e.source == source && e.code == code);
      if (index >= 0) {
        errors[index] = errors[index].seenAgain();
      } else {
        errors.add(ObservedError(source: source, code: code, count: 1, firstEpochMs: status.tsEpochMs));
      }
    }
    return errors;
  }

  static double? _rateOf(List<DeviceStatus> buffer) {
    final recent = buffer.length > rateSamples ? buffer.sublist(buffer.length - rateSamples) : buffer;
    if (recent.length < 2) return null;
    final elapsedMs = recent.last.tsMonotonicMs - recent.first.tsMonotonicMs;
    if (elapsedMs <= 0) return null;
    return (recent.length - 1) * 1000 / elapsedMs;
  }

  Future<void> _onRecordingToggled(RecordingToggled event, Emitter<TelemetryState> emit) async {
    if (!state.recording) {
      _recorded.clear();
      emit(state.copyWith(recording: true, recordedSamples: 0, recordingFull: false));
      return;
    }
    // Ao parar, grava o CSV com tudo que foi guardado.
    final rows = List<DeviceStatus>.of(_recorded);
    _recorded.clear();
    emit(state.copyWith(recording: false, recordedSamples: 0, recordingFull: false));
    if (rows.isEmpty) {
      emit(state.withSaveResult(error: 'Nenhuma amostra gravada: confira se o polling está ligado.'));
      return;
    }
    final exporter = _exporter;
    if (exporter == null) {
      emit(state.withSaveResult(error: 'Gravação de arquivo indisponível neste build.'));
      return;
    }
    try {
      emit(state.withSaveResult(path: await exporter.saveCsv(TelemetryCsv.build(rows))));
    } catch (e) {
      emit(state.withSaveResult(error: 'Falha ao salvar o CSV: $e'));
    }
  }

  /// Limpa só os gráficos; a gravação em andamento e os erros observados são mantidos.
  void _onCleared(TelemetryCleared event, Emitter<TelemetryState> emit) {
    emit(TelemetryState(
      recording: state.recording,
      recordedSamples: state.recordedSamples,
      recordingFull: state.recordingFull,
      latest: state.latest,
      observedErrors: state.observedErrors,
      saveSeq: state.saveSeq,
    ));
  }

  @override
  Future<void> close() {
    _ticker?.cancel();
    return super.close();
  }
}
