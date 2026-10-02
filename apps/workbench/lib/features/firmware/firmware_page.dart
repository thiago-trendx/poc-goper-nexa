import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../shared/widgets/feedback.dart';
import '../connection/connection_bloc.dart';
import '../control/control_bloc.dart';
import 'firmware_bloc.dart';

/// Instalação de firmware (placa adaptadora ou controlador).
class FirmwarePage extends StatefulWidget {
  const FirmwarePage({super.key});

  @override
  State<FirmwarePage> createState() => _FirmwarePageState();
}

class _FirmwarePageState extends State<FirmwarePage> {
  late final TextEditingController _path =
      TextEditingController(text: context.read<FirmwareBloc>().state.filePath ?? '');
  int _type = 2;

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  Future<void> _install(BuildContext context) async {
    final bloc = context.read<FirmwareBloc>();
    final target = _type == 1 ? 'placa adaptadora' : 'controlador';
    final confirmed = await confirmAction(
      context,
      title: 'Instalar firmware?',
      message: 'O firmware será instalado no $target. Não desligue a máquina durante a instalação; '
          'ao final, desligue e religue a máquina.',
      confirmLabel: 'Instalar',
    );
    if (confirmed) bloc.add(InstallRequested(_type));
  }

  static String _statusLabel(FirmwareState state) => switch (state.status) {
        FirmwareStatus.idle => 'Aguardando',
        FirmwareStatus.sending => 'Enviando…',
        FirmwareStatus.progress => 'Instalando: ${state.progress}%',
        FirmwareStatus.success => 'Instalado com sucesso. Desligue e religue a máquina.',
        FirmwareStatus.error => 'Erro: ${state.message ?? 'sem detalhes'}',
      };

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<FirmwareBloc>();
    final connected = context.watch<ConnectionBloc>().state.isConnected;
    final running = context.select((ControlBloc b) => b.state.machineRunning);
    return BlocBuilder<FirmwareBloc, FirmwareState>(
      builder: (context, state) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Use somente depois de a fábrica confirmar o procedimento e fornecer um .bin de teste.'),
              ),
            ),
            const SizedBox(height: 16),
            Section(
              title: 'Arquivo e destino',
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 420,
                    child: TextField(
                      key: const Key('firmware_path'),
                      controller: _path,
                      enabled: !state.installing,
                      decoration: const InputDecoration(
                        labelText: 'Caminho do arquivo .bin',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => bloc.add(FileSelected(value)),
                    ),
                  ),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 1, label: Text('Placa adaptadora')),
                      ButtonSegment(value: 2, label: Text('Controlador')),
                    ],
                    selected: {_type},
                    onSelectionChanged: state.installing ? null : (value) => setState(() => _type = value.first),
                  ),
                ],
              ),
            ),
            Section(
              title: 'Instalação',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    children: [
                      FilledButton(
                        key: const Key('firmware_install'),
                        onPressed: connected && !running && !state.installing ? () => _install(context) : null,
                        child: const Text('Instalar'),
                      ),
                      OutlinedButton(
                        key: const Key('firmware_cancel'),
                        onPressed: state.installing ? () => bloc.add(const Cancelled()) : null,
                        child: const Text('Cancelar'),
                      ),
                    ],
                  ),
                  if (running)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Pare a máquina para instalar firmware: o polling é pausado durante a instalação.',
                        key: Key('firmware_running_hint'),
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (state.installing)
                    LinearProgressIndicator(value: state.status == FirmwareStatus.progress ? state.progress / 100 : null),
                  const SizedBox(height: 8),
                  Text(_statusLabel(state), key: const Key('firmware_status')),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
