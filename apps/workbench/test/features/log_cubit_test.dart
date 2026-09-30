import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:poc_goper_nexa/data/machine_repository.dart';
import 'package:poc_goper_nexa/features/log/log_cubit.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';

class _MockGateway extends Mock implements MachineGateway {}

void main() {
  late _MockGateway gateway;
  late StreamController<MachineEvent> events;
  late MachineRepository repository;
  var now = 1750000000000;

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  setUp(() {
    now = 1750000000000;
    gateway = _MockGateway();
    events = StreamController<MachineEvent>.broadcast();
    when(() => gateway.events).thenAnswer((_) => events.stream);
    when(() => gateway.dispose()).thenAnswer((_) async {});
    repository = MachineRepository(gateway);
  });

  tearDown(() async {
    await repository.dispose();
    await events.close();
  });

  LogCubit build({int maxEntries = 2000}) =>
      LogCubit(repository, maxEntries: maxEntries, nowMs: () => now++);

  test('registra pacotes tx e rx com o tipo e o hexadecimal', () async {
    final cubit = build();
    events
      ..add(const LogEntry(direction: LogDirection.tx, packetType: 'CONTROL', hex: 'AA55', tsEpochMs: 10))
      ..add(const LogEntry(direction: LogDirection.rx, packetType: 'DEVICE_INFO', tsEpochMs: 20));
    await flush();

    expect(cubit.state, [
      const LogLine(tsEpochMs: 10, text: 'TX CONTROL AA55'),
      const LogLine(tsEpochMs: 20, text: 'RX DEVICE_INFO'),
    ]);
    await cubit.close();
  });

  test('registra mudanças de conexão com porta e motivo', () async {
    final cubit = build();
    events
      ..add(const ConnectionEvent(state: MachineConnectionState.connected, portPath: '/dev/ttyS3'))
      ..add(const ConnectionEvent(state: MachineConnectionState.failed, reason: 'timeout'));
    await flush();

    expect(cubit.state.map((l) => l.text), [
      'Conexão connected (/dev/ttyS3)',
      'Conexão failed: timeout',
    ]);
    await cubit.close();
  });

  test('registra erros do canal de eventos sem derrubar o log', () async {
    final cubit = build();
    events.addError(const FormatException('tipo desconhecido'));
    await flush();

    expect(cubit.state.single.text, contains('Erro no canal de eventos'));
    expect(cubit.state.single.text, contains('tipo desconhecido'));
    await cubit.close();
  });

  test('mantém só as últimas maxEntries linhas', () async {
    final cubit = build(maxEntries: 3);
    for (var i = 1; i <= 5; i++) {
      events.add(LogEntry(direction: LogDirection.tx, packetType: 'P$i', tsEpochMs: i));
    }
    await flush();

    expect(cubit.state.map((l) => l.text), ['TX P3', 'TX P4', 'TX P5']);
    await cubit.close();
  });

  test('clear esvazia o log', () async {
    final cubit = build();
    events.add(const LogEntry(direction: LogDirection.tx, packetType: 'CONTROL', tsEpochMs: 1));
    await flush();

    cubit.clear();

    expect(cubit.state, isEmpty);
    await cubit.close();
  });

  test('exportText gera uma linha por entrada com horário ISO 8601 em UTC', () async {
    final cubit = build();
    events
      ..add(const LogEntry(direction: LogDirection.tx, packetType: 'CONTROL', hex: 'AA', tsEpochMs: 1750000000000))
      ..add(const LogEntry(direction: LogDirection.rx, packetType: 'CONTROL', hex: 'BB', tsEpochMs: 1750000001500));
    await flush();

    expect(
      cubit.exportText(),
      '2025-06-15T15:06:40.000Z TX CONTROL AA\n2025-06-15T15:06:41.500Z RX CONTROL BB',
    );
    await cubit.close();
  });
}
