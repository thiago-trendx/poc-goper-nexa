import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';

import '../../data/machine_repository.dart';
import '../../shared/safety/safety_limits.dart';

// ---- Eventos ----

sealed class ControlEvent extends Equatable {
  const ControlEvent();

  @override
  List<Object?> get props => [];
}

/// Comandos que entram numa fila única e chegam à máquina na ordem em que foram pedidos.
/// [StopPressed] e [ForceChanged] ficam de fora de propósito: veja o [ControlBloc].
sealed class ControlCommand extends ControlEvent {
  const ControlCommand();
}

class ControlLoaded extends ControlCommand {
  const ControlLoaded();
}

class StartPressed extends ControlCommand {
  const StartPressed();
}

class StopPressed extends ControlEvent {
  const StopPressed();
}

class ForceChanged extends ControlEvent {
  const ForceChanged(this.kg);

  final int kg;

  @override
  List<Object?> get props => [kg];
}

class ModeChanged extends ControlCommand {
  const ModeChanged(this.mode);

  final ForceMode mode;

  @override
  List<Object?> get props => [mode];
}

class CoefficientChanged extends ControlCommand {
  const CoefficientChanged(this.kind, this.value);

  final CoefficientKind kind;
  final int value;

  @override
  List<Object?> get props => [kind, value];
}

class ElasticMaxChanged extends ControlCommand {
  const ElasticMaxChanged(this.value);

  final int value;

  @override
  List<Object?> get props => [value];
}

class SafeModeChanged extends ControlCommand {
  const SafeModeChanged(this.mode);

  final SafeMode mode;

  @override
  List<Object?> get props => [mode];
}

class BalancingForceChanged extends ControlCommand {
  const BalancingForceChanged(this.kg);

  final int kg;

  @override
  List<Object?> get props => [kg];
}

enum OneShotKind { originReset, errorRestore, clearData }

/// Comando de disparo único. [clearMode] só vale para [OneShotKind.clearData].
class OneShotRequested extends ControlCommand {
  const OneShotRequested(this.kind, {this.clearMode = ClearMode.all});

  final OneShotKind kind;
  final ClearMode clearMode;

  @override
  List<Object?> get props => [kind, clearMode];
}

class _StatusReceived extends ControlEvent {
  const _StatusReceived(this.status);

  final DeviceStatus status;

  @override
  List<Object?> get props => [status];
}

// ---- Estado ----

class ControlState extends Equatable {
  const ControlState({
    this.snapshot = const ControlSnapshot(),
    this.reportedRun,
    this.error,
    this.errorSeq = 0,
  });

  /// Parâmetros de controle como o app os conhece (refletem o que foi enviado com sucesso).
  final ControlSnapshot snapshot;

  /// Estado de execução que a máquina informou no último status.
  final RunState? reportedRun;

  /// A máquina está em execução. Vale o que ela reportou no último status; o estado local só
  /// entra antes do primeiro status, porque ele fica desatualizado depois do STOP fixo (que não
  /// passa por este Bloc).
  bool get machineRunning => reportedRun != null ? reportedRun == RunState.running : snapshot.run == RunState.running;

  /// Falha do último comando; [errorSeq] muda a cada falha para a UI avisar de novo.
  final String? error;
  final int errorSeq;

  ControlState copyWith({
    ControlSnapshot? snapshot,
    RunState? reportedRun,
    String? error,
  }) =>
      ControlState(
        snapshot: snapshot ?? this.snapshot,
        reportedRun: reportedRun ?? this.reportedRun,
        error: error,
        errorSeq: error == null ? errorSeq : errorSeq + 1,
      );

  @override
  List<Object?> get props => [snapshot, reportedRun, error, errorSeq];
}

// ---- Bloc ----

/// Comandos de controle contínuo da máquina.
///
/// Os [ControlCommand] entram numa fila única (`sequential`), sem importar o tipo. [StopPressed]
/// nunca espera outro comando. O slider de força ([ForceChanged]) usa `restartable` com
/// debounce: só o último valor é enviado.
class ControlBloc extends Bloc<ControlEvent, ControlState> {
  ControlBloc(
    this._repository, {
    this.limits = const SafetyLimits(),
    this.forceDebounce = const Duration(milliseconds: 150),
    this.minForceKg = _defaultMinForceKg,
  }) : super(const ControlState()) {
    on<ControlCommand>(_onCommand, transformer: sequential());
    on<StopPressed>(_onStop, transformer: concurrent());
    on<ForceChanged>(_onForceChanged, transformer: restartable());
    on<_StatusReceived>(
      // O status chega o tempo todo; ele só atualiza o estado reportado e preserva o último erro.
      (event, emit) => emit(ControlState(
        snapshot: state.snapshot,
        reportedRun: event.status.run,
        error: state.error,
        errorSeq: state.errorSeq,
      )),
    );

    _statusSubscription = _repository.statuses.listen((s) => add(_StatusReceived(s)));
  }

  /// Força mínima da calibração (`DeviceParams.minForce`); o padrão é o valor do painel original.
  static int _defaultMinForceKg() => 5;

  final MachineRepository _repository;
  final SafetyLimits limits;
  final Duration forceDebounce;

  /// Lê a força mínima atual da calibração (muda se os parâmetros forem enviados).
  final int Function() minForceKg;
  late final StreamSubscription<DeviceStatus> _statusSubscription;

  Future<void> _onCommand(ControlCommand command, Emitter<ControlState> emit) => switch (command) {
        ControlLoaded e => _onLoaded(e, emit),
        StartPressed e => _onStart(e, emit),
        ModeChanged e => _onModeChanged(e, emit),
        CoefficientChanged e => _onCoefficientChanged(e, emit),
        ElasticMaxChanged e => _onElasticMaxChanged(e, emit),
        SafeModeChanged e => _onSafeModeChanged(e, emit),
        BalancingForceChanged e => _onBalancingForceChanged(e, emit),
        OneShotRequested e => _onOneShot(e, emit),
      };

