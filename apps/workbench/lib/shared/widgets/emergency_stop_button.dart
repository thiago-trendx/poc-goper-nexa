import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sdk850_bridge/sdk850_bridge.dart';

import '../../data/machine_repository.dart';

/// Botão STOP fixo em todas as telas.
///
/// Chama `stop()` direto no repositório, sem passar por fila de Bloc, e nunca fica
/// desabilitado: se o envio falhar, o erro aparece na tela.
class EmergencyStopButton extends StatelessWidget {
  const EmergencyStopButton({super.key});

  static const buttonKey = Key('emergency_stop_button');

  Future<void> _stop(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final repository = context.read<MachineRepository>();
    final errorColor = Theme.of(context).colorScheme.error;
    try {
      await repository.stop();
    } on MachineException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: errorColor,
          content: Text('Falha ao enviar STOP: ${e.message ?? e.code}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Parada de emergência',
      child: FilledButton.icon(
        key: buttonKey,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.red.shade700,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(64),
          textStyle: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        onPressed: () => _stop(context),
        icon: const Icon(Icons.stop_circle, size: 32),
        label: const Text('STOP'),
      ),
    );
  }
}
