import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';

import '../../data/machine_repository.dart';
import 'profile_store.dart';

// ---- Eventos ----

sealed class DeviceParamsEvent extends Equatable {
  const DeviceParamsEvent();

  @override
  List<Object?> get props => [];
}

/// Lê os parâmetros guardados no app (cache do SDK). O controlador não tem comando de leitura.
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

/// Valida e envia os parâmetros ao controlador. Só acontece por ação explícita do usuário.
class DeviceParamsSendRequested extends DeviceParamsEvent {
  const DeviceParamsSendRequested();
}

class ProfilesRefreshed extends DeviceParamsEvent {
  const ProfilesRefreshed();
}

/// Salva os valores do formulário com o nome [name].
class ProfileSaved extends DeviceParamsEvent {
  const ProfileSaved(this.name);

  final String name;

  @override
  List<Object?> get props => [name];
}

/// Carrega o perfil [name] no formulário, sem enviar.
class ProfileLoaded extends DeviceParamsEvent {
  const ProfileLoaded(this.name);

  final String name;

  @override
  List<Object?> get props => [name];
}

class ProfileDeleted extends DeviceParamsEvent {
  const ProfileDeleted(this.name);

  final String name;

  @override
  List<Object?> get props => [name];
}

class _AckReceived extends DeviceParamsEvent {
  const _AckReceived(this.params);

  final DeviceParams params;

  @override
  List<Object?> get props => [params];
}

class _AckTimedOut extends DeviceParamsEvent {
  const _AckTimedOut();
}

// ---- Estado ----

class DeviceParamsState extends Equatable {
  const DeviceParamsState({
    required this.params,
    this.errors = const {},
    this.loading = false,
    this.ackPending = false,
    this.acknowledged = false,
    this.lastSent,
    this.profiles = const [],
    this.error,
    this.errorSeq = 0,
    this.info,
    this.infoSeq = 0,
  });

  final DeviceParams params;

  /// Erro de validação por campo.
  final Map<DeviceParamField, String> errors;
  final bool loading;

  /// Enviado e aguardando o evento `paramsAck`.
  final bool ackPending;

  /// O último envio foi confirmado pelo controlador; [params] passa a ter os valores devolvidos.
  final bool acknowledged;

  /// Valores do último envio, para comparar com o que o controlador devolveu.
  final DeviceParams? lastSent;

  /// Nomes dos perfis salvos.
  final List<String> profiles;

  /// Falha do último comando; [errorSeq] muda a cada falha para a UI avisar de novo.
  final String? error;
  final int errorSeq;

  /// Aviso não urgente (perfil salvo, por exemplo), com o mesmo esquema de [errorSeq].
  final String? info;
  final int infoSeq;

  bool get hasErrors => errors.isNotEmpty;

  /// Campos em que o controlador devolveu um valor diferente do enviado.
  List<DeviceParamField> get ackMismatches {
    final sent = lastSent;
    if (!acknowledged || sent == null) return const [];
    return [
      for (final field in DeviceParamField.values)
        if (params.valueOf(field) != sent.valueOf(field)) field,
    ];
  }

  DeviceParamsState copyWith({
    DeviceParams? params,
    Map<DeviceParamField, String>? errors,
    bool? loading,
    bool? ackPending,
    bool? acknowledged,
    DeviceParams? lastSent,
    List<String>? profiles,
    String? error,
    String? info,
  }) =>
      DeviceParamsState(
        params: params ?? this.params,
        errors: errors ?? this.errors,
        loading: loading ?? this.loading,
        ackPending: ackPending ?? this.ackPending,
        acknowledged: acknowledged ?? this.acknowledged,
        lastSent: lastSent ?? this.lastSent,
        profiles: profiles ?? this.profiles,
        error: error,
        errorSeq: error == null ? errorSeq : errorSeq + 1,
        info: info,
        infoSeq: info == null ? infoSeq : infoSeq + 1,
      );

  @override
  List<Object?> get props =>
      [params, errors, loading, ackPending, acknowledged, lastSent, profiles, error, errorSeq, info, infoSeq];
}

// ---- Bloc ----

/// Formulário de [DeviceParams]: validação por campo, envio por ação explícita e perfis em JSON.
///
/// Os valores lidos vêm do cache do SDK; o controlador só informa os parâmetros dele em
/// resposta a um envio (`paramsAck`), e o Bloc avisa quando eles diferem dos enviados.
class DeviceParamsBloc extends Bloc<DeviceParamsEvent, DeviceParamsState> {
  DeviceParamsBloc(
    this._repository, {
    required ProfileStore profiles,
    this.ackTimeout = const Duration(seconds: 3),
  })  : _profiles = profiles,
        super(DeviceParamsState(params: DeviceParams.lowerBounds())) {
    // Uma única fila: ler, editar, enviar e confirmar acontecem na ordem em que chegam,
    // para uma leitura atrasada nunca sobrescrever uma edição mais nova.
    on<DeviceParamsEvent>(_onEvent, transformer: sequential());

    _ackSubscription = _repository.paramsAcks.listen((e) => add(_AckReceived(e.params)));
  }

