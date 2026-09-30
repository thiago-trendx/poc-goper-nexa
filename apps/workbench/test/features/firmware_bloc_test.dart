import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poc_goper_nexa/data/machine_repository.dart';
import 'package:poc_goper_nexa/features/firmware/firmware_bloc.dart';
import 'package:sdk850_bridge/testing.dart';

({FakeMachineGateway gateway, MachineRepository repository, FirmwareBloc bloc}) _setup(
  FakeAsync async, {
  bool connect = true,
}) {
  final gateway = FakeMachineGateway(connectDelay: Duration.zero);
  final repository = MachineRepository(gateway);
  final bloc = FirmwareBloc(repository);
  if (connect) {
    repository.autoConnect();
    async.elapse(const Duration(milliseconds: 10));
  }
  return (gateway: gateway, repository: repository, bloc: bloc);
}

void _teardown(FakeAsync async, FirmwareBloc bloc, MachineRepository repository) {
  bloc.close();
  repository.dispose();
  async.flushMicrotasks();
}

void main() {
  test('instalação completa: envio, progresso e sucesso', () {
    fakeAsync((async) {
      final env = _setup(async);
      env.bloc.add(const FileSelected('/sdcard/fw.bin'));
      env.bloc.add(const InstallRequested(2));
      async.flushMicrotasks();

      expect(env.bloc.state.status, FirmwareStatus.sending);
      expect(env.bloc.state.installing, isTrue);

      async.elapse(env.gateway.firmwareStepInterval * 2);
      expect(env.bloc.state.status, FirmwareStatus.progress);
      expect(env.bloc.state.progress, 50);

      async.elapse(env.gateway.firmwareStepInterval * 2);
      expect(env.bloc.state.status, FirmwareStatus.success);
      expect(env.bloc.state.progress, 100);
      expect(env.bloc.state.installing, isFalse);

      _teardown(async, env.bloc, env.repository);
    });
  });

  test('instalar sem escolher o arquivo mostra erro e não chama o gateway', () {
    fakeAsync((async) {
      final env = _setup(async);
      env.bloc.add(const InstallRequested(1));
      async.flushMicrotasks();

      expect(env.bloc.state.status, FirmwareStatus.error);
      expect(env.bloc.state.message, 'Selecione o arquivo .bin');

      _teardown(async, env.bloc, env.repository);
    });
  });

  test('cancelar durante a instalação termina em erro "cancelada"', () {
    fakeAsync((async) {
      final env = _setup(async);
      env.bloc.add(const FileSelected('fw.bin'));
      env.bloc.add(const InstallRequested(1));
      async.elapse(env.gateway.firmwareStepInterval);

      env.bloc.add(const Cancelled());
      async.flushMicrotasks();

      expect(env.bloc.state.status, FirmwareStatus.error);
      expect(env.bloc.state.message, 'Instalação cancelada');

      _teardown(async, env.bloc, env.repository);
    });
  });

  test('sem conexão a instalação é recusada com a mensagem do erro', () {
    fakeAsync((async) {
      final env = _setup(async, connect: false);
      env.bloc.add(const FileSelected('fw.bin'));
      env.bloc.add(const InstallRequested(2));
      async.flushMicrotasks();

      expect(env.bloc.state.status, FirmwareStatus.error);
      expect(env.bloc.state.message, 'Sem conexão com a máquina');

      _teardown(async, env.bloc, env.repository);
    });
  });

  test('pedido de instalação durante uma instalação é descartado', () {
    fakeAsync((async) {
      final env = _setup(async);
      env.bloc.add(const FileSelected('fw.bin'));
      env.bloc.add(const InstallRequested(2));
      env.bloc.add(const InstallRequested(1));
      async.flushMicrotasks();

      expect(env.bloc.state.status, FirmwareStatus.sending);
      expect(env.bloc.state.message, isNull);

      _teardown(async, env.bloc, env.repository);
    });
  });
}
