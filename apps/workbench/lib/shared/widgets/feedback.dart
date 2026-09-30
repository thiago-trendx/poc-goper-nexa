import 'package:flutter/material.dart';

/// Mostra [text] numa SnackBar; em vermelho quando [isError].
void showMessage(BuildContext context, String text, {bool isError = false}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
        content: Text(text),
      ),
    );
}

/// Pede confirmação antes de uma ação que move motores ou altera a calibração.
/// Devolve `true` somente se o usuário confirmar.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirmar',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          key: const Key('confirm_dialog_cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('confirm_dialog_confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Campo numérico com botões − e +, dentro de [min] e [max] (opcional).
/// Sem [onChanged] fica desabilitado.
class IntStepper extends StatelessWidget {
  const IntStepper({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max,
  });

  final String label;
  final int value;
  final int min;
  final int? max;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final canDecrease = onChanged != null && value > min;
    final canIncrease = onChanged != null && (max == null || value < max!);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 180, child: Text(label)),
        IconButton(
          tooltip: 'Diminuir $label',
          onPressed: canDecrease ? () => onChanged!(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 48,
          child: Text('$value', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        ),
        IconButton(
          tooltip: 'Aumentar $label',
          onPressed: canIncrease ? () => onChanged!(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}

/// Título de seção com o conteúdo logo abaixo.
class Section extends StatelessWidget {
  const Section({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
