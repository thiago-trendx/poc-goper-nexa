import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';
import 'package:sdk850_bridge/testing.dart';
import 'package:poc_goper_nexa/data/machine_repository.dart';
import 'package:poc_goper_nexa/features/connection/connection_bloc.dart';

const _settle = Duration(milliseconds: 60);

void main() {
  late FakeMachineGateway gateway;
  late MachineRepository repository;

  setUp(() {
    gateway = FakeMachineGateway(connectDelay: Duration.zero);
    repository = MachineRepository(gateway);
  });

  tearDown(() => repository.dispose());

  blocTest<ConnectionBloc, ConnectionBlocState>(
    'conexão automática: conecta, liga o polling e lê o DeviceInfo',
    build: () => ConnectionBloc(repository),
    act: (bloc) => bloc.add(const ConnectRequested.auto()),
    wait: _settle,
    expect: () => [
      const ConnectionBlocState(status: LinkStatus.connecting),
      const ConnectionBlocState(status: LinkStatus.connected, portPath: '/dev/ttyFAKE0'),
      const ConnectionBlocState(
        status: LinkStatus.connected,
        portPath: '/dev/ttyFAKE0',
        pollingActive: true,
      ),
      const ConnectionBlocState(
        status: LinkStatus.connected,
        portPath: '/dev/ttyFAKE0',
        pollingActive: true,
        deviceInfo: FakeMachineGateway.defaultDeviceInfo,
      ),
    ],
    verify: (_) => expect(gateway.isPolling, isTrue),
  );

  blocTest<ConnectionBloc, ConnectionBlocState>(
    'conexão manual usa o caminho informado',
    build: () => ConnectionBloc(repository),
    act: (bloc) => bloc.add(const ConnectRequested.manual('/dev/ttyUSB0')),
    wait: _settle,
    verify: (bloc) {
      expect(bloc.state.status, LinkStatus.connected);
      expect(bloc.state.portPath, '/dev/ttyUSB0');
    },
  );

  blocTest<ConnectionBloc, ConnectionBlocState>(
    'falha de varredura vira estado failed com o motivo',
    setUp: () => gateway.autoConnectShouldFail = true,
    build: () => ConnectionBloc(repository),
    act: (bloc) => bloc.add(const ConnectRequested.auto()),
    wait: _settle,
    expect: () => [
      const ConnectionBlocState(status: LinkStatus.connecting),
      const ConnectionBlocState(
        status: LinkStatus.failed,
        portPath: null,
        reason: 'Nenhuma porta respondeu (simulado)',
      ),
    ],
  );

  blocTest<ConnectionBloc, ConnectionBlocState>(
    'erro ao pedir a conexão vira estado failed',
    setUp: () => gateway.failNextCommand(const MachineException(MachineErrorCode.sdkError, 'sem permissão na serial')),
    build: () => ConnectionBloc(repository),
    act: (bloc) => bloc.add(const ConnectRequested.manual('/dev/ttyUSB0')),
    wait: _settle,
    expect: () => [
      const ConnectionBlocState(status: LinkStatus.connecting),
      const ConnectionBlocState(status: LinkStatus.failed, reason: 'sem permissão na serial'),
    ],
  );

  blocTest<ConnectionBloc, ConnectionBlocState>(
    'desconectar limpa porta, DeviceInfo e polling',
    build: () => ConnectionBloc(repository),
    act: (bloc) async {
      bloc.add(const ConnectRequested.auto());
      await Future<void>.delayed(_settle);
      bloc.add(const DisconnectRequested());
    },
    wait: _settle,
    verify: (bloc) {
      expect(bloc.state.status, LinkStatus.disconnected);
      expect(bloc.state.portPath, isNull);
      expect(bloc.state.deviceInfo, isNull);
      expect(bloc.state.pollingActive, isFalse);
      expect(gateway.isPolling, isFalse);
    },
  );

  blocTest<ConnectionBloc, ConnectionBlocState>(
    'PollingToggled desliga e religa o polling com o novo intervalo',
    build: () => ConnectionBloc(repository),
    act: (bloc) async {
      bloc.add(const ConnectRequested.auto());
      await Future<void>.delayed(_settle);
      bloc.add(const PollingToggled(intervalMs: 100)); // liga -> desliga
      await Future<void>.delayed(_settle);
      bloc.add(const PollingToggled(intervalMs: 50)); // desliga -> liga
    },
    wait: _settle,
    verify: (bloc) {
      expect(bloc.state.pollingActive, isTrue);
      expect(bloc.state.pollingIntervalMs, 50);
      expect(repository.pollingIntervalMs, 50);
    },
  );

  blocTest<ConnectionBloc, ConnectionBlocState>(
    'perda de conexão vira failed e desliga o polling',
    build: () => ConnectionBloc(repository),
    act: (bloc) async {
      bloc.add(const ConnectRequested.auto());
      await Future<void>.delayed(_settle);
      gateway.simulateDisconnect(state: MachineConnectionState.error, reason: 'cabo solto');
    },
    wait: _settle,
    verify: (bloc) {
      expect(bloc.state.status, LinkStatus.failed);
      expect(bloc.state.reason, 'cabo solto');
      expect(bloc.state.pollingActive, isFalse);
      expect(bloc.state.deviceInfo, isNull);
    },
  );
}
