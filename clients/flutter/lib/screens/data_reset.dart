import 'package:flutter/material.dart';

import '../api.dart';
import '../session.dart';
import '../widgets/record_list.dart';

/// Word the admin types before movement data is deleted; the server checks it too.
const dataResetConfirmWord = 'LIMPAR';

class _Scope {
  const _Scope(this.key, this.title, this.detail, {this.warning});

  final String key;
  final String title;
  final String detail;
  final String? warning;
}

const _scopes = [
  _Scope('Sales', 'Comercial', 'Orçamentos, pedidos de venda, entregas, certificados, análises de viabilidade e notas fiscais simuladas'),
  _Scope('Purchasing', 'Suprimentos', 'Requisições, cotações, pedidos de compra e recebimentos', warning: 'Inclui o que veio do sistema antigo'),
  _Scope('Production', 'PCP', 'Ordens de fabricação e apontamentos', warning: 'Inclui o que veio do sistema antigo'),
  _Scope('Stock', 'Estoque', 'Movimentações, lotes, reservas e bobinas', warning: 'O saldo de estoque volta a zero.'),
];

const _tableNames = {
  'quotes': 'Orçamentos',
  'quote_lines': 'Itens de orçamento',
  'quote_request_files': 'Anexos de orçamento',
  'sales_orders': 'Pedidos de venda',
  'sales_order_lines': 'Itens de pedido de venda',
  'sales_events': 'Histórico comercial',
  'deliveries': 'Entregas',
  'delivery_lines': 'Itens de entrega',
  'quality_certificates': 'Certificados de qualidade',
  'certificate_measures': 'Medições de certificado',
  'feasibility_studies': 'Análises de viabilidade',
  'fiscal_documents': 'Notas fiscais',
  'fiscal_document_lines': 'Itens de nota fiscal',
  'fiscal_installments': 'Parcelas de nota fiscal',
  'purchase_requisitions': 'Requisições',
  'quotations': 'Cotações',
  'quotation_items': 'Itens de cotação',
  'quotation_bids': 'Propostas de fornecedor',
  'purchase_orders': 'Pedidos de compra',
  'purchase_order_lines': 'Itens de pedido de compra',
  'goods_receipts': 'Recebimentos',
  'goods_receipt_lines': 'Itens de recebimento',
  'payable_installments': 'Parcelas a pagar',
  'production_orders': 'Ordens de fabricação',
  'production_order_operations': 'Operações de OF',
  'production_order_materials': 'Materiais de OF',
  'production_reports': 'Apontamentos',
  'production_occurrences': 'Ocorrências',
  'outside_shipments': 'Remessas a terceiros',
  'overrun_releases': 'Liberações de excedente',
  'stock_documents': 'Documentos de estoque',
  'stock_movements': 'Movimentações de estoque',
  'stock_reservations': 'Reservas',
  'stock_balances': 'Saldos',
  'average_costs': 'Custos médios',
  'stock_closings': 'Fechamentos',
  'stock_lots': 'Lotes',
  'steel_lots': 'Bobinas',
  'steel_usages': 'Consumo de bobinas',
  'slitter_jobs': 'Cortes de bobina',
};

/// Opens the "clear movement data" dialog. Returns true when something was deleted.
Future<bool> showDataResetDialog(BuildContext context, Session session) async =>
    await showDialog<bool>(context: context, builder: (_) => _DataResetDialog(session: session)) ?? false;

class _DataResetDialog extends StatefulWidget {
  const _DataResetDialog({required this.session});

  final Session session;

  @override
  State<_DataResetDialog> createState() => _DataResetDialogState();
}

class _DataResetDialogState extends State<_DataResetDialog> {
  final _selected = <String>{'Sales'};
  final _confirm = TextEditingController();
  List<Map<String, dynamic>>? _preview;
  int _total = 0;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _body => {'scopes': _selected.toList()};

  Future<void> _showPreview() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.session.api.post('/api/admin/data-reset/preview', _body) as Map<String, dynamic>;
      setState(() {
        _preview = [
          for (final t in (r['tables'] as List).cast<Map<String, dynamic>>())
            if ((t['rows'] as num) > 0) t,
        ];
        _total = (r['totalRows'] as num).toInt();
      });
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.session.api.post('/api/admin/data-reset', {..._body, 'confirm': _confirm.text.trim()}) as Map<String, dynamic>;
      NameCache.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${r['totalRows']} registros apagados')));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggle(String key, bool on) => setState(() {
    on ? _selected.add(key) : _selected.remove(key);
    _preview = null;
    _confirm.clear();
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canDelete = _preview != null && _confirm.text.trim() == dataResetConfirmWord && !_busy;
    return AlertDialog(
      title: const Text('Limpar dados de movimento'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Apaga os registros do dia a dia para recomeçar do zero. Produtos, materiais, clientes, fornecedores, ferramentas, preços e usuários não são apagados.'),
              const SizedBox(height: 8),
              for (final s in _scopes)
                CheckboxListTile(
                  key: ValueKey('reset-${s.key}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _selected.contains(s.key),
                  onChanged: _busy ? null : (v) => _toggle(s.key, v ?? false),
                  title: Text(s.title),
                  subtitle: Text(s.warning == null ? s.detail : '${s.detail}. ${s.warning}'),
                ),
              if (_preview != null) ...[
                const Divider(),
                Text(_total == 0 ? 'Não há nada para apagar nesta seleção.' : 'Serão apagados $_total registros:', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                for (final t in _preview!)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Row(
                      children: [
                        Expanded(child: Text(_tableNames[t['table']] ?? '${t['table']}')),
                        Text('${t['rows']}'),
                      ],
                    ),
                  ),
                if (_total > 0) ...[
                  const SizedBox(height: 12),
                  Text('Não dá para desfazer. Faça um backup do banco antes.', style: TextStyle(color: cs.error)),
                  const SizedBox(height: 8),
                  TextField(
                    key: const ValueKey('reset-confirm'),
                    controller: _confirm,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Digite $dataResetConfirmWord para confirmar', border: OutlineInputBorder(), isDense: true),
                  ),
                ],
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: TextStyle(color: cs.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancelar')),
        if (_preview == null)
          FilledButton(key: const ValueKey('reset-preview'), onPressed: _busy || _selected.isEmpty ? null : _showPreview, child: const Text('Ver o que será apagado'))
        else if (_total > 0)
          FilledButton(
            key: const ValueKey('reset-run'),
            style: FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError),
            onPressed: canDelete ? _run : null,
            child: const Text('Apagar definitivamente'),
          ),
      ],
    );
  }
}
