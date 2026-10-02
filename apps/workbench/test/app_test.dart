import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poc_goper_nexa/app.dart';
import 'package:poc_goper_nexa/features/device_params/profile_store.dart';
import 'package:poc_goper_nexa/features/log/log_exporter.dart';
import 'package:sdk850_bridge/testing.dart';
import 'package:poc_goper_nexa/shared/safety/safety_limits.dart';
import 'package:poc_goper_nexa/shared/widgets/emergency_stop_button.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';

import 'helpers/fake_telemetry_exporter.dart';
import 'helpers/memory_profile_store.dart';
import 'helpers/spy_gateway.dart';

class _FakeExporter implements LogExporter {
  final saved = <String>[];
  Exception? failure;

  @override
  Future<String> save(String text) async {
    if (failure != null) throw failure!;
    saved.add(text);
    return '/sdcard/fake_log.txt';
  }
}

Future<void> pumpApp(
  WidgetTester tester,
  SpyGateway gateway, {
  SafetyLimits limits = const SafetyLimits(),
  LogExporter? logExporter,
  FakeTelemetryExporter? telemetryExporter,
  bool simulated = false,
  MemoryProfileStore? profileStore,
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(WorkbenchApp(
    gateway: gateway,
    limits: limits,
    forceDebounce: const Duration(milliseconds: 10),
    logExporter: logExporter ?? _FakeExporter(),
    telemetryExporter: telemetryExporter ?? FakeTelemetryExporter(),
    simulated: simulated,
    profileStore: profileStore ?? MemoryProfileStore(),
  ));
  await tester.pump();
}

/// Desmonta o app e deixa os timers pendentes (inclusive o `stop` de segurança) terminarem.
Future<void> disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

Future<void> goTo(WidgetTester tester, AppDestination destination) async {
  await tester.tap(find.descendant(
    of: find.byType(NavigationRail),
    matching: find.text(destination.label),
  ));
  await tester.pump(const Duration(milliseconds: 50));
  // A tela carrega o estado inicial (por exemplo, ControlLoaded) depois do primeiro quadro.
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> connect(WidgetTester tester) async {
  await goTo(tester, AppDestination.connection);
  await tester.tap(find.byKey(const Key('connect_auto')));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 300)); // primeiros status do polling
}

Future<void> confirmDialog(WidgetTester tester, {required bool confirm}) async {
  await tester.tap(find.byKey(Key(confirm ? 'confirm_dialog_confirm' : 'confirm_dialog_cancel')));
  await tester.pump(const Duration(milliseconds: 100));
}

bool isEnabled(WidgetTester tester, Key key) {
  final button = tester.widget<ButtonStyleButton>(find.byKey(key));
  return button.onPressed != null;
}

