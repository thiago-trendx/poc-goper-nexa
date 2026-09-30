import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';

import '../../shared/widgets/feedback.dart';
import '../connection/connection_bloc.dart';
import 'device_params_bloc.dart';

/// Formulário de `DeviceParams` com as faixas do Javadoc, leitura e envio.
class DeviceParamsPage extends StatelessWidget {
  const DeviceParamsPage({super.key});

  static const _labels = {
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

  Future<void> _send(BuildContext context) async {
    final bloc = context.read<DeviceParamsBloc>();
    final confirmed = await confirmAction(
      context,
      title: 'Enviar parâmetros?',
      message: 'Isto altera a calibração da máquina. Confirme que os valores estão corretos.',
      confirmLabel: 'Enviar',
    );
    if (confirmed) bloc.add(const DeviceParamsSendRequested());
  }

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<DeviceParamsBloc>();
    final connected = context.watch<ConnectionBloc>().state.isConnected;
    return BlocConsumer<DeviceParamsBloc, DeviceParamsState>(
      listenWhen: (previous, current) =>
          previous.errorSeq != current.errorSeq || (!previous.acknowledged && current.acknowledged),
      listener: (context, state) {
        if (state.error != null) {
          showMessage(context, state.error!, isError: true);
        } else if (state.acknowledged) {
          showMessage(context, 'Parâmetros confirmados pelo controlador');
        }
      },
      builder: (context, state) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  key: const Key('params_load'),
                  onPressed: state.loading ? null : () => bloc.add(const DeviceParamsLoaded()),
                  icon: const Icon(Icons.download),
                  label: const Text('Ler da máquina'),
                ),
                FilledButton.icon(
                  key: const Key('params_send'),
                  onPressed: connected && !state.ackPending && !state.hasErrors ? () => _send(context) : null,
                  icon: const Icon(Icons.upload),
                  label: Text(state.ackPending ? 'Aguardando confirmação…' : 'Enviar'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final field in DeviceParamField.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ParamField(
                  field: field,
                  label: _labels[field]!,
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
    // Só sobrescreve o texto quando o valor mudou por fora (leitura ou confirmação).
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
