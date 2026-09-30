import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';

import '../../data/machine_repository.dart';

// ---- Eventos ----

sealed class DeviceParamsEvent extends Equatable {
  const DeviceParamsEvent();

  @override
  List<Object?> get props => [];
}

/// Lê os parâmetros atuais do dispositivo.
class DeviceParamsLoaded extends DeviceParamsEvent {
  const DeviceParamsLoaded();
}

/// Alteração de um campo do formulário. [value] nulo indica texto que não é um inteiro.
class DeviceParamFieldChanged extends DeviceParamsEvent {
  const DeviceParamFieldChanged(this.field, this.value);

  final DeviceParamField field;
  final int? value;

  @override
  List<Object?> get props => [field, value];
}

/// Valida e envia os parâmetros ao controlador.
class DeviceParamsSendRequested extends DeviceParamsEvent {
  const DeviceParamsSendRequested();
}

class _AckReceived extends DeviceParamsEvent {
  const _AckReceived(this.params);

  final DeviceParams params;

  @override
  List<Object?> get props => [params];
}

// ---- Estado ----

class DeviceParamsState extends Equatable {
  const DeviceParamsState({
    required this.params,
    this.errors = const {},
    this.loading = false,
    this.ackPending = false,
    this.acknowledged = false,
    this.error,
    this.errorSeq = 0,
  });

  final DeviceParams params;

  /// Erro de validação por campo.
  final Map<DeviceParamField, String> errors;
  final bool loading;

  /// Enviado e aguardando o evento `paramsAck`.
  final bool ackPending;

  /// O último envio foi confirmado pelo controlador.
  final bool acknowledged;

  /// Falha do último comando; [errorSeq] muda a cada falha para a UI avisar de novo.
  final String? error;
  final int errorSeq;

  bool get hasErrors => errors.isNotEmpty;

  DeviceParamsState copyWith({
    DeviceParams? params,
    Map<DeviceParamField, String>? errors,
    bool? loading,
    bool? ackPending,
    bool? acknowledged,
    String? error,
  }) =>
      DeviceParamsState(
        params: params ?? this.params,
        errors: errors ?? this.errors,
        loading: loading ?? this.loading,
        ackPending: ackPending ?? this.ackPending,
        acknowledged: acknowledged ?? this.acknowledged,
        error: error,
        errorSeq: error == null ? errorSeq : errorSeq + 1,
      );

  @override
  List<Object?> get props =>
      [params, errors, loading, ackPending, acknowledged, error, errorSeq];
}

// ---- Bloc ----

/// Formulário de [DeviceParams] com validação por campo. Perfis salvos entram na Fase 3.
class DeviceParamsBloc extends Bloc<DeviceParamsEvent, DeviceParamsState> {
  DeviceParamsBloc(this._repository) : super(DeviceParamsState(params: DeviceParams.lowerBounds())) {
    // Uma única fila: ler, editar, enviar e confirmar acontecem na ordem em que chegam,
    // para uma leitura atrasada nunca sobrescrever uma edição mais nova.
    on<DeviceParamsEvent>(_onEvent, transformer: sequential());

    _ackSubscription = _repository.paramsAcks.listen((e) => add(_AckReceived(e.params)));
  }

  final MachineRepository _repository;
  late final StreamSubscription<ParamsAckEvent> _ackSubscription;

  Future<void> _onEvent(DeviceParamsEvent event, Emitter<DeviceParamsState> emit) async {
    switch (event) {
      case DeviceParamsLoaded():
        await _onLoaded(event, emit);
      case DeviceParamFieldChanged():
        _onFieldChanged(event, emit);
      case DeviceParamsSendRequested():
        await _onSendRequested(event, emit);
      case _AckReceived():
        _onAck(event, emit);
    }
  }

  Future<void> _onLoaded(DeviceParamsLoaded event, Emitter<DeviceParamsState> emit) async {
    emit(state.copyWith(loading: true, acknowledged: false));
    try {
      final params = await _repository.getDeviceParams();
      emit(state.copyWith(params: params, errors: const {}, loading: false));
    } on MachineException catch (e) {
      emit(state.copyWith(loading: false, error: e.message ?? e.code));
    }
  }

  void _onFieldChanged(DeviceParamFieldChanged event, Emitter<DeviceParamsState> emit) {
    final errors = Map<DeviceParamField, String>.of(state.errors)..remove(event.field);
    final value = event.value;
    if (value == null) {
      errors[event.field] = 'Informe um número inteiro';
      emit(state.copyWith(errors: errors, acknowledged: false));
      return;
    }
    final params = state.params.withField(event.field, value);
    final rangeError = params.validate()[event.field];
    if (rangeError != null) errors[event.field] = rangeError;
    emit(state.copyWith(params: params, errors: errors, acknowledged: false));
  }

  Future<void> _onSendRequested(
    DeviceParamsSendRequested event,
    Emitter<DeviceParamsState> emit,
  ) async {
    final errors = state.params.validate();
    if (errors.isNotEmpty || state.hasErrors) {
      emit(state.copyWith(errors: {...state.errors, ...errors}));
      return;
    }
    emit(state.copyWith(ackPending: true, acknowledged: false));
    try {
      await _repository.sendDeviceParams(state.params);
    } on MachineException catch (e) {
      emit(state.copyWith(ackPending: false, error: e.message ?? e.code));
    }
  }

  void _onAck(_AckReceived event, Emitter<DeviceParamsState> emit) {
    emit(state.copyWith(
      params: event.params,
      errors: const {},
      ackPending: false,
      acknowledged: true,
    ));
  }

  @override
  Future<void> close() async {
    await _ackSubscription.cancel();
    return super.close();
  }
}