void main() {
  group('botão STOP', () {
    testWidgets('aparece em todas as rotas', (tester) async {
      await pumpApp(tester, SpyGateway());

      for (final destination in AppDestination.values) {
        await goTo(tester, destination);

        expect(find.byKey(EmergencyStopButton.buttonKey), findsOneWidget, reason: destination.label);
        expect(
          find.descendant(of: find.byType(AppBar), matching: find.text(destination.label)),
          findsOneWidget,
          reason: 'título de ${destination.label}',
        );
      }
      await disposeApp(tester);
    });

    testWidgets('envia stop() à máquina', (tester) async {
      final gateway = SpyGateway();
      await pumpApp(tester, gateway);
      await connect(tester);
      await gateway.setForce(10);
      await gateway.start();

      await tester.tap(find.byKey(EmergencyStopButton.buttonKey));
      await tester.pump(const Duration(milliseconds: 50));

      expect(gateway.controlSnapshot.run, RunState.stop);
      expect(find.text('STOP enviado'), findsOneWidget);
      await disposeApp(tester);
    });

    testWidgets('não espera a fila de comandos do ControlBloc', (tester) async {
      final gateway = SpyGateway();
      await pumpApp(tester, gateway);
      await connect(tester);
      await goTo(tester, AppDestination.control);
      gateway.commandDelay = const Duration(milliseconds: 400);

      await tester.tap(find.text('Elástico')); // ocupa a fila por 400 ms
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(EmergencyStopButton.buttonKey));
      await tester.pump(const Duration(milliseconds: 600));

      expect(gateway.calls.indexOf('stop:done'), greaterThanOrEqualTo(0));
      expect(gateway.calls.indexOf('stop:done'), lessThan(gateway.calls.indexOf('setMode:done')));
      await disposeApp(tester);
    });

    testWidgets('nunca fica desabilitado: sem conexão mostra a falha na tela', (tester) async {
      await pumpApp(tester, SpyGateway());

      await tester.tap(find.byKey(EmergencyStopButton.buttonKey));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('Falha ao enviar STOP'), findsOneWidget);
      await disposeApp(tester);
    });
  });

  group('segurança ao sair da tela de controle', () {
    testWidgets('trocar de tela envia stop() e para o polling', (tester) async {
      final gateway = SpyGateway();
      await pumpApp(tester, gateway);
      await connect(tester);
      await gateway.setForce(10);
      await goTo(tester, AppDestination.control);
      await tester.tap(find.byKey(const Key('control_start')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(gateway.controlSnapshot.run, RunState.running);
      expect(gateway.isPolling, isTrue);

      await goTo(tester, AppDestination.telemetry);
      await tester.pump(const Duration(seconds: 1));

      expect(gateway.controlSnapshot.run, RunState.stop);
      expect(gateway.isPolling, isFalse);
      await disposeApp(tester);
    });

    testWidgets('fechar o app envia stop() e para o polling', (tester) async {
      final gateway = SpyGateway();
      await pumpApp(tester, gateway);
      await connect(tester);
      await gateway.setForce(10);
      await gateway.start();

      // O Flutter só aceita a sequência resumed -> inactive -> hidden -> paused.
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump(const Duration(seconds: 1));

      expect(gateway.controlSnapshot.run, RunState.stop);
      expect(gateway.isPolling, isFalse);
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await disposeApp(tester);
    });
  });

  group('painel de controle', () {
    testWidgets('comandos ficam desabilitados sem conexão e habilitam ao conectar', (tester) async {
      final gateway = SpyGateway();
      await pumpApp(tester, gateway);
      await goTo(tester, AppDestination.control);
      expect(isEnabled(tester, const Key('control_start')), isFalse);
      expect(isEnabled(tester, const Key('one_shot_origin')), isFalse);
      expect(tester.widget<Slider>(find.byKey(const Key('control_force'))).onChanged, isNull);

      await connect(tester);
      await gateway.setForce(10);
      await goTo(tester, AppDestination.control);

      expect(isEnabled(tester, const Key('control_start')), isTrue);
      expect(isEnabled(tester, const Key('one_shot_origin')), isTrue);
      expect(tester.widget<Slider>(find.byKey(const Key('control_force'))).onChanged, isNotNull);
      await disposeApp(tester);
    });

    testWidgets('perda de conexão desabilita os comandos e aparece na tela de conexão', (tester) async {
      final gateway = SpyGateway();
      await pumpApp(tester, gateway);
      await connect(tester);
      await gateway.setForce(10);
      await goTo(tester, AppDestination.control);
      expect(isEnabled(tester, const Key('control_start')), isTrue);

      gateway.simulateDisconnect(state: MachineConnectionState.error, reason: 'cabo solto');
      await tester.pump(const Duration(milliseconds: 100));

      expect(isEnabled(tester, const Key('control_start')), isFalse);
      expect(find.text('Desconectado'), findsOneWidget);
      await goTo(tester, AppDestination.connection);
      expect(find.text('Falha: cabo solto'), findsOneWidget);
      await disposeApp(tester);
    });

    testWidgets('o slider não passa do limite de carga do app', (tester) async {
      await pumpApp(tester, SpyGateway(), limits: const SafetyLimits(maxForceKg: 20));
      await goTo(tester, AppDestination.control);

      final slider = tester.widget<Slider>(find.byKey(const Key('control_force')));
      expect(slider.max, 20);
      expect(slider.min, 5, reason: 'o mínimo é a força mínima da calibração, não zero');
      expect(find.textContaining('fora da faixa (5 a 20 kg)'), findsOneWidget);
      await disposeApp(tester);
    });

    testWidgets('Iniciar fica desabilitado com a carga fora da faixa e a tela explica', (tester) async {
      await pumpApp(tester, SpyGateway());
      await connect(tester);
      await goTo(tester, AppDestination.control);

      expect(isEnabled(tester, const Key('control_start')), isFalse);
      expect(find.byKey(const Key('control_start_hint')), findsOneWidget);
      expect(find.textContaining('ajuste a carga entre 5 e 30 kg'), findsOneWidget);
      await disposeApp(tester);
    });

    testWidgets('Iniciar fica desabilitado sem o polling e a tela explica', (tester) async {
      final gateway = SpyGateway();
      await pumpApp(tester, gateway);
      await connect(tester);
      await gateway.setForce(10);
      await tester.tap(find.byKey(const Key('polling_switch'))); // desliga o polling
      await tester.pump(const Duration(milliseconds: 100));
      await goTo(tester, AppDestination.control);

      expect(isEnabled(tester, const Key('control_start')), isFalse);
      expect(find.textContaining('ligue o polling na tela Conexão'), findsOneWidget);
      await disposeApp(tester);
    });

    testWidgets('avisa em vermelho se o controlador ficar mudo com a máquina em execução', (tester) async {
      final gateway = SpyGateway();
      await pumpApp(tester, gateway);
      await connect(tester);
      await gateway.setForce(10);
      await goTo(tester, AppDestination.control);
      await tester.tap(find.byKey(const Key('control_start')));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Em execução'), findsOneWidget);
      expect(find.byKey(const Key('control_silent_warning')), findsNothing);

      await gateway.stopPolling(); // o controlador deixa de responder
      await tester.pump(const Duration(seconds: 5));

      expect(find.byKey(const Key('control_silent_warning')), findsOneWidget);
      expect(find.textContaining('com a máquina em execução'), findsOneWidget);
      await disposeApp(tester);
    });

    testWidgets('Iniciar aplica a carga e a máquina passa a informar execução', (tester) async {
      final gateway = SpyGateway();
      await pumpApp(tester, gateway);
      await connect(tester);
      await gateway.setForce(10);
      await goTo(tester, AppDestination.control);
      expect(find.text('Carga: 10 kg (faixa 5 a 30 kg; limite do app: 30 kg)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('control_start')));
      await tester.pump(const Duration(milliseconds: 600));

      expect(gateway.controlSnapshot.run, RunState.running);
      expect(find.text('Em execução'), findsOneWidget);
      expect(find.byKey(const Key('control_start_hint')), findsNothing);
      await disposeApp(tester);
    });

    testWidgets('disparo único pede confirmação e só envia depois de confirmar', (tester) async {
      final gateway = SpyGateway();
      await pumpApp(tester, gateway);
      await connect(tester);
      await goTo(tester, AppDestination.control);

      await tester.tap(find.byKey(const Key('one_shot_origin')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Redefinir a origem?'), findsOneWidget);
      await confirmDialog(tester, confirm: false);
      expect(gateway.calls.where((c) => c.startsWith('originReset')), isEmpty);

      await tester.tap(find.byKey(const Key('one_shot_origin')));
      await tester.pump(const Duration(milliseconds: 100));
      await confirmDialog(tester, confirm: true);
      expect(gateway.calls.where((c) => c.startsWith('originReset')), ['originReset:start', 'originReset:done']);

      await tester.tap(find.byKey(const Key('one_shot_clear')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Limpar as contagens'), findsOneWidget);
      await confirmDialog(tester, confirm: true);
      expect(gateway.calls.where((c) => c.startsWith('clearData')), ['clearData:ALL:start', 'clearData:ALL:done']);
      await disposeApp(tester);
    });

    testWidgets('origem e reset de erro ficam desabilitados com a máquina em execução', (tester) async {
      final gateway = SpyGateway();
      await pumpApp(tester, gateway);
      await connect(tester);
      await gateway.setForce(10);
      await goTo(tester, AppDestination.control);
      expect(isEnabled(tester, const Key('one_shot_origin')), isTrue);

      await tester.tap(find.byKey(const Key('control_start')));
      await tester.pump(const Duration(milliseconds: 600));

      expect(isEnabled(tester, const Key('one_shot_origin')), isFalse);
      expect(isEnabled(tester, const Key('one_shot_error')), isFalse);
      expect(isEnabled(tester, const Key('one_shot_clear')), isTrue, reason: 'limpar dados vale em execução');
      expect(find.byKey(const Key('one_shot_hint')), findsOneWidget);
      await disposeApp(tester);
    });

    testWidgets('os coeficientes mostram a faixa de cada modo', (tester) async {
      await pumpApp(tester, SpyGateway());
      await connect(tester);
      await goTo(tester, AppDestination.control);

      for (final (label, expected) in [
        ('Concêntrico', 'Concêntrico (0–6)'),
        ('Excêntrico', 'Excêntrico (0–6)'),
        ('Elástico', 'Elástico (0–10)'),
      ]) {
        await tester.tap(find.text(label).first);
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text(expected), findsOneWidget, reason: label);
      }
      expect(find.textContaining('Curso elástico (1–200 cm)'), findsOneWidget);
      await disposeApp(tester);
    });

    testWidgets('mostra os coeficientes do modo ativo', (tester) async {
      await pumpApp(tester, SpyGateway());
      await connect(tester);
      await goTo(tester, AppDestination.control);
      expect(find.text('Modo padrão: sem coeficientes'), findsOneWidget);

      await tester.tap(find.text('Isocinético'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Isocinético (0–20)'), findsOneWidget);
      await disposeApp(tester);
    });
  });

  group('parâmetros: origem dos valores, divergência e perfis', () {
    Future<void> send(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('params_send')));
      await tester.pump(const Duration(milliseconds: 100));
      await confirmDialog(tester, confirm: true);
      await tester.pump(const Duration(milliseconds: 100));
    }

    String fieldText(WidgetTester tester, String key) =>
        tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

    testWidgets('deixa claro que os valores não são uma leitura do controlador', (tester) async {
      await pumpApp(tester, SpyGateway());
      await goTo(tester, AppDestination.deviceParams);

      expect(find.byKey(const Key('params_origin_note')), findsOneWidget);
      expect(find.textContaining('não uma leitura do controlador'), findsOneWidget);
      expect(find.text('Ler valores salvos'), findsOneWidget);
      expect(find.text('Ler da máquina'), findsNothing);
      await disposeApp(tester);
    });

    testWidgets('conectar e ligar o polling nunca envia parâmetros', (tester) async {
      final gateway = SpyGateway();
      await pumpApp(tester, gateway);

      await connect(tester);
      await tester.pump(const Duration(seconds: 2));

      expect(gateway.sentParams, isEmpty);
      await disposeApp(tester);
    });

    testWidgets('o envio só acontece depois da confirmação', (tester) async {
      final gateway = SpyGateway();
      await pumpApp(tester, gateway);
      await connect(tester);
      await goTo(tester, AppDestination.deviceParams);
      await tester.enterText(find.byKey(const Key('param_minForce')), '10');
      await tester.pump();

      await tester.tap(find.byKey(const Key('params_send')));
      await tester.pump(const Duration(milliseconds: 100));
      await confirmDialog(tester, confirm: false);
      expect(gateway.sentParams, isEmpty);

      await send(tester);

      expect(gateway.sentParams.single.minForce, 10);
      expect(find.byKey(const Key('params_mismatch')), findsNothing);
      await disposeApp(tester);
    });

    testWidgets('avisa quando o controlador devolve valores diferentes dos enviados', (tester) async {
      final gateway = SpyGateway()..ackFor = (sent) => sent.withField(DeviceParamField.minForce, 12);
      await pumpApp(tester, gateway);
      await connect(tester);
      await goTo(tester, AppDestination.deviceParams);
      await tester.enterText(find.byKey(const Key('param_minForce')), '10');
      await tester.pump();

      await send(tester);

      expect(find.byKey(const Key('params_mismatch')), findsOneWidget);
      expect(find.textContaining('Força mínima: enviado 10, devolvido 12'), findsOneWidget);
      expect(fieldText(tester, 'param_minForce'), '12', reason: 'a tela passa a mostrar o valor devolvido');
      await disposeApp(tester);
    });

    testWidgets('sem paramsAck a tela avisa que o controlador não confirmou', (tester) async {
      final gateway = SpyGateway()..dropParamsAck = true;
      await pumpApp(tester, gateway);
      await connect(tester);
      await goTo(tester, AppDestination.deviceParams);

      await send(tester);
      expect(find.text('Aguardando confirmação…'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));

      expect(find.textContaining('não confirmou o envio'), findsOneWidget);
      expect(find.text('Enviar ao controlador'), findsOneWidget);
      await disposeApp(tester);
    });

    testWidgets('perfis: salvar, alterar e carregar de volta', (tester) async {
      final store = MemoryProfileStore();
      final gateway = SpyGateway();
      await pumpApp(tester, gateway, profileStore: store);
      await goTo(tester, AppDestination.deviceParams);
      await tester.enterText(find.byKey(const Key('param_minForce')), '12');
      await tester.enterText(find.byKey(const Key('profile_name')), 'painel original');
      await tester.pump();

      await tester.tap(find.byKey(const Key('profile_save')));
      await tester.pump(const Duration(milliseconds: 100));

      expect(store.profiles['painel original']!.params.minForce, 12);
      expect(find.textContaining('Perfil "painel original" salvo'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('param_minForce')), '7');
      await tester.pump();
      expect(fieldText(tester, 'param_minForce'), '7');

      await tester.tap(find.byKey(const Key('profile_select')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('painel original').last);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('profile_load')));
      await tester.pump(const Duration(milliseconds: 600)); // o aviso anterior sai...
      await tester.pump(const Duration(milliseconds: 600)); // ...e o novo entra no quadro seguinte

      expect(fieldText(tester, 'param_minForce'), '12');
      expect(find.textContaining('carregado no formulário (ainda não enviado)'), findsOneWidget);
      expect(gateway.sentParams, isEmpty, reason: 'carregar um perfil nunca envia');
      await disposeApp(tester);
    });

    testWidgets('perfis: nome inválido mostra o erro e não salva', (tester) async {
      final store = MemoryProfileStore();
      await pumpApp(tester, SpyGateway(), profileStore: store);
      await goTo(tester, AppDestination.deviceParams);
      await tester.enterText(find.byKey(const Key('profile_name')), '../fora');
      await tester.pump();

      await tester.tap(find.byKey(const Key('profile_save')));
      await tester.pump(const Duration(milliseconds: 100));

      expect(store.profiles, isEmpty);
      expect(find.textContaining('Use letras, números'), findsOneWidget);
      await disposeApp(tester);
    });

    testWidgets('perfis: excluir pede confirmação', (tester) async {
      final store = MemoryProfileStore()
        ..profiles['p1'] = DeviceParamsProfile(
          name: 'p1',
          params: FakeMachineGateway.defaultParams,
          savedAt: DateTime(2026),
        );
      await pumpApp(tester, SpyGateway(), profileStore: store);
      await goTo(tester, AppDestination.deviceParams);
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const Key('profile_select')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('p1').last);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('profile_delete')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Excluir perfil?'), findsOneWidget);
      await confirmDialog(tester, confirm: false);
      expect(store.profiles.keys, ['p1']);

      await tester.tap(find.byKey(const Key('profile_delete')));
      await tester.pump(const Duration(milliseconds: 100));
      await confirmDialog(tester, confirm: true);

      expect(store.profiles, isEmpty);
      await disposeApp(tester);
    });
  });

  group('parâmetros do dispositivo', () {
    testWidgets('valor fora da faixa mostra o erro e bloqueia o envio', (tester) async {
      await pumpApp(tester, SpyGateway());
      await connect(tester);
      await goTo(tester, AppDestination.deviceParams);
      expect(isEnabled(tester, const Key('params_send')), isTrue);

      await tester.enterText(find.byKey(const Key('param_minForce')), '99');
      await tester.pump(const Duration(milliseconds: 500)); // termina a animação ajuda -> erro

      final field = tester.widget<TextField>(find.byKey(const Key('param_minForce')));
      expect(field.decoration!.errorText, 'Entre 5 e 20 kg');
      expect(isEnabled(tester, const Key('params_send')), isFalse);
      await disposeApp(tester);
    });

    testWidgets('o envio pede confirmação e aguarda o paramsAck', (tester) async {
      final gateway = SpyGateway();
      await pumpApp(tester, gateway);
      await connect(tester);
      await goTo(tester, AppDestination.deviceParams);
      await tester.enterText(find.byKey(const Key('param_minForce')), '10');
      await tester.pump();

      await tester.tap(find.byKey(const Key('params_send')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Enviar parâmetros ao controlador?'), findsOneWidget);
      await confirmDialog(tester, confirm: false);
      expect(gateway.deviceParams.minForce, 5, reason: 'cancelar não envia nada');

      await tester.tap(find.byKey(const Key('params_send')));
      await tester.pump(const Duration(milliseconds: 100));
      await confirmDialog(tester, confirm: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(gateway.deviceParams.minForce, 10);
      expect(find.text('Controlador confirmou o envio (paramsAck)'), findsOneWidget);
      await disposeApp(tester);
    });
  });

  group('motores de elevação', () {
    testWidgets('o autoteste só dispara depois da confirmação', (tester) async {
      final gateway = SpyGateway();
      await pumpApp(tester, gateway);
      await connect(tester);
      await goTo(tester, AppDestination.liftMotor);

      await tester.tap(find.byKey(const Key('lift_self_check')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Iniciar autoteste dos motores?'), findsOneWidget);
      await confirmDialog(tester, confirm: false);
      expect(gateway.controlSnapshot.motorSelfCheck, isFalse);

      await tester.tap(find.byKey(const Key('lift_self_check')));
      await tester.pump(const Duration(milliseconds: 100));
      await confirmDialog(tester, confirm: true);

      expect(gateway.controlSnapshot.motorSelfCheck, isTrue);
      expect(find.text('Em autoteste'), findsWidgets);
      expect(isEnabled(tester, const Key('lift_self_check')), isFalse);
      await tester.pump(const Duration(seconds: 7));
      await disposeApp(tester);
    });

    testWidgets('o ajuste de posição pede confirmação antes de mover', (tester) async {
      final gateway = SpyGateway();
      await pumpApp(tester, gateway);
      await connect(tester);
      await goTo(tester, AppDestination.liftMotor);
      await tester.enterText(find.byKey(const Key('lift_p1')), '2');
      await tester.enterText(find.byKey(const Key('lift_p2')), '3');

      await tester.tap(find.byKey(const Key('lift_adjust')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(gateway.controlSnapshot.motorPosition1, 0, reason: 'ainda aguardando a confirmação');
      await confirmDialog(tester, confirm: true);

      expect(gateway.controlSnapshot.motorPosition1, 2);
      expect(gateway.controlSnapshot.motorPosition2, 3);
      await tester.pump(const Duration(seconds: 5));
      await disposeApp(tester);
    });

    testWidgets('ajuste e autoteste ficam desabilitados sem o polling e a tela explica', (tester) async {
      final gateway = SpyGateway();
      await pumpApp(tester, gateway);
      await connect(tester);
      await tester.tap(find.byKey(const Key('polling_switch'))); // desliga o polling
      await tester.pump(const Duration(milliseconds: 100));
      await goTo(tester, AppDestination.liftMotor);

      expect(isEnabled(tester, const Key('lift_adjust')), isFalse);
      expect(isEnabled(tester, const Key('lift_self_check')), isFalse);
      expect(find.textContaining('Ligue o polling na tela Conexão'), findsOneWidget);
      await disposeApp(tester);
    });

    testWidgets('com o polling ligado a tela avisa que a máquina fica em STOP no fim', (tester) async {
      await pumpApp(tester, SpyGateway());
      await connect(tester);
      await goTo(tester, AppDestination.liftMotor);

      expect(isEnabled(tester, const Key('lift_adjust')), isTrue);
      expect(find.textContaining('a máquina fica em STOP no fim'), findsOneWidget);
      await disposeApp(tester);
    });
  });

  group('modo simulado', () {
    testWidgets('a barra avisa que o app está simulado', (tester) async {
      await pumpApp(tester, SpyGateway(), simulated: true);

      expect(find.byKey(const Key('simulated_chip')), findsOneWidget);
      expect(find.textContaining('SIMULADO'), findsOneWidget);
      await disposeApp(tester);
    });

    testWidgets('com a máquina real não aparece o aviso', (tester) async {
      await pumpApp(tester, SpyGateway());

      expect(find.byKey(const Key('simulated_chip')), findsNothing);
      await disposeApp(tester);
    });
  });

  group('diagnóstico do polling', () {
    testWidgets('avisa quando o controlador fica mudo com o polling ligado', (tester) async {
      final gateway = SilentGateway();
      await pumpApp(tester, gateway);
      await connect(tester);
      await goTo(tester, AppDestination.telemetry);
      expect(find.byKey(const Key('telemetry_silent')), findsNothing);

      await tester.pump(const Duration(seconds: 4));

      expect(find.byKey(const Key('telemetry_silent')), findsOneWidget);
      expect(find.textContaining('Sem resposta do controlador'), findsOneWidget);
      expect(find.byKey(const Key('telemetry_frozen')), findsNothing, reason: 'o polling está ligado');
      await disposeApp(tester);
    });

    testWidgets('não avisa quando as respostas chegam', (tester) async {
      await pumpApp(tester, SpyGateway());
      await connect(tester);
      await goTo(tester, AppDestination.telemetry);

      await tester.pump(const Duration(seconds: 5));

      expect(find.byKey(const Key('telemetry_silent')), findsNothing);
      await disposeApp(tester);
    });

    testWidgets('o seletor oferece os intervalos e religa o polling com o escolhido', (tester) async {
      final gateway = SpyGateway();
      await pumpApp(tester, gateway);
      await connect(tester);
      for (final ms in [200, 150, 120, 100, 80, 70, 60, 50]) {
        expect(find.byKey(Key('interval_$ms')), findsOneWidget, reason: '$ms ms');
      }

      await tester.tap(find.byKey(const Key('polling_switch')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('interval_80')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('polling_switch')));
      await tester.pump(const Duration(milliseconds: 100));

      expect(gateway.intervals, [200, 80]);
      await disposeApp(tester);
    });

    testWidgets('com o polling ligado o intervalo não pode ser trocado', (tester) async {
      final gateway = SpyGateway();
      await pumpApp(tester, gateway);
      await connect(tester);

      await tester.tap(find.byKey(const Key('interval_100')));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.widget<ChoiceChip>(find.byKey(const Key('interval_200'))).selected, isTrue);
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('interval_100'))).selected, isFalse);
      await disposeApp(tester);
    });
  });

  group('polling', () {
    testWidgets('o switch liga e desliga o polling e a telemetria congela', (tester) async {
      final gateway = SpyGateway();
      await pumpApp(tester, gateway);
      await connect(tester);
      expect(gateway.isPolling, isTrue);

      await tester.tap(find.byKey(const Key('polling_switch')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(gateway.isPolling, isFalse);
      expect(tester.widget<Switch>(find.byKey(const Key('polling_switch'))).value, isFalse);

      await goTo(tester, AppDestination.telemetry);
      expect(find.byKey(const Key('telemetry_frozen')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('telemetry_rate'))).data, '— Hz');
      await tester.pump(const Duration(seconds: 2));
      expect(tester.widget<Text>(find.byKey(const Key('telemetry_rate'))).data, '— Hz');

      await goTo(tester, AppDestination.connection);
      await tester.tap(find.byKey(const Key('polling_switch')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(gateway.isPolling, isTrue);
      await goTo(tester, AppDestination.telemetry);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('telemetry_frozen')), findsNothing);
      expect(tester.widget<Text>(find.byKey(const Key('telemetry_rate'))).data, endsWith('Hz'));
      await goTo(tester, AppDestination.connection);
      expect(tester.widget<Switch>(find.byKey(const Key('polling_switch'))).value, isTrue);
      await disposeApp(tester);
    });
  });

  group('telemetria, firmware e log', () {
    testWidgets('os três gráficos aparecem com dados e a tabela de erros começa vazia', (tester) async {
      await pumpApp(tester, SpyGateway());
      await connect(tester);
      await tester.pump(const Duration(seconds: 2));
      await goTo(tester, AppDestination.telemetry);

      for (final key in ['chart_force_time', 'chart_speed_time', 'chart_force_stroke']) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      expect(find.byKey(const Key('telemetry_no_errors')), findsOneWidget);
      await disposeApp(tester);
    });

    testWidgets('um código de erro aparece na tabela de erros observados', (tester) async {
      final gateway = SpyGateway();
      await pumpApp(tester, gateway);
      await connect(tester);
      gateway.injectErrorCode(9);
      await tester.pump(const Duration(seconds: 1));
      await goTo(tester, AppDestination.telemetry);

      expect(find.byKey(const Key('telemetry_errors_table')), findsOneWidget);
      expect(find.text('9 (0x9)'), findsOneWidget);
      await disposeApp(tester);
    });

    testWidgets('gravar e parar salva o CSV e mostra o caminho', (tester) async {
      final exporter = FakeTelemetryExporter();
      await pumpApp(tester, SpyGateway(), telemetryExporter: exporter);
      await connect(tester);
      await goTo(tester, AppDestination.telemetry);

      await tester.tap(find.byKey(const Key('telemetry_record')));
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byKey(const Key('telemetry_record')));
      await tester.pump(const Duration(milliseconds: 100));

      expect(exporter.csvs, hasLength(1));
      expect(exporter.csvs.single, startsWith('tsEpochMs,tsMonotonicMs,run,mode'));
      expect(find.textContaining('/fake/telemetria_1.csv'), findsWidgets);
      await tester.pump(const Duration(seconds: 5)); // some a mensagem da barra
      await disposeApp(tester);
    });

    testWidgets('o teste de taxa mede os intervalos, mostra o resumo e salva o relatório', (tester) async {
      final exporter = FakeTelemetryExporter();
      await pumpApp(tester, SpyGateway(), telemetryExporter: exporter);
      await connect(tester);
      await goTo(tester, AppDestination.telemetry);
      expect(isEnabled(tester, const Key('rate_test_start')), isTrue);
      expect(isEnabled(tester, const Key('report_save')), isFalse);

      await tester.tap(find.byKey(const Key('rate_test_start')));
      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(const Key('rate_test_progress')), findsOneWidget);
      expect(isEnabled(tester, const Key('rate_test_start')), isFalse);

      await tester.pump(const Duration(seconds: 50));

      expect(find.byKey(const Key('rate_test_table')), findsOneWidget);
      expect(find.byKey(const Key('rate_test_summary')), findsOneWidget);
      expect(find.byKey(const Key('rate_test_progress')), findsNothing);
      expect(isEnabled(tester, const Key('rate_test_start')), isTrue);

      await tester.ensureVisible(find.byKey(const Key('report_save')));
      await tester.tap(find.byKey(const Key('report_save')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(exporter.reports, hasLength(1));
      expect(exporter.reports.single, contains('Taxa de status por intervalo de polling'));
      await tester.pump(const Duration(seconds: 5));
      await disposeApp(tester);
    });

    testWidgets('o teste de taxa fica desabilitado sem conexão', (tester) async {
      await pumpApp(tester, SpyGateway());
      await goTo(tester, AppDestination.telemetry);

      expect(isEnabled(tester, const Key('rate_test_start')), isFalse);
      await disposeApp(tester);
    });

    testWidgets('a telemetria mostra a taxa medida depois de conectar', (tester) async {
      await pumpApp(tester, SpyGateway());
      await connect(tester);
      await tester.pump(const Duration(seconds: 2));
      await goTo(tester, AppDestination.telemetry);

      final rate = tester.widget<Text>(find.byKey(const Key('telemetry_rate'))).data!;
      expect(rate, endsWith('Hz'));
      expect(rate, isNot(startsWith('—')));
      await disposeApp(tester);
    });

    testWidgets('a instalação de firmware pede confirmação', (tester) async {
      final gateway = SpyGateway();
      await pumpApp(tester, gateway);
      await connect(tester);
      await goTo(tester, AppDestination.firmware);
      await tester.enterText(find.byKey(const Key('firmware_path')), '/sdcard/fw.bin');

      await tester.tap(find.byKey(const Key('firmware_install')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Instalar firmware?'), findsOneWidget);
      await confirmDialog(tester, confirm: true);

      expect(find.byKey(const Key('firmware_status')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('firmware_status'))).data,
        anyOf('Enviando…', startsWith('Instalando')),
      );
      await tester.pump(const Duration(seconds: 3));
      expect(tester.widget<Text>(find.byKey(const Key('firmware_status'))).data, contains('Desligue e religue'));
      await disposeApp(tester);
    });

    testWidgets('o log pode ser salvo em arquivo e mostra o caminho', (tester) async {
      final exporter = _FakeExporter();
      await pumpApp(tester, SpyGateway(), logExporter: exporter);
      await connect(tester);
      await goTo(tester, AppDestination.log);

      await tester.tap(find.byKey(const Key('log_save')));
      await tester.pump(const Duration(milliseconds: 100));

      expect(exporter.saved.single, contains('Conexão connected (/dev/ttyFAKE0)'));
      expect(find.textContaining('/sdcard/fake_log.txt'), findsOneWidget);
      await disposeApp(tester);
    });

    testWidgets('falha ao salvar o log aparece na tela', (tester) async {
      final exporter = _FakeExporter()..failure = const FileSystemException('sem espaço');
      await pumpApp(tester, SpyGateway(), logExporter: exporter);
      await connect(tester);
      await goTo(tester, AppDestination.log);

      await tester.tap(find.byKey(const Key('log_save')));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Falha ao salvar o log'), findsOneWidget);
      await disposeApp(tester);
    });

    testWidgets('o log registra a conexão', (tester) async {
      await pumpApp(tester, SpyGateway());
      await connect(tester);
      await goTo(tester, AppDestination.log);

      expect(find.textContaining('Conexão connected (/dev/ttyFAKE0)'), findsOneWidget);
      await disposeApp(tester);
    });
  });
}
