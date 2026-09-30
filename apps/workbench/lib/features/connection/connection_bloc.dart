import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';

import '../../data/machine_repository.dart';

// ---- Eventos ----

sealed class ConnectionBlocEvent extends Equatable {
  const ConnectionBlocEvent();

  @override
  List<Object?> get props => [];
}

/// Eventos que mudam a conexão ou o polling. Entram numa fila única e são tratados na ordem.
sealed class ConnectionCommand extends ConnectionBlocEvent {
  const ConnectionCommand();
}

/// Conecta por varredura automática ([portPath] nulo) ou na porta informada.
class ConnectRequested extends ConnectionCommand {
  const ConnectRequested.auto() : portPath = null;
  const ConnectRequested.manual(String this.portPath);

  final String? portPath;

  bool get isAuto => portPath == null;

  @override
  List<Object?> get props => [portPath];
}

class DisconnectRequested extends ConnectionCommand {
  const DisconnectRequested();
}

/// Liga o polling com [intervalMs] se estiver desligado; desliga se estiver ligado.
class PollingToggled extends ConnectionCommand {
  const PollingToggled({required this.intervalMs});

  final int intervalMs;

  @override
  List<Object?> get props => [intervalMs];
}

class _ConnectionChanged extends ConnectionCommand {
  const _ConnectionChanged(this.event);

  final ConnectionEvent event;

  @override
  List<Object?> get props => [event];
}

class _DeviceInfoReceived extends ConnectionBlocEvent {
  const _DeviceInfoReceived(this.info);

  final DeviceInfo info;

  @override
  List<Object?> get props => [info];
}

class _PollingChanged extends ConnectionBlocEvent {
  const _PollingChanged(this.active);

  final bool active;

  @override
  List<Object?> get props => [active];
}

// ---- Estado ----

enum LinkStatus { disconnected, connecting, connected, failed }

class ConnectionBlocState extends Equatable {
  const ConnectionBlocState({
    this.status = LinkStatus.disconnected,
    this.portPath,
    this.deviceInfo,
    this.reason,
    this.pollingActive = false,
    this.pollingIntervalMs = 200,
  });

  final LinkStatus status;
  final String? portPath;
  final DeviceInfo? deviceInfo;

  /// Motivo da última falha, quando [status] é [LinkStatus.failed].
  final String? reason;
  final bool pollingActive;
  final int pollingIntervalMs;

  bool get isConnected => status == LinkStatus.connected;

  ConnectionBlocState copyWith({
    LinkStatus? status,
    String? portPath,
    DeviceInfo? deviceInfo,
    String? reason,
    bool? pollingActive,
    int? pollingIntervalMs,
    bool clearDeviceInfo = false,
    bool clearReason = false,
  }) =>
      ConnectionBlocState(
        status: status ?? this.status,
        portPath: portPath ?? this.portPath,
        deviceInfo: clearDeviceInfo ? null : deviceInfo ?? this.deviceInfo,
        reason: clearReason ? null : reason ?? this.reason,
        pollingActive: pollingActive ?? this.pollingActive,
        pollingIntervalMs: pollingIntervalMs ?? this.pollingIntervalMs,
      );

  @override
  List<Object?> get props =>
      [status, portPath, deviceInfo, reason, pollingActive, pollingIntervalMs];
}

// ---- Bloc ----

/// Conexão com a máquina. Ao conectar, liga o polling e consulta o `DeviceInfo`.
///
/// O envio do perfil ativo de `DeviceParams` ao conectar (como faz o demo) entra na Fase 3,
/// junto com os perfis salvos.
class ConnectionBloc extends Bloc<ConnectionBlocEvent, ConnectionBlocState> {
  ConnectionBloc(this._repository)
      : super(ConnectionBlocState(pollingIntervalMs: _repository.pollingIntervalMs)) {
    on<ConnectionCommand>(_onCommand, transformer: sequential());
    on<_DeviceInfoReceived>(
      (event, emit) => emit(state.copyWith(deviceInfo: event.info)),
    );
    on<_PollingChanged>(
      (event, emit) => emit(state.copyWith(pollingActive: event.active)),
    );

    _subscriptions = [
      _repository.connections.listen((e) => add(_ConnectionChanged(e))),
      _repository.deviceInfos.listen((e) => add(_DeviceInfoReceived(e))),
      _repository.pollingStates.listen((e) => add(_PollingChanged(e))),
    ];
  }

  final MachineRepository _repository;
  late final List<StreamSubscription<Object?>> _subscriptions;

  Future<void> _onCommand(ConnectionCommand command, Emitter<ConnectionBlocState> emit) =>
      switch (command) {
        ConnectRequested e => _onConnectRequested(e, emit),
        DisconnectRequested e => _onDisconnectRequested(e, emit),
        PollingToggled e => _onPollingToggled(e, emit),
        _ConnectionChanged e => _onConnectionChanged(e, emit),
      };

  Future<void> _onConnectRequested(ConnectRequested event, Emitter<ConnectionBlocState> emit) async {
    emit(state.copyWith(status: LinkStatus.connecting, clearReason: true));
    try {
      if (event.isAuto) {
        await _repository.autoConnect();
      } else if (!await _repository.connect(event.portPath!)) {
        emit(state.copyWith(status: LinkStatus.failed, reason: 'Não foi possível iniciar a conexão'));
      }
    } on MachineException catch (e) {
      emit(state.copyWith(status: LinkStatus.failed, reason: e.message ?? e.code));
    }
  }

  Future<void> _onDisconnectRequested(
    DisconnectRequested event,
    Emitter<ConnectionBlocState> emit,
  ) async {
    try {
      await _repository.disconnect();
    } on MachineException catch (e) {
      emit(state.copyWith(reason: e.message ?? e.code));
    }
  }

  Future<void> _onPollingToggled(PollingToggled event, Emitter<ConnectionBlocState> emit) async {
    try {
      if (state.pollingActive) {
        await _repository.stopPolling();
      } else {
        emit(state.copyWith(pollingIntervalMs: event.intervalMs));
        await _repository.startPolling(intervalMs: event.intervalMs);
      }
    } on MachineException catch (e) {
      emit(state.copyWith(reason: e.message ?? e.code));
    }
  }

  Future<void> _onConnectionChanged(
    _ConnectionChanged event,
    Emitter<ConnectionBlocState> emit,
  ) async {
    final connection = event.event;
    switch (connection.state) {
      case MachineConnectionState.connected:
        emit(state.copyWith(
          status: LinkStatus.connected,
          portPath: connection.portPath,
          clearReason: true,
        ));
        try {
          await _repository.startPolling(intervalMs: state.pollingIntervalMs);
          await _repository.queryDeviceInfo();
        } on MachineException catch (e) {
          emit(state.copyWith(reason: e.message ?? e.code));
        }
      case MachineConnectionState.disconnected:
        emit(ConnectionBlocState(pollingIntervalMs: state.pollingIntervalMs));
      case MachineConnectionState.failed:
      case MachineConnectionState.error:
        emit(state.copyWith(
          status: LinkStatus.failed,
          reason: connection.reason ?? 'Falha na comunicação',
          pollingActive: false,
          clearDeviceInfo: true,
        ));
    }
  }

  @override
  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    return super.close();
  }
}
