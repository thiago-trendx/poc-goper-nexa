import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../shared/widgets/feedback.dart';
import '../connection/connection_bloc.dart';
import 'lift_motor_bloc.dart';

/// Motores de elevação: posições 1 e 2, autoteste, contagem regressiva e erros.
class LiftMotorPage extends StatefulWidget {
  const LiftMotorPage({super.key});

  @override
  State<LiftMotorPage> createState() => _LiftMotorPageState();
}

class _LiftMotorPageState extends State<LiftMotorPage> {
  final _p1 = TextEditingController(text: '0');
  final _p2 = TextEditingController(text: '0');

  @override
  void dispose() {
    _p1.dispose();
    _p2.dispose();
    super.dispose();
  }

  static String _phaseLabel(LiftPhase phase) => switch (phase) {
        LiftPhase.idle => 'Ocioso',
        LiftPhase.adjusting => 'Ajustando posição',
        LiftPhase.selfChecking => 'Em autoteste',
        LiftPhase.completed => 'Concluído',
        LiftPhase.timeout => 'Timeout de segurança',
      };

  static String _statusLabel(int status) => switch (status) {
        0x00 => 'Parado',
        0x01 => 'Em movimento',
        0x02 => 'Em autoteste',
        _ => 'Desconhecido (${_hex(status)})',
      };

  static String _hex(int value) => '0x${value.toRadixString(16).padLeft(2, '0').toUpperCase()}';

  Future<void> _adjust(BuildContext context) async {
    final bloc = context.read<LiftMotorBloc>();
    final p1 = int.tryParse(_p1.text);
    final p2 = int.tryParse(_p2.text);
    if (p1 == null || p2 == null || p1 < 0 || p2 < 0) {
      showMessage(context, 'As posições devem ser números inteiros não negativos', isError: true);
      return;
    }
    final confirmed = await confirmAction(
      context,
      title: 'Ajustar posição dos motores?',
      message: 'Os motores de elevação vão se mover para as posições $p1 e $p2. '
          'O movimento será parado antes do ajuste. Mantenha a área livre.',
      confirmLabel: 'Ajustar',
    );
    if (confirmed) bloc.add(PositionRequested(p1: p1, p2: p2));
  }

  Future<void> _selfCheck(BuildContext context) async {
    final bloc = context.read<LiftMotorBloc>();
    final confirmed = await confirmAction(
      context,
      title: 'Iniciar autoteste dos motores?',
      message: 'O autoteste move os motores de elevação e pode levar mais de 2 minutos. '
          'Mantenha a área livre.',
      confirmLabel: 'Iniciar',
    );
    if (confirmed) bloc.add(const SelfCheckRequested());
  }

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<ConnectionBloc>().state.isConnected;
    return BlocConsumer<LiftMotorBloc, LiftMotorState>(
      listenWhen: (previous, current) => previous.errorSeq != current.errorSeq,
      listener: (context, state) {
        if (state.error != null) showMessage(context, state.error!, isError: true);
      },
      builder: (context, state) {
        final enabled = connected && !state.busy;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Section(
              title: 'Posição dos motores',
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final (key, label, controller) in [
                    ('lift_p1', 'Posição 1', _p1),
                    ('lift_p2', 'Posição 2', _p2),
                  ])
                    SizedBox(
                      width: 140,
                      child: TextField(
                        key: Key(key),
                        controller: controller,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
                      ),
                    ),
                  FilledButton(
                    key: const Key('lift_adjust'),
                    onPressed: enabled ? () => _adjust(context) : null,
                    child: const Text('Ajustar posição'),
                  ),
                  OutlinedButton(
                    key: const Key('lift_self_check'),
                    onPressed: enabled ? () => _selfCheck(context) : null,
                    child: const Text('Autoteste'),
                  ),
                ],
              ),
            ),
            Section(
              title: 'Andamento',
              child: Card(
                child: Column(
                  children: [
                    ListTile(
                      key: const Key('lift_phase'),
                      title: Text(_phaseLabel(state.phase)),
                      subtitle: state.busy ? Text('Timeout de segurança em ${state.remainingSec} s') : null,
                      trailing: state.busy ? const CircularProgressIndicator() : null,
                    ),
                    ListTile(
                      title: const Text('Status dos motores'),
                      subtitle: Text(_statusLabel(state.liftMotorStatus)),
                    ),
                    ListTile(
                      title: const Text('Erros dos motores 1 e 2'),
                      subtitle: Text('${_hex(state.error1)} e ${_hex(state.error2)}'
                          '${state.error1 == 0 && state.error2 == 0 ? ' (sem erro)' : ''}'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
