import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poc_goper_nexa/app.dart';
import 'package:poc_goper_nexa/shared/safety/safety_limits.dart';
import 'package:poc_goper_nexa/shared/widgets/emergency_stop_button.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';

import 'helpers/spy_gateway.dart';

Future<void> pumpApp(
  WidgetTester tester,
  SpyGateway gateway, {
  SafetyLimits limits = const SafetyLimits(),
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(WorkbenchApp(
    gateway: gateway,
    limits: limits,
    forceDebounce: const Duration(milliseconds: 10),
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
      await gateway.start();

      await tester.tap(find.byKey(EmergencyStopButton.buttonKey));
      await tester.pump(const Duration(milliseconds: 50));

      expect(gateway.controlSnapshot.run, RunState.stop);
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
      await pumpApp(tester, SpyGateway());
      await goTo(tester, AppDestination.control);
      expect(isEnabled(tester, const Key('control_start')), isFalse);
      expect(isEnabled(tester, const Key('one_shot_origin')), isFalse);
      expect(tester.widget<Slider>(find.byKey(const Key('control_force'))).onChanged, isNull);

      await connect(tester);
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
      expect(find.textContaining('limite do app: 20 kg'), findsOneWidget);
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
      expect(find.text('Enviar parâmetros?'), findsOneWidget);
      await confirmDialog(tester, confirm: false);
      expect(gateway.deviceParams.minForce, 5, reason: 'cancelar não envia nada');

      await tester.tap(find.byKey(const Key('params_send')));
      await tester.pump(const Duration(milliseconds: 100));
      await confirmDialog(tester, confirm: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(gateway.deviceParams.minForce, 10);
      expect(find.text('Parâmetros confirmados pelo controlador'), findsOneWidget);
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
  });

  group('telemetria, firmware e log', () {
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

    testWidgets('o log registra a conexão', (tester) async {
      await pumpApp(tester, SpyGateway());
      await connect(tester);
      await goTo(tester, AppDestination.log);

      expect(find.textContaining('Conexão connected (/dev/ttyFAKE0)'), findsOneWidget);
      await disposeApp(tester);
    });
  });
}
