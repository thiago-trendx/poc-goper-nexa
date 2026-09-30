import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poc_goper_nexa/data/machine_repository.dart';
import 'package:poc_goper_nexa/features/device_params/device_params_bloc.dart';
import 'package:poc_goper_nexa/features/device_params/profile_store.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';
import 'package:sdk850_bridge/testing.dart';

import '../helpers/memory_profile_store.dart';

const _settle = Duration(milliseconds: 40);

void main() {
  late FakeMachineGateway gateway;
  late MachineRepository repository;
  late MemoryProfileStore store;
  const defaults = FakeMachineGateway.defaultParams;

  Future<void> connect() async {
    await repository.autoConnect();
    await Future<void>.delayed(_settle);
  }

  DeviceParamsBloc build({Duration ackTimeout = const Duration(seconds: 3)}) =>
      DeviceParamsBloc(repository, profiles: store, ackTimeout: ackTimeout);

  setUp(() {
    gateway = FakeMachineGateway(connectDelay: Duration.zero);
    repository = MachineRepository(gateway);
    store = MemoryProfileStore();
  });

  tearDown(() => repository.dispose());

  group('leitura e edição', () {
    blocTest<DeviceParamsBloc, DeviceParamsState>(
      'Loaded lê os parâmetros guardados no app',
      build: build,
      act: (bloc) => bloc.add(const DeviceParamsLoaded()),
      expect: () => [
        DeviceParamsState(params: DeviceParams.lowerBounds(), loading: true),
        const DeviceParamsState(params: defaults),
      ],
    );

    blocTest<DeviceParamsBloc, DeviceParamsState>(
      'FieldChanged com valor válido atualiza o campo sem erro',
      build: build,
      act: (bloc) => bloc.add(const DeviceParamFieldChanged(DeviceParamField.minForce, 12)),
      expect: () => [
        DeviceParamsState(params: DeviceParams.lowerBounds().withField(DeviceParamField.minForce, 12)),
      ],
    );

    blocTest<DeviceParamsBloc, DeviceParamsState>(
      'FieldChanged fora da faixa guarda o valor e mostra o erro da faixa',
      build: build,
      act: (bloc) => bloc.add(const DeviceParamFieldChanged(DeviceParamField.minForce, 99)),
      verify: (bloc) {
        expect(bloc.state.params.minForce, 99);
        expect(bloc.state.errors, {DeviceParamField.minForce: 'Entre 5 e 20 kg'});
      },
    );

    blocTest<DeviceParamsBloc, DeviceParamsState>(
      'FieldChanged com texto inválido mantém o valor e mostra erro',
      build: build,
      act: (bloc) => bloc.add(const DeviceParamFieldChanged(DeviceParamField.maxForce, null)),
      verify: (bloc) {
        expect(bloc.state.params.maxForce, DeviceParams.lowerBounds().maxForce);
        expect(bloc.state.errors[DeviceParamField.maxForce], 'Informe um número inteiro');
      },
    );

    blocTest<DeviceParamsBloc, DeviceParamsState>(
      'corrigir o campo remove o erro',
      build: build,
      act: (bloc) => bloc
        ..add(const DeviceParamFieldChanged(DeviceParamField.minForce, 99))
        ..add(const DeviceParamFieldChanged(DeviceParamField.minForce, 10)),
      verify: (bloc) {
        expect(bloc.state.errors, isEmpty);
        expect(bloc.state.params.minForce, 10);
      },
    );
  });

  group('envio (só por ação explícita)', () {
    blocTest<DeviceParamsBloc, DeviceParamsState>(
      'enviar com campo inválido não chama o gateway',
      build: build,
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
      build: build,
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
        expect(bloc.state.lastSent!.minForce, 10);
        expect(bloc.state.ackMismatches, isEmpty);
        expect(gateway.deviceParams.minForce, 10);
      },
    );

    blocTest<DeviceParamsBloc, DeviceParamsState>(
      'enviar sem conexão publica o erro e não fica aguardando confirmação',
      build: build,
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

    blocTest<DeviceParamsBloc, DeviceParamsState>(
      'o controlador devolve valores diferentes: os campos divergentes são listados',
      setUp: () => gateway.ackFor = (sent) => sent.withField(DeviceParamField.minForce, 12),
      build: build,
      act: (bloc) async {
        await connect();
        bloc
          ..add(const DeviceParamsLoaded())
          ..add(const DeviceParamFieldChanged(DeviceParamField.minForce, 10))
          ..add(const DeviceParamsSendRequested());
      },
      wait: _settle,
      verify: (bloc) {
        expect(bloc.state.acknowledged, isTrue);
        expect(bloc.state.params.minForce, 12, reason: 'a tela passa a mostrar o que o controlador devolveu');
        expect(bloc.state.lastSent!.minForce, 10);
        expect(bloc.state.ackMismatches, [DeviceParamField.minForce]);
      },
    );

    blocTest<DeviceParamsBloc, DeviceParamsState>(
      'editar um campo depois da confirmação limpa o aviso de divergência',
      setUp: () => gateway.ackFor = (sent) => sent.withField(DeviceParamField.minForce, 12),
      build: build,
      act: (bloc) async {
        await connect();
        bloc
          ..add(const DeviceParamsLoaded())
          ..add(const DeviceParamFieldChanged(DeviceParamField.minForce, 10))
          ..add(const DeviceParamsSendRequested());
        await Future<void>.delayed(_settle);
        bloc.add(const DeviceParamFieldChanged(DeviceParamField.maxForce, 90));
      },
      wait: _settle,
      verify: (bloc) {
        expect(bloc.state.acknowledged, isFalse);
        expect(bloc.state.ackMismatches, isEmpty);
      },
    );

    test('sem paramsAck o envio expira com erro e deixa enviar de novo', () {
      fakeAsync((async) {
        final fakeGateway = FakeMachineGateway(connectDelay: Duration.zero)..dropParamsAck = true;
        final fakeRepository = MachineRepository(fakeGateway);
        final bloc = DeviceParamsBloc(fakeRepository, profiles: MemoryProfileStore());
        fakeRepository.autoConnect();
        async.elapse(const Duration(milliseconds: 10));

        bloc.add(const DeviceParamsLoaded());
        bloc.add(const DeviceParamsSendRequested());
        async.elapse(const Duration(seconds: 1));
        expect(bloc.state.ackPending, isTrue);

        async.elapse(const Duration(seconds: 3));

        expect(bloc.state.ackPending, isFalse);
        expect(bloc.state.error, 'O controlador não confirmou o envio em 3 s');
        expect(bloc.state.acknowledged, isFalse);

        bloc.close();
        fakeRepository.dispose();
        async.flushMicrotasks();
      });
    });

    test('o paramsAck a tempo cancela o timeout', () {
      fakeAsync((async) {
        final fakeGateway = FakeMachineGateway(connectDelay: Duration.zero);
        final fakeRepository = MachineRepository(fakeGateway);
        final bloc = DeviceParamsBloc(fakeRepository, profiles: MemoryProfileStore());
        fakeRepository.autoConnect();
        async.elapse(const Duration(milliseconds: 10));

        bloc.add(const DeviceParamsLoaded());
        bloc.add(const DeviceParamsSendRequested());
        async.elapse(const Duration(seconds: 10));

        expect(bloc.state.acknowledged, isTrue);
        expect(bloc.state.error, isNull);
        expect(bloc.state.errorSeq, 0);

        bloc.close();
        fakeRepository.dispose();
        async.flushMicrotasks();
      });
    });
  });

  group('perfis', () {
    blocTest<DeviceParamsBloc, DeviceParamsState>(
      'salvar grava os valores do formulário e atualiza a lista',
      build: build,
      act: (bloc) => bloc
        ..add(const DeviceParamFieldChanged(DeviceParamField.minForce, 12))
        ..add(const ProfileSaved('  painel original ')),
      wait: _settle,
      verify: (bloc) {
        expect(store.profiles.keys, ['painel original']);
        expect(store.profiles['painel original']!.params.minForce, 12);
        expect(bloc.state.profiles, ['painel original']);
        expect(bloc.state.info, 'Perfil "painel original" salvo');
        expect(bloc.state.infoSeq, 1);
      },
    );

    blocTest<DeviceParamsBloc, DeviceParamsState>(
      'nome inválido não grava e publica o erro',
      build: build,
      act: (bloc) => bloc
        ..add(const ProfileSaved(''))
        ..add(const ProfileSaved('../fora'))
        ..add(const ProfileSaved('a/b')),
      wait: _settle,
      verify: (bloc) {
        expect(store.profiles, isEmpty);
        expect(bloc.state.errorSeq, 3);
      },
    );

    blocTest<DeviceParamsBloc, DeviceParamsState>(
      'carregar coloca o perfil no formulário, valida e não envia nada',
      setUp: () => store.profiles['fora'] = DeviceParamsProfile(
        name: 'fora',
        params: defaults.withField(DeviceParamField.minForce, 99),
        savedAt: DateTime(2026),
      ),
      build: build,
      act: (bloc) async {
        await connect();
        bloc.add(const ProfileLoaded('fora'));
      },
      wait: _settle,
      verify: (bloc) {
        expect(bloc.state.params.minForce, 99);
        expect(bloc.state.errors.keys, [DeviceParamField.minForce], reason: 'perfil fora da faixa é apontado');
        expect(bloc.state.acknowledged, isFalse);
        expect(gateway.deviceParams, defaults, reason: 'carregar não envia');
      },
    );

    blocTest<DeviceParamsBloc, DeviceParamsState>(
      'carregar perfil que não existe mais publica o erro',
      build: build,
      act: (bloc) => bloc.add(const ProfileLoaded('sumiu')),
      wait: _settle,
      verify: (bloc) => expect(bloc.state.error, 'Perfil "sumiu" não existe mais'),
    );

    blocTest<DeviceParamsBloc, DeviceParamsState>(
      'excluir remove o perfil e atualiza a lista',
      setUp: () => store.profiles['a'] = DeviceParamsProfile(name: 'a', params: defaults, savedAt: DateTime(2026)),
      build: build,
      act: (bloc) => bloc
        ..add(const ProfilesRefreshed())
        ..add(const ProfileDeleted('a')),
      wait: _settle,
      verify: (bloc) {
        expect(store.profiles, isEmpty);
        expect(bloc.state.profiles, isEmpty);
      },
    );

    blocTest<DeviceParamsBloc, DeviceParamsState>(
      'falha do armazenamento vira mensagem de erro, sem derrubar o Bloc',
      setUp: () => store.failure = const FileSystemException('sem espaço'),
      build: build,
      act: (bloc) => bloc
        ..add(const ProfilesRefreshed())
        ..add(const ProfileSaved('x'))
        ..add(const ProfileLoaded('x'))
        ..add(const ProfileDeleted('x')),
      wait: _settle,
      verify: (bloc) {
        expect(bloc.state.errorSeq, 4, reason: 'as quatro operações falharam e cada uma foi avisada');
      },
    );
  });
}
