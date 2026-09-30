import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../shared/widgets/feedback.dart';
import 'connection_bloc.dart';

/// Conexão e diagnóstico: conexão automática ou por caminho manual, estado,
/// `DeviceInfo` e intervalo de polling.
class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key});

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  final _portController = TextEditingController(text: '/dev/ttyUSB0');
  int _intervalMs = 200;

  @override
  void initState() {
    super.initState();
    _intervalMs = context.read<ConnectionBloc>().state.pollingIntervalMs;
  }

  @override
  void dispose() {
    _portController.dispose();
    super.dispose();
  }

  static String _statusLabel(ConnectionBlocState state) => switch (state.status) {
        LinkStatus.disconnected => 'Desconectado',
        LinkStatus.connecting => 'Conectando…',
        LinkStatus.connected => 'Conectado em ${state.portPath ?? '?'}',
        LinkStatus.failed => 'Falha: ${state.reason ?? 'sem detalhes'}',
      };

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<ConnectionBloc>();
    return BlocBuilder<ConnectionBloc, ConnectionBlocState>(
      builder: (context, state) {
        final canConnect = state.status == LinkStatus.disconnected || state.status == LinkStatus.failed;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Section(
              title: 'Estado',
              child: Card(
                color: state.status == LinkStatus.failed
                    ? Theme.of(context).colorScheme.errorContainer
                    : null,
                child: ListTile(
                  key: const Key('connection_status'),
                  leading: Icon(state.isConnected ? Icons.link : Icons.link_off),
                  title: Text(_statusLabel(state)),
                ),
              ),
            ),
            Section(
              title: 'Conexão',
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    key: const Key('connect_auto'),
                    onPressed: canConnect ? () => bloc.add(const ConnectRequested.auto()) : null,
                    icon: const Icon(Icons.search),
                    label: const Text('Conexão automática'),
                  ),
                  SizedBox(
                    width: 260,
                    child: TextField(
                      key: const Key('port_field'),
                      controller: _portController,
                      decoration: const InputDecoration(labelText: 'Caminho da porta', isDense: true),
                    ),
                  ),
                  OutlinedButton(
                    key: const Key('connect_manual'),
                    onPressed: canConnect
                        ? () {
                            final path = _portController.text.trim();
                            if (path.isEmpty) {
                              showMessage(context, 'Informe o caminho da porta', isError: true);
                              return;
                            }
                            bloc.add(ConnectRequested.manual(path));
                          }
                        : null,
                    child: const Text('Conectar'),
                  ),
                  OutlinedButton(
                    key: const Key('disconnect'),
                    onPressed: state.isConnected ? () => bloc.add(const DisconnectRequested()) : null,
                    child: const Text('Desconectar'),
                  ),
                ],
              ),
            ),
            Section(
              title: 'Polling do comando de controle',
              child: Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 200, label: Text('200 ms')),
                      ButtonSegment(value: 100, label: Text('100 ms')),
                      ButtonSegment(value: 50, label: Text('50 ms')),
                    ],
                    selected: {_intervalMs},
                    onSelectionChanged:
                        state.pollingActive ? null : (value) => setState(() => _intervalMs = value.first),
                  ),
                  Switch(
                    key: const Key('polling_switch'),
                    value: state.pollingActive,
                    onChanged: state.isConnected
                        ? (_) => bloc.add(PollingToggled(intervalMs: _intervalMs))
                        : null,
                  ),
                  Text(state.pollingActive ? 'Polling ativo (${state.pollingIntervalMs} ms)' : 'Polling parado'),
                ],
              ),
            ),
            Section(
              title: 'Controlador',
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: state.deviceInfo == null
                      ? const Text('Sem informação do controlador')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Software: ${state.deviceInfo!.softwareNum}'),
                            Text('Versão: ${state.deviceInfo!.versionCode}'),
                            Text('Código de produção: ${state.deviceInfo!.produceCode}'),
                          ],
                        ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