  /// Executa [command]; em sucesso publica [onSuccess], em falha publica o erro.
  Future<void> _run(
    Emitter<ControlState> emit,
    Future<void> Function() command,
    ControlSnapshot Function(ControlSnapshot) onSuccess,
  ) async {
    try {
      await command();
      emit(state.copyWith(snapshot: onSuccess(state.snapshot)));
    } on MachineException catch (e) {
      emit(state.copyWith(error: e.message ?? e.code));
    }
  }

  Future<void> _onLoaded(ControlLoaded event, Emitter<ControlState> emit) async {
    try {
      emit(state.copyWith(snapshot: await _repository.getControlParams()));
    } on MachineException {
      // Sem leitura disponível: mantém os valores padrão até o primeiro comando.
    }
  }

  /// Só inicia com uma força válida (faixa da calibração e limite do app): o valor padrão dos
  /// `ControlParams` não é conhecido, então a força definida na tela é reafirmada antes do início.
  Future<void> _onStart(StartPressed event, Emitter<ControlState> emit) async {
    final min = minForceKg();
    final range = limits.forceRange(min);
    if (range == null) {
      emit(state.copyWith(
        error: 'O limite de carga do app (${limits.maxForceKg} kg) está abaixo da força mínima ($min kg)',
      ));
      return;
    }
    final force = state.snapshot.force;
    if (force < range.min || force > range.max) {
      emit(state.copyWith(error: 'Defina a carga entre ${range.min} e ${range.max} kg antes de iniciar'));
      return;
    }
    await _run(
      emit,
      () async {
        await _repository.setForce(force);
        await _repository.start();
      },
      (s) => s.copyWith(run: RunState.running),
    );
  }

  Future<void> _onStop(StopPressed event, Emitter<ControlState> emit) =>
      _run(emit, _repository.stop, (s) => s.copyWith(run: RunState.stop));

  Future<void> _onForceChanged(ForceChanged event, Emitter<ControlState> emit) async {
    final min = minForceKg();
    if (limits.forceRange(min) == null) {
      emit(state.copyWith(
        error: 'O limite de carga do app (${limits.maxForceKg} kg) está abaixo da força mínima ($min kg)',
      ));
      return;
    }
    final kg = limits.clampForce(event.kg, minForceKg: min);
    emit(state.copyWith(
      snapshot: state.snapshot.copyWith(force: kg),
      error: switch (event.kg) {
        _ when event.kg > limits.maxForceKg => 'Limite de carga do app: ${limits.maxForceKg} kg',
        _ when event.kg < min => 'Força mínima da calibração: $min kg',
        _ => null,
      },
    ));
    await Future<void>.delayed(forceDebounce);
    if (emit.isDone) return; // substituído por um valor mais novo
    try {
      await _repository.setForce(kg);
    } on MachineException catch (e) {
      emit(state.copyWith(error: e.message ?? e.code));
      await _resync(emit);
    }
  }

  /// Relê os parâmetros após uma falha, para a tela mostrar o que a máquina de fato tem.
  Future<void> _resync(Emitter<ControlState> emit) async {
    try {
      final snapshot = await _repository.getControlParams();
      emit(ControlState(
        snapshot: snapshot,
        reportedRun: state.reportedRun,
        error: state.error,
        errorSeq: state.errorSeq,
      ));
    } on MachineException {
      // Mantém o que está na tela; o erro original já foi publicado.
    }
  }

  Future<void> _onModeChanged(ModeChanged event, Emitter<ControlState> emit) => _run(
        emit,
        () => _repository.setMode(event.mode),
        (s) => s.copyWith(mode: event.mode),
      );

  Future<void> _onCoefficientChanged(CoefficientChanged event, Emitter<ControlState> emit) => _run(
        emit,
        () => _repository.setCoefficient(event.kind, event.value),
        (s) => switch (event.kind) {
          CoefficientKind.centripetal => s.copyWith(centripetal: event.value),
          CoefficientKind.centrifugal => s.copyWith(centrifugal: event.value),
          CoefficientKind.velocity => s.copyWith(velocity: event.value),
          CoefficientKind.elastic => s.copyWith(elastic: event.value),
        },
      );

  Future<void> _onElasticMaxChanged(ElasticMaxChanged event, Emitter<ControlState> emit) => _run(
        emit,
        () => _repository.setElasticMax(event.value),
        (s) => s.copyWith(maxElectric: event.value),
      );

  Future<void> _onSafeModeChanged(SafeModeChanged event, Emitter<ControlState> emit) => _run(
        emit,
        () => _repository.setSafeMode(event.mode),
        (s) => s.copyWith(safeMode: event.mode),
      );

  Future<void> _onBalancingForceChanged(
    BalancingForceChanged event,
    Emitter<ControlState> emit,
  ) =>
      _run(
        emit,
        () => _repository.setBalancingForce(event.kg),
        (s) => s.copyWith(balancingForce: event.kg),
      );

  Future<void> _onOneShot(OneShotRequested event, Emitter<ControlState> emit) => _run(
        emit,
        () => switch (event.kind) {
          OneShotKind.originReset => _repository.originReset(),
          OneShotKind.errorRestore => _repository.errorRestore(),
          OneShotKind.clearData => _repository.clearData(event.clearMode),
        },
        (s) => s, // os flags de disparo único são zerados no lado nativo
      );

  @override
  Future<void> close() async {
    await _statusSubscription.cancel();
    return super.close();
  }
}
