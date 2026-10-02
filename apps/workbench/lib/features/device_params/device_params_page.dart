import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';

import '../../shared/widgets/feedback.dart';
import '../connection/connection_bloc.dart';
import '../control/control_bloc.dart';
import 'device_params_bloc.dart';

/// Formulário de `DeviceParams` com as faixas do Javadoc, envio por ação explícita e perfis.
class DeviceParamsPage extends StatefulWidget {
  const DeviceParamsPage({super.key});

  static const labels = {
    DeviceParamField.minForce: 'Força mínima',
    DeviceParamField.maxForce: 'Força máxima',
    DeviceParamField.inactiveForce: 'Força em repouso',
    DeviceParamField.maxLength: 'Comprimento máximo do cabo',
    DeviceParamField.ratedSpeed: 'Velocidade nominal',
    DeviceParamField.ropeGuideDiameter: 'Diâmetro da guia do cabo',
    DeviceParamField.orginMinDistance: 'Distância mínima da origem',
    DeviceParamField.orginMaxDistance: 'Distância máxima da origem',
    DeviceParamField.velocityRange: 'Faixa do coeficiente isocinético',
    DeviceParamField.torqueVariationCycle: 'Ciclo de variação de torque',
    DeviceParamField.torqueCoefficient: 'Coeficiente de torque',
  };

  @override
  State<DeviceParamsPage> createState() => _DeviceParamsPageState();
}

class _DeviceParamsPageState extends State<DeviceParamsPage> {
  final _profileName = TextEditingController();
  String? _selectedProfile;

  @override
  void initState() {
    super.initState();
    context.read<DeviceParamsBloc>().add(const ProfilesRefreshed());
  }

  @override
  void dispose() {
    _profileName.dispose();
    super.dispose();
  }

  Future<void> _send(BuildContext context) async {
    final bloc = context.read<DeviceParamsBloc>();
    final confirmed = await confirmAction(
      context,
      title: 'Enviar parâmetros ao controlador?',
      message: 'Isto altera a calibração da máquina com os 11 valores exibidos. '
          'O controlador confirma devolvendo os valores dele; se forem diferentes dos enviados, '
          'a tela avisa. Confirme que os valores estão corretos.',
      confirmLabel: 'Enviar',
    );
    if (confirmed) bloc.add(const DeviceParamsSendRequested());
  }

  Future<void> _delete(BuildContext context, String name) async {
    final bloc = context.read<DeviceParamsBloc>();
    final confirmed = await confirmAction(
      context,
      title: 'Excluir perfil?',
      message: 'O perfil "$name" será apagado do tablet.',
      confirmLabel: 'Excluir',
    );
    if (confirmed) {
      bloc.add(ProfileDeleted(name));
      setState(() => _selectedProfile = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<DeviceParamsBloc>();
    final connected = context.watch<ConnectionBloc>().state.isConnected;
    final running = context.select((ControlBloc b) => b.state.machineRunning);
    return BlocConsumer<DeviceParamsBloc, DeviceParamsState>(
      listenWhen: (previous, current) =>
          previous.errorSeq != current.errorSeq ||
          previous.infoSeq != current.infoSeq ||
          (!previous.acknowledged && current.acknowledged),
      listener: (context, state) {
        if (state.error != null) {
          showMessage(context, state.error!, isError: true);
        } else if (state.info != null) {
          showMessage(context, state.info!);
        } else if (state.acknowledged) {
          showMessage(context, 'Controlador confirmou o envio (paramsAck)');
        }
      },
      builder: (context, state) {
        final profile = state.profiles.contains(_selectedProfile) ? _selectedProfile : null;
        final mismatches = state.ackMismatches;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              key: const Key('params_origin_note'),
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Estes valores são os guardados no app, não uma leitura do controlador.'),
                subtitle: Text(
                  'O controlador não tem comando de leitura: ele só informa os parâmetros dele quando você '
                  'envia (resposta paramsAck). Nada é enviado ao conectar.',
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (mismatches.isNotEmpty) ...[
              Card(
                key: const Key('params_mismatch'),
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.warning_amber),
                  title: const Text('O controlador devolveu valores diferentes dos enviados'),
                  subtitle: Text([
                    for (final field in mismatches)
                      '${DeviceParamsPage.labels[field]}: enviado ${state.lastSent!.valueOf(field)}, '
                          'devolvido ${state.params.valueOf(field)}',
                  ].join('\n')),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  key: const Key('params_load'),
                  onPressed: state.loading ? null : () => bloc.add(const DeviceParamsLoaded()),
                  icon: const Icon(Icons.download),
                  label: const Text('Ler valores salvos'),
                ),
                FilledButton.icon(
                  key: const Key('params_send'),
                  onPressed:
                      connected && !running && !state.ackPending && !state.hasErrors ? () => _send(context) : null,
                  icon: const Icon(Icons.upload),
                  label: Text(state.ackPending ? 'Aguardando confirmação…' : 'Enviar ao controlador'),
                ),
                if (running)
                  const Text(
                    'Pare a máquina para enviar parâmetros: a calibração não deve mudar com ela em execução.',
                    key: Key('params_running_hint'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Section(
              title: 'Perfis',
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 240,
                    child: TextField(
                      key: const Key('profile_name'),
                      controller: _profileName,
                      decoration: const InputDecoration(labelText: 'Nome do perfil', isDense: true),
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const Key('profile_save'),
                    onPressed: () => bloc.add(ProfileSaved(_profileName.text)),
                    icon: const Icon(Icons.save),
                    label: const Text('Salvar perfil'),
                  ),
                  DropdownButton<String>(
                    key: const Key('profile_select'),
                    hint: const Text('Perfis salvos'),
                    value: profile,
                    items: [for (final name in state.profiles) DropdownMenuItem(value: name, child: Text(name))],
                    onChanged: (name) => setState(() => _selectedProfile = name),
                  ),
                  OutlinedButton(
                    key: const Key('profile_load'),
                    onPressed: profile == null ? null : () => bloc.add(ProfileLoaded(profile)),
                    child: const Text('Carregar'),
                  ),
                  OutlinedButton(
                    key: const Key('profile_delete'),
                    onPressed: profile == null ? null : () => _delete(context, profile),
                    child: const Text('Excluir'),
                  ),
                ],
              ),
            ),
            for (final field in DeviceParamField.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ParamField(
                  field: field,
                  label: DeviceParamsPage.labels[field]!,
                  value: state.params.valueOf(field),
                  error: state.errors[field],
                  onChanged: (value) => bloc.add(DeviceParamFieldChanged(field, value)),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ParamField extends StatefulWidget {
  const _ParamField({
    required this.field,
    required this.label,
    required this.value,
    required this.error,
    required this.onChanged,
  });

  final DeviceParamField field;
  final String label;
  final int value;
  final String? error;
  final ValueChanged<int?> onChanged;

  @override
  State<_ParamField> createState() => _ParamFieldState();
}

class _ParamFieldState extends State<_ParamField> {
  late final TextEditingController _controller = TextEditingController(text: '${widget.value}');

  @override
  void didUpdateWidget(_ParamField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Só sobrescreve o texto quando o valor mudou por fora (leitura, perfil ou confirmação).
    if (oldWidget.value != widget.value && int.tryParse(_controller.text) != widget.value) {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: Key('param_${widget.field.key}'),
      controller: _controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9-]'))],
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.field.rangeLabel,
        errorText: widget.error,
        border: const OutlineInputBorder(),
      ),
      onChanged: (text) => widget.onChanged(int.tryParse(text)),
    );
  }
}