  final MachineRepository _repository;
  final ProfileStore _profiles;

  /// Tempo máximo de espera pelo `paramsAck` depois de um envio.
  final Duration ackTimeout;

  late final StreamSubscription<ParamsAckEvent> _ackSubscription;
  Timer? _ackTimer;

  Future<void> _onEvent(DeviceParamsEvent event, Emitter<DeviceParamsState> emit) async {
    switch (event) {
      case DeviceParamsLoaded():
        await _onLoaded(emit);
      case DeviceParamFieldChanged():
        _onFieldChanged(event, emit);
      case DeviceParamsSendRequested():
        await _onSendRequested(emit);
      case ProfilesRefreshed():
        await _refreshProfiles(emit);
      case ProfileSaved():
        await _onProfileSaved(event, emit);
      case ProfileLoaded():
        await _onProfileLoaded(event, emit);
      case ProfileDeleted():
        await _onProfileDeleted(event, emit);
      case _AckReceived():
        _onAck(event, emit);
      case _AckTimedOut():
        _onAckTimedOut(emit);
    }
  }

  Future<void> _onLoaded(Emitter<DeviceParamsState> emit) async {
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

  Future<void> _onSendRequested(Emitter<DeviceParamsState> emit) async {
    final errors = state.params.validate();
    if (errors.isNotEmpty || state.hasErrors) {
      emit(state.copyWith(errors: {...state.errors, ...errors}));
      return;
    }
    final sent = state.params;
    emit(state.copyWith(ackPending: true, acknowledged: false, lastSent: sent));
    try {
      await _repository.sendDeviceParams(sent);
      _ackTimer?.cancel();
      _ackTimer = Timer(ackTimeout, () => add(const _AckTimedOut()));
    } on MachineException catch (e) {
      emit(state.copyWith(ackPending: false, error: e.message ?? e.code));
    }
  }

  void _onAck(_AckReceived event, Emitter<DeviceParamsState> emit) {
    _ackTimer?.cancel();
    emit(state.copyWith(
      params: event.params,
      errors: const {},
      ackPending: false,
      acknowledged: true,
    ));
  }

  void _onAckTimedOut(Emitter<DeviceParamsState> emit) {
    if (!state.ackPending) return;
    emit(state.copyWith(
      ackPending: false,
      error: 'O controlador não confirmou o envio em ${ackTimeout.inSeconds} s',
    ));
  }

  Future<void> _refreshProfiles(Emitter<DeviceParamsState> emit) async {
    try {
      emit(state.copyWith(profiles: await _profiles.list()));
    } on Exception catch (e) {
      emit(state.copyWith(error: 'Não foi possível listar os perfis: $e'));
    }
  }

  Future<void> _onProfileSaved(ProfileSaved event, Emitter<DeviceParamsState> emit) async {
    final name = event.name.trim();
    final problem = ProfileStore.validateName(name);
    if (problem != null) {
      emit(state.copyWith(error: problem));
      return;
    }
    try {
      await _profiles.save(DeviceParamsProfile(name: name, params: state.params, savedAt: DateTime.now()));
      emit(state.copyWith(profiles: await _profiles.list(), info: 'Perfil "$name" salvo'));
    } on Exception catch (e) {
      emit(state.copyWith(error: 'Não foi possível salvar o perfil: $e'));
    }
  }

  Future<void> _onProfileLoaded(ProfileLoaded event, Emitter<DeviceParamsState> emit) async {
    try {
      final profile = await _profiles.read(event.name);
      if (profile == null) {
        emit(state.copyWith(profiles: await _profiles.list(), error: 'Perfil "${event.name}" não existe mais'));
        return;
      }
      emit(state.copyWith(
        params: profile.params,
        errors: profile.params.validate(),
        acknowledged: false,
        info: 'Perfil "${event.name}" carregado no formulário (ainda não enviado)',
      ));
    } on Exception catch (e) {
      emit(state.copyWith(error: 'Não foi possível carregar o perfil: $e'));
    }
  }

  Future<void> _onProfileDeleted(ProfileDeleted event, Emitter<DeviceParamsState> emit) async {
    try {
      await _profiles.delete(event.name);
      emit(state.copyWith(profiles: await _profiles.list(), info: 'Perfil "${event.name}" excluído'));
    } on Exception catch (e) {
      emit(state.copyWith(error: 'Não foi possível excluir o perfil: $e'));
    }
  }

  @override
  Future<void> close() async {
    _ackTimer?.cancel();
    await _ackSubscription.cancel();
    return super.close();
  }
}
