import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';

import 'data/machine_repository.dart';
import 'features/connection/connection_bloc.dart';
import 'features/connection/connection_page.dart';
import 'features/control/control_bloc.dart';
import 'features/control/control_page.dart';
import 'features/device_params/device_params_bloc.dart';
import 'features/device_params/device_params_page.dart';
import 'features/firmware/firmware_bloc.dart';
import 'features/firmware/firmware_page.dart';
import 'features/lift_motor/lift_motor_bloc.dart';
import 'features/lift_motor/lift_motor_page.dart';
import 'features/log/log_cubit.dart';
import 'features/log/log_page.dart';
import 'features/telemetry/telemetry_bloc.dart';
import 'features/telemetry/telemetry_page.dart';
import 'shared/safety/safety_limits.dart';
import 'shared/widgets/emergency_stop_button.dart';

/// Raiz do app: repositório, Blocs e navegação.
class WorkbenchApp extends StatelessWidget {
  const WorkbenchApp({
    super.key,
    required this.gateway,
    this.limits = const SafetyLimits(),
    this.forceDebounce = const Duration(milliseconds: 150),
  });

  final MachineGateway gateway;
  final SafetyLimits limits;
  final Duration forceDebounce;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<SafetyLimits>.value(value: limits),
        RepositoryProvider<MachineRepository>(
          create: (_) => MachineRepository(gateway),
          dispose: (repository) => unawaited(repository.dispose()),
          lazy: false,
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            lazy: false,
            create: (context) => ConnectionBloc(context.read<MachineRepository>()),
          ),
          BlocProvider(
            lazy: false,
            create: (context) =>
                DeviceParamsBloc(context.read<MachineRepository>())..add(const DeviceParamsLoaded()),
          ),
          BlocProvider(
            lazy: false,
            create: (context) => ControlBloc(
              context.read<MachineRepository>(),
              limits: limits,
              forceDebounce: forceDebounce,
            )..add(const ControlLoaded()),
          ),
          BlocProvider(
            lazy: false,
            create: (context) => LiftMotorBloc(context.read<MachineRepository>()),
          ),
          BlocProvider(
            lazy: false,
            create: (context) =>
                TelemetryBloc(context.read<MachineRepository>())..add(const TelemetryStarted()),
          ),
          BlocProvider(
            lazy: false,
            create: (context) => FirmwareBloc(context.read<MachineRepository>()),
          ),
          BlocProvider(
            lazy: false,
            create: (context) => LogCubit(context.read<MachineRepository>()),
          ),
        ],
        child: MaterialApp(
          title: 'Workbench 850',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
          home: const _SafetyLifecycleGuard(child: HomeShell()),
        ),
      ),
    );
  }
}

/// Ao enviar o app para segundo plano ou fechá-lo, envia `stop()` e para o polling.
class _SafetyLifecycleGuard extends StatefulWidget {
  const _SafetyLifecycleGuard({required this.child});

  final Widget child;

  @override
  State<_SafetyLifecycleGuard> createState() => _SafetyLifecycleGuardState();
}

class _SafetyLifecycleGuardState extends State<_SafetyLifecycleGuard> with WidgetsBindingObserver {
  late final MachineRepository _repository;

  @override
  void initState() {
    super.initState();
    _repository = context.read<MachineRepository>();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      unawaited(_repository.haltForSafety());
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Destinos de navegação, na ordem das telas do plano (seção 7.4) mais o log.
enum AppDestination {
  connection('Conexão', Icons.usb, ConnectionPage.new),
  deviceParams('Parâmetros', Icons.tune, DeviceParamsPage.new),
  control('Controle', Icons.sports_gymnastics, ControlPage.new),
  liftMotor('Motores', Icons.height, LiftMotorPage.new),
  telemetry('Telemetria', Icons.show_chart, TelemetryPage.new),
  firmware('Firmware', Icons.system_update, FirmwarePage.new),
  log('Log', Icons.receipt_long, LogPage.new);

  const AppDestination(this.label, this.icon, this.builder);

  final String label;
  final IconData icon;
  final Widget Function({Key? key}) builder;
}

/// Navegação lateral com o botão STOP fixo embaixo, visível em todas as telas.
///
/// Ao trocar de destino a tela anterior é descartada, o que dispara o `stop()` de
/// segurança da tela de controle.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  AppDestination _selected = AppDestination.connection;

  @override
  Widget build(BuildContext context) {
    final connected = context.select((ConnectionBloc b) => b.state.isConnected);
    return Scaffold(
      appBar: AppBar(
        title: Text(_selected.label),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Chip(
              avatar: Icon(connected ? Icons.link : Icons.link_off, size: 18),
              label: Text(connected ? 'Conectado' : 'Desconectado'),
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: NavigationRail(
                    selectedIndex: _selected.index,
                    labelType: NavigationRailLabelType.all,
                    onDestinationSelected: (index) =>
                        setState(() => _selected = AppDestination.values[index]),
                    destinations: [
                      for (final destination in AppDestination.values)
                        NavigationRailDestination(
                          icon: Icon(destination.icon),
                          label: Text(destination.label),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _selected.builder()),
        ],
      ),
      bottomNavigationBar: const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(8),
          child: EmergencyStopButton(),
        ),
      ),
    );
  }
}
