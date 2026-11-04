import 'package:flutter/material.dart';

import '../theme_tokens.dart';
import '../widgets/responsive.dart';

/// Form of "Enviar por e-mail": recipients, subject and text; the PDF is built and attached when the dialog returns.
class QuoteEmailDialog extends StatefulWidget {
  const QuoteEmailDialog({super.key, required this.to, required this.subject, required this.body, required this.from, required this.fileName, required this.registers, this.onSend});

  final String to;
  final String subject;
  final String body;
  final String? from;
  final String fileName;

  /// The send also starts the quote's validity (a draft or approved quote); false when it was already sent.
  final bool registers;

  /// Does the sending while the dialog stays open showing a busy state; true closes the dialog, false keeps it for another try.
  /// Without it the dialog just returns the typed form.
  final Future<bool> Function(Map<String, String> form)? onSend;

  @override
  State<QuoteEmailDialog> createState() => QuoteEmailDialogState();
}

class QuoteEmailDialogState extends State<QuoteEmailDialog> {
  late final _to = TextEditingController(text: widget.to.contains('@') ? widget.to : '');
  final _cc = TextEditingController();
  late final _subject = TextEditingController(text: widget.subject);
  late final _body = TextEditingController(text: widget.body);
  final _form = GlobalKey<FormState>();
  bool _busy = false;

  @override
  void dispose() {
    _to.dispose();
    _cc.dispose();
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  static final _address = RegExp(r'^[^\s@;,]+@[^\s@;,]+\.[^\s@;,]+$');

  /// null when every address of the typed list (separated by ; or ,) looks like an e-mail address.
  static String? _check(String? v, {required bool required}) {
    final parts = (v ?? '').split(RegExp(r'[;,\n]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return required ? 'Informe o e-mail do cliente' : null;
    final bad = parts.where((p) => !_address.hasMatch(p));
    return bad.isEmpty ? null : 'E-mail inválido: ${bad.first}';
  }

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    final form = {'to': _to.text.trim(), 'cc': _cc.text.trim(), 'subject': _subject.text.trim(), 'body': _body.text};
    final send = widget.onSend;
    if (send == null) {
      Navigator.pop(context, form);
      return;
    }
    setState(() => _busy = true);
    final ok = await send(form);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, form);
    } else {
      setState(() => _busy = false);
    }
  }

  Widget _notice(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = '${widget.from == null ? '' : 'Sai de ${widget.from}. '}${widget.registers ? 'O envio fica registrado e a validade começa a contar hoje.' : 'O orçamento já foi enviado: este é um reenvio.'}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(AppRadius.chip)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: cs.onSecondaryContainer),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSecondaryContainer))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.forward_to_inbox),
    title: const Text('Enviar orçamento por e-mail'),
    content: DialogBody(
      ideal: 520,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                key: const ValueKey('email-to'),
                controller: _to,
                autofocus: _to.text.isEmpty,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Para', helperText: 'Mais de um e-mail: separe com ;'),
                validator: (v) => _check(v, required: true),
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const ValueKey('email-cc'),
                controller: _cc,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Cópia (opcional)'),
                validator: (v) => _check(v, required: false),
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const ValueKey('email-subject'),
                controller: _subject,
                decoration: const InputDecoration(labelText: 'Assunto'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Informe o assunto' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const ValueKey('email-body'),
                controller: _body,
                minLines: 5,
                maxLines: 10,
                decoration: const InputDecoration(labelText: 'Mensagem', alignLabelWithHint: true),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Anexo: ${widget.fileName}', style: Theme.of(context).textTheme.bodySmall)),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      // What the send does is said right above the buttons, where the decision is made.
      _notice(context),
      TextButton(key: const ValueKey('email-cancel'), onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton.icon(
        key: const ValueKey('email-send'),
        onPressed: _busy ? null : _submit,
        icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
        label: Text(_busy ? 'Enviando...' : 'Enviar'),
      ),
    ],
  );
}
