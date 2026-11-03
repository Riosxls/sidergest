import 'package:flutter/material.dart';


/// Form of "Enviar por e-mail": recipients, subject and text; the PDF is built and attached when the dialog returns.
class QuoteEmailDialog extends StatefulWidget {
  const QuoteEmailDialog({super.key, required this.to, required this.subject, required this.body, required this.from, required this.fileName, required this.registers});

  final String to;
  final String subject;
  final String body;
  final String? from;
  final String fileName;

  /// The send also starts the quote's validity (a draft or approved quote); false when it was already sent.
  final bool registers;

  @override
  State<QuoteEmailDialog> createState() => QuoteEmailDialogState();
}

class QuoteEmailDialogState extends State<QuoteEmailDialog> {
  late final _to = TextEditingController(text: widget.to.contains('@') ? widget.to : '');
  final _cc = TextEditingController();
  late final _subject = TextEditingController(text: widget.subject);
  late final _body = TextEditingController(text: widget.body);
  final _form = GlobalKey<FormState>();

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

  void _submit() {
    if (!(_form.currentState?.validate() ?? false)) return;
    Navigator.pop(context, {'to': _to.text.trim(), 'cc': _cc.text.trim(), 'subject': _subject.text.trim(), 'body': _body.text});
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.forward_to_inbox),
    title: const Text('Enviar orçamento por e-mail'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
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
              const SizedBox(height: 4),
              Text(
                '${widget.from == null ? '' : 'Sai de ${widget.from}. '}${widget.registers ? 'O envio fica registrado e a validade começa a contar hoje.' : 'O orçamento já foi enviado: este é um reenvio.'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(key: const ValueKey('email-cancel'), onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton.icon(key: const ValueKey('email-send'), onPressed: _submit, icon: const Icon(Icons.send), label: const Text('Enviar')),
    ],
  );
}
