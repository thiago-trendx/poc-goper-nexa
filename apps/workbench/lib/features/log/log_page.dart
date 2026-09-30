import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../shared/widgets/feedback.dart';
import 'log_cubit.dart';
import 'log_exporter.dart';

/// Log de pacotes tx/rx, conexão e erros, com as entradas mais novas no topo.
class LogPage extends StatelessWidget {
  const LogPage({super.key});

  Future<void> _save(BuildContext context, LogCubit cubit) async {
    final exporter = context.read<LogExporter>();
    try {
      final path = await exporter.save(cubit.exportText());
      if (context.mounted) showMessage(context, 'Log salvo em $path (copie com adb pull)');
    } on Exception catch (e) {
      if (context.mounted) showMessage(context, 'Falha ao salvar o log: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<LogCubit>();
    return BlocBuilder<LogCubit, List<LogLine>>(
      builder: (context, lines) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('${lines.length} linhas (máx. ${cubit.maxEntries})'),
                  OutlinedButton.icon(
                    key: const Key('log_copy'),
                    onPressed: lines.isEmpty
                        ? null
                        : () async {
                            await Clipboard.setData(ClipboardData(text: cubit.exportText()));
                            if (context.mounted) showMessage(context, 'Log copiado para a área de transferência');
                          },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copiar'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('log_save'),
                    onPressed: lines.isEmpty ? null : () => _save(context, cubit),
                    icon: const Icon(Icons.save_alt),
                    label: const Text('Salvar .txt'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('log_clear'),
                    onPressed: lines.isEmpty ? null : cubit.clear,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Limpar'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: lines.isEmpty
                  ? const Center(child: Text('Sem registros'))
                  : ListView.builder(
                      itemCount: lines.length,
                      itemBuilder: (context, index) {
                        final line = lines[lines.length - 1 - index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                          child: Text(
                            line.text,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
