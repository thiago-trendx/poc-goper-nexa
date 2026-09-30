import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poc_goper_nexa/features/device_params/profile_store.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';
import 'package:sdk850_bridge/testing.dart';

void main() {
  late Directory directory;
  late FileProfileStore store;
  const params = FakeMachineGateway.defaultParams;

  DeviceParamsProfile profile(String name, {DeviceParams p = params}) =>
      DeviceParamsProfile(name: name, params: p, savedAt: DateTime.utc(2026, 9, 30, 12));

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('profiles_test_');
    store = FileProfileStore(directory: () async => Directory('${directory.path}/profiles'));
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  group('validateName', () {
    test('aceita nomes comuns', () {
      for (final name in ['painel original', 'Painel_1', 'teste-2', 'v1.0', 'a', 'A' * 40]) {
        expect(ProfileStore.validateName(name), isNull, reason: name);
      }
    });

    test('rejeita vazio, longo e caracteres de caminho', () {
      for (final name in ['', 'A' * 41, '../fora', 'a/b', r'a\b', '.oculto', ' espaço', 'termina ', 'termina.', 'a:b', 'a*b']) {
        expect(ProfileStore.validateName(name), isNotNull, reason: '"$name"');
      }
    });
  });

  group('FileProfileStore', () {
    test('sem perfis, lista vazia e o diretório nem precisa existir', () async {
      expect(await store.list(), isEmpty);
    });

    test('salvar e ler devolve o mesmo perfil', () async {
      await store.save(profile('painel original', p: params.withField(DeviceParamField.minForce, 12)));

      final read = await store.read('painel original');

      expect(read, profile('painel original', p: params.withField(DeviceParamField.minForce, 12)));
    });

    test('o arquivo é um JSON legível com o nome, a data e os 11 campos', () async {
      await store.save(profile('p1'));

      final file = File('${directory.path}/profiles/p1.json');
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;

      expect(json['name'], 'p1');
      expect(json['savedAt'], '2026-09-30T12:00:00.000Z');
      expect((json['params'] as Map).keys, DeviceParamField.values.map((f) => f.key));
    });

    test('list ordena sem diferenciar maiúsculas e ignora outros arquivos', () async {
      await store.save(profile('beta'));
      await store.save(profile('Alfa'));
      await store.save(profile('charlie'));
      await File('${directory.path}/profiles/anotacao.txt').writeAsString('x');

      expect(await store.list(), ['Alfa', 'beta', 'charlie']);
    });

    test('salvar com o mesmo nome substitui o perfil', () async {
      await store.save(profile('p1'));
      await store.save(profile('p1', p: params.withField(DeviceParamField.maxForce, 90)));

      expect((await store.read('p1'))!.params.maxForce, 90);
      expect(await store.list(), ['p1']);
    });

    test('excluir apaga o arquivo; excluir o que não existe não falha', () async {
      await store.save(profile('p1'));

      await store.delete('p1');
      await store.delete('p1');

      expect(await store.list(), isEmpty);
      expect(await store.read('p1'), isNull);
    });

    test('nome inválido é recusado antes de tocar no disco', () async {
      expect(() => store.save(profile('../fora')), throwsArgumentError);
      expect(() => store.read('a/b'), throwsArgumentError);
      expect(() => store.delete(''), throwsArgumentError);
      expect(await store.list(), isEmpty);
    });

    test('arquivo corrompido falha na leitura em vez de devolver valores errados', () async {
      await Directory('${directory.path}/profiles').create(recursive: true);
      await File('${directory.path}/profiles/ruim.json').writeAsString('{"name": "ruim"');

      expect(() => store.read('ruim'), throwsFormatException);
    });
  });
}
