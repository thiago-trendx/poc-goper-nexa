import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';

import '../../data/machine_repository.dart';

// ---- Eventos ----

sealed class LiftMotorBlocEvent extends Equatable {
  const LiftMotorBlocEvent();

  @override
  List<Object?> get props => [];
}

/// Pedido que move os motores. Enquanto um pedido está em andamento, qualquer outro é descartado.
sealed class LiftMotorRequest extends LiftMotorBlocEvent {
  const LiftMotorRequest();
}

/// Ajuste das posições dos motores de elevação 1 e 2.
class PositionRequested extends LiftMotorRequest {
  const PositionRequested({required this.p1, required this.p2});

  final int p1;
  final int p2;

  @override
  List<Object?> get props => [p1, p2];
}

class SelfCheckRequested extends LiftMotorRequest {
  const SelfCheckRequested({this.timeoutSec = 130});

  final int timeoutSec;

  @override
  List<Object?> get props => [timeoutSec];
}

class _LiftMotorEventReceived extends LiftMotorBlocEvent {
  const _LiftMotorEventReceived(this.event);

  final LiftMotorEvent event;

  @override
  List<Object?> get props => [event];
}

class _StatusReceived extends LiftMotorBlocEvent {
  const _StatusReceived(this.status);

  final DeviceStatus status;

  @override
  List<Object?> get props => [status];
}

class _Tick extends LiftMotorBlocEvent {
  const _Tick();
}

// ---- Estado ----

enum LiftPhase { idle, adjusting, selfChecking, completed, timeout }

class LiftMotorState extends Equatable {
  const LiftMotorState({
    this.phase = LiftPhase.idle,
    this.remainingSec = 0,
    this.liftMotorStatus = 0,
    this.error1 = 0,
    this.error2 = 0,
    this.error,
    this.errorSeq = 0,
  });

  final LiftPhase phase;

  /// Contagem regressiva até o timeout de segurança.
  final int remainingSec;

  /// 0x00 parado, 0x01 em movimento, 0x02 em autoteste (último status recebido).
  final int liftMotorStatus;
  final int error1;
  final int error2;

  /// Falha do último comando; [errorSeq] muda a cada falha para a UI avisar de novo.
  final String? error;
  final int errorSeq;

  bool get busy => phase == LiftPhase.adjusting || phase == LiftPhase.selfChecking;

  LiftMotorState copyWith({
    LiftPhase? phase,
    int? remainingSec,
    int? liftMotorStatus,
    int? error1,
    int? error2,
    String? error,
  }) =>
      LiftMotorState(
        phase: phase ?? this.phase,
        remainingSec: remainingSec ?? this.remainingSec,
        liftMotorStatus: liftMotorStatus ?? this.liftMotorStatus,
        error1: error1 ?? this.error1,
        error2: error2 ?? this.error2,
        error: error,
        errorSeq: error == null ? errorSeq : errorSeq + 1,
      );

  @override
  List<Object?> get props =>
      [phase, remainingSec, liftMotorStatus, error1, error2, error, errorSeq];
}

// ---- Bloc ----

/// Ajuste de posição e autoteste dos motores de elevação, com contagem regressiva.
///
/// A confirmação do usuário antes de disparar é responsabilidade da UI. O timeout de
/// segurança de verdade fica no lado nativo (`LiftMotorGuard`); aqui só se reflete o evento.
class LiftMotorBloc extends Bloc<LiftMotorBlocEvent, LiftMotorState> {
  LiftMotorBloc(this._repository) : super(const LiftMotorState()) {
    on<LiftMotorRequest>(_onRequest, transformer: droppable());
    on<_LiftMotorEventReceived>(_onLiftMotorEvent, transformer: sequential());
    on<_StatusReceived>(_onStatus);
    on<_Tick>(_onTick);

    _subscriptions = [
      _repository.liftMotorEvents.listen((e) => add(_LiftMotorEventReceived(e))),
      _repository.statuses.listen((s) => add(_StatusReceived(s))),
    ];
  }

  final MachineRepository _repository;
  late final List<StreamSubscription<Object?>> _subscriptions;
  Timer? _ticker;

  /// Enquanto os motores estão em operação ([LiftMotorState.busy]) qualquer pedido novo é
  /// descartado: o handler termina assim que o comando é aceito, mas o movimento continua.
  Future<void> _onRequest(LiftMotorRequest request, Emitter<LiftMotorState> emit) async {
    if (state.busy) return;
    switch (request) {
      case PositionRequested():
        await _onPositionRequested(request, emit);
      case SelfCheckRequested():
        await _onSelfCheckRequested(request, emit);
    }
  }

  Future<void> _onPositionRequested(
    PositionRequested event,
    Emitter<LiftMotorState> emit,
  ) async {
    emit(state.copyWith(phase: LiftPhase.adjusting, remainingSec: 0));
    try {
      await _repository.setMotorPosition(p1: event.p1, p2: event.p2);
    } on MachineException catch (e) {
      emit(state.copyWith(phase: LiftPhase.idle, error: e.message ?? e.code));
    }
  }

  Future<void> _onSelfCheckRequested(
    SelfCheckRequested event,
    Emitter<LiftMotorState> emit,
  ) async {
    emit(state.copyWith(phase: LiftPhase.selfChecking, remainingSec: event.timeoutSec));
    try {
      await _repository.startMotorSelfCheck(timeoutSec: event.timeoutSec);
    } on MachineException catch (e) {
      emit(state.copyWith(phase: LiftPhase.idle, error: e.message ?? e.code));
    }
  }

  void _onLiftMotorEvent(_LiftMotorEventReceived event, Emitter<LiftMotorState> emit) {
    if (!state.busy) return; // evento sem comando nosso em andamento
    final liftEvent = event.event;
    switch (liftEvent.phase) {
      case LiftMotorPhase.started:
        _ticker?.cancel();
        _ticker = Timer.periodic(const Duration(seconds: 1), (_) => add(const _Tick()));
        emit(state.copyWith(remainingSec: liftEvent.remainingSec));
      case LiftMotorPhase.completed:
        _ticker?.cancel();
        emit(state.copyWith(phase: LiftPhase.completed, remainingSec: 0));
      case LiftMotorPhase.timeout:
        _ticker?.cancel();
        emit(state.copyWith(phase: LiftPhase.timeout, remainingSec: 0));
    }
  }

  void _onStatus(_StatusReceived event, Emitter<LiftMotorState> emit) {
    final status = event.status;
    if (status.liftMotorStatus == state.liftMotorStatus &&
        status.liftMotorError1 == state.error1 &&
        status.liftMotorError2 == state.error2) {
      return;
    }
    emit(state.copyWith(
      liftMotorStatus: status.liftMotorStatus,
      error1: status.liftMotorError1,
      error2: status.liftMotorError2,
    ));
  }

  void _onTick(_Tick event, Emitter<LiftMotorState> emit) {
    if (!state.busy || state.remainingSec <= 0) return;
    emit(state.copyWith(remainingSec: state.remainingSec - 1));
  }

  @override
  Future<void> close() async {
    _ticker?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    return super.close();
  }
}
