import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';
import 'package:sdk850_bridge/testing.dart';
import 'package:poc_goper_nexa/data/machine_repository.dart';
import 'package:poc_goper_nexa/features/device_params/device_params_bloc.dart';

const _settle = Duration(milliseconds: 40);

void main() {
  late FakeMachineGateway gateway;
  late MachineRepository repository;
  const defaults = FakeMachineGateway.defaultParams;

  Future<void> connect() async {
    await repository.autoConnect();
    await Future<void>.delayed(_settle);
  }

  setUp(() {
    gateway = FakeMachineGateway(connectDelay: Duration.zero);
    repository = MachineRepository(gateway);
  });

  tearDown(() => repository.dispose());

  blocTest<DeviceParamsBloc, DeviceParamsState>(
    'Loaded lê os parâmetros do dispositivo',
    build: () => DeviceParamsBloc(repository),
    act: (bloc) => bloc.add(const DeviceParamsLoaded()),
    expect: () => [
      DeviceParamsState(params: DeviceParams.lowerBounds(), loading: true),
      const DeviceParamsState(params: defaults),
    ],
  );

  blocTest<DeviceParamsBloc, DeviceParamsState>(
    'FieldChanged com valor válido atualiza o campo sem erro',
    build: () => DeviceParamsBloc(repository),
    act: (bloc) => bloc.add(const DeviceParamFieldChanged(DeviceParamField.minForce, 12)),
    expect: () => [
      DeviceParamsState(params: DeviceParams.lowerBounds().withField(DeviceParamField.minForce, 12)),
    ],
  );

  blocTest<DeviceParamsBloc, DeviceParamsState>(
    'FieldChanged fora da faixa guarda o valor e mostra o erro da faixa',
    build: () => DeviceParamsBloc(repository),
    act: (bloc) => bloc.add(const DeviceParamFieldChanged(DeviceParamField.minForce, 99)),
    verify: (bloc) {
      expect(bloc.state.params.minForce, 99);
      expect(bloc.state.errors, {DeviceParamField.minForce: 'Entre 5 e 20 kg'});
    },
  );

  blocTest<DeviceParamsBloc, DeviceParamsState>(
    'FieldChanged com texto inválido mantém o valor e mostra erro',
    build: () => DeviceParamsBloc(repository),
    act: (bloc) => bloc.add(const DeviceParamFieldChanged(DeviceParamField.maxForce, null)),
    verify: (bloc) {
      expect(bloc.state.params.maxForce, DeviceParams.lowerBounds().maxForce);
      expect(bloc.state.errors[DeviceParamField.maxForce], 'Informe um número inteiro');
    },
  );

  blocTest<DeviceParamsBloc, DeviceParamsState>(
    'corrigir o campo remove o erro',
    build: () => DeviceParamsBloc(repository),
    act: (bloc) => bloc
      ..add(const DeviceParamFieldChanged(DeviceParamField.minForce, 99))
      ..add(const DeviceParamFieldChanged(DeviceParamField.minForce, 10)),
    verify: (bloc) {
      expect(bloc.state.errors, isEmpty);
      expect(bloc.state.params.minForce, 10);
    },
  );

  blocTest<DeviceParamsBloc, DeviceParamsState>(
    'enviar com campo inválido não chama o gateway',
    build: () => DeviceParamsBloc(repository),
    act: (bloc) async {
      await connect();
      bloc
        ..add(const DeviceParamFieldChanged(DeviceParamField.minForce, 99))
        ..add(const DeviceParamsSendRequested());
    },
    wait: _settle,
    verify: (bloc) {
      expect(bloc.state.ackPending, isFalse);
      expect(bloc.state.errors.containsKey(DeviceParamField.minForce), isTrue);
      expect(gateway.deviceParams, defaults, reason: 'nada foi enviado');
    },
  );

  blocTest<DeviceParamsBloc, DeviceParamsState>(
    'enviar parâmetros válidos aguarda o paramsAck e marca como confirmado',
    build: () => DeviceParamsBloc(repository),
    act: (bloc) async {
      await connect();
      bloc
        ..add(const DeviceParamsLoaded())
        ..add(const DeviceParamFieldChanged(DeviceParamField.minForce, 10))
        ..add(const DeviceParamsSendRequested());
    },
    wait: _settle,
    verify: (bloc) {
      expect(bloc.state.ackPending, isFalse);
      expect(bloc.state.acknowledged, isTrue);
      expect(bloc.state.params.minForce, 10);
      expect(gateway.deviceParams.minForce, 10);
    },
  );

  blocTest<DeviceParamsBloc, DeviceParamsState>(
    'enviar sem conexão publica o erro e não fica aguardando confirmação',
    build: () => DeviceParamsBloc(repository),
    act: (bloc) => bloc
      ..add(const DeviceParamsLoaded())
      ..add(const DeviceParamsSendRequested()),
    wait: _settle,
    verify: (bloc) {
      expect(bloc.state.ackPending, isFalse);
      expect(bloc.state.error, 'Sem conexão com a máquina');
      expect(bloc.state.errorSeq, 1);
    },
  );
}
