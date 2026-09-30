import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';

import '../../data/machine_repository.dart';

// ---- Eventos ----

sealed class FirmwareBlocEvent extends Equatable {
  const FirmwareBlocEvent();

  @override
  List<Object?> get props => [];
}

class FileSelected extends FirmwareBlocEvent {
  const FileSelected(this.path);

  final String path;

  @override
  List<Object?> get props => [path];
}

/// [type]: 1 = placa adaptadora, 2 = controlador.
class InstallRequested extends FirmwareBlocEvent {
  const InstallRequested(this.type);

  final int type;

  @override
  List<Object?> get props => [type];
}

class Cancelled extends FirmwareBlocEvent {
  const Cancelled();
}

class _FirmwareEventReceived extends FirmwareBlocEvent {
  const _FirmwareEventReceived(this.event);

  final FirmwareEvent event;

  @override
  List<Object?> get props => [event];
}

// ---- Estado ----

enum FirmwareStatus { idle, sending, progress, success, error }

class FirmwareState extends Equatable {
  const FirmwareState({
    this.status = FirmwareStatus.idle,
    this.filePath,
    this.progress = 0,
    this.message,
  });

  final FirmwareStatus status;
  final String? filePath;

  /// 0–100, na fase [FirmwareStatus.progress].
  final int progress;
  final String? message;

  bool get installing => status == FirmwareStatus.sending || status == FirmwareStatus.progress;

  FirmwareState copyWith({
    FirmwareStatus? status,
    String? filePath,
    int? progress,
    String? message,
  }) =>
      FirmwareState(
        status: status ?? this.status,
        filePath: filePath ?? this.filePath,
        progress: progress ?? this.progress,
        message: message,
      );

  @override
  List<Object?> get props => [status, filePath, progress, message];
}

// ---- Bloc ----

/// Instalação de firmware. A instalação real só entra na Fase 7, depois de a fábrica
/// confirmar o procedimento e fornecer um `.bin` de teste.
class FirmwareBloc extends Bloc<FirmwareBlocEvent, FirmwareState> {
  FirmwareBloc(this._repository) : super(const FirmwareState()) {
    on<FileSelected>((event, emit) => emit(state.copyWith(filePath: event.path)));
    on<InstallRequested>(_onInstallRequested, transformer: droppable());
    on<Cancelled>(_onCancelled, transformer: concurrent());
    on<_FirmwareEventReceived>(_onFirmwareEvent, transformer: sequential());

    _subscription = _repository.firmwareEvents.listen((e) => add(_FirmwareEventReceived(e)));
  }

  final MachineRepository _repository;
  late final StreamSubscription<FirmwareEvent> _subscription;

  Future<void> _onInstallRequested(InstallRequested event, Emitter<FirmwareState> emit) async {
    final path = state.filePath;
    if (path == null || path.trim().isEmpty) {
      emit(state.copyWith(status: FirmwareStatus.error, message: 'Selecione o arquivo .bin'));
      return;
    }
    emit(state.copyWith(status: FirmwareStatus.sending, progress: 0));
    try {
      await _repository.installFirmware(type: event.type, filePath: path);
    } on MachineException catch (e) {
      emit(state.copyWith(status: FirmwareStatus.error, message: e.message ?? e.code));
    }
  }

  Future<void> _onCancelled(Cancelled event, Emitter<FirmwareState> emit) async {
    try {
      await _repository.cancelFirmware();
    } on MachineException catch (e) {
      emit(state.copyWith(status: FirmwareStatus.error, message: e.message ?? e.code));
    }
  }

  void _onFirmwareEvent(_FirmwareEventReceived event, Emitter<FirmwareState> emit) {
    final firmware = event.event;
    switch (firmware.phase) {
      case FirmwarePhase.sending:
        emit(state.copyWith(status: FirmwareStatus.sending, progress: 0));
      case FirmwarePhase.progress:
        emit(state.copyWith(status: FirmwareStatus.progress, progress: firmware.progress ?? 0));
      case FirmwarePhase.success:
        emit(state.copyWith(status: FirmwareStatus.success, progress: 100));
      case FirmwarePhase.error:
        emit(state.copyWith(status: FirmwareStatus.error, message: firmware.message));
    }
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
