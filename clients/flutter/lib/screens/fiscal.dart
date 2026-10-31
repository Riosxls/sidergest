import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';
import '../session.dart';
import '../widgets/actions.dart';
import '../widgets/page_column.dart';
import '../widgets/pipeline.dart';
import '../widgets/record_list.dart';
import 'sales_common.dart';

const fiscalKinds = {'Sale': 'Venda', 'OutsideShipment': 'Remessa p/ industrialização'};
const fiscalStatuses = {'Authorized': 'Autorizada', 'Cancelled': 'Cancelada', 'Pending': 'Pendente na SEFAZ', 'Rejected': 'Rejeitada'};

Future<void> openFiscalDocument(BuildContext context, Session session, int id) => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => FiscalDocumentScreen(session: session, id: id),
  ),
);

class FiscalDocumentsScreen extends StatefulWidget {
  const FiscalDocumentsScreen({super.key, required this.session});

  final Session session;

  @override
  State<FiscalDocumentsScreen> createState() => _FiscalDocumentsScreenState();
}

class _FiscalDocumentsScreenState extends State<FiscalDocumentsScreen> {
  final _list = GlobalKey<RecordListState>();
  String? _kind;
  String? _status;

  Future<void> _inutilize() async {
    final r = await submitForm(
      context,
      api: widget.session.api,
      title: 'Inutilizar numeração',
      fields: const [
        FieldSpec('from', 'Primeiro número', type: FieldType.integer, required: true, hint: 'Só números já pulados (NF rejeitada ou perdida)'),
        FieldSpec('to', 'Último número', type: FieldType.integer, required: true),
        FieldSpec('reason', 'Motivo', required: true, hint: 'Mínimo de 15 caracteres (regra da SEFAZ)'),
        FieldSpec('password', 'Sua senha', required: true, obscure: true, hint: 'Confirma que é você inutilizando'),
      ],
      submit: (b) => widget.session.api.post('/api/fiscal/inutilizations', b),
    );
    if (r != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Numeração ${r['fromNumber']} a ${r['toNumber']} inutilizada (protocolo ${r['protocol']})')));
      _list.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) => RecordList(
    key: _list,
    api: widget.session.api,
    path: '/api/fiscal/documents',
    fab: widget.session.canFiscalCancel
        ? FloatingActionButton.extended(onPressed: _inutilize, icon: const Icon(Icons.layers_clear_outlined), label: const Text('Inutilizar numeração'))
        : null,
    query: {'kind': _kind, 'status': _status},
    searchHint: 'Destinatário, número ou chave',
    filters: [
      ChoiceFilter(label: 'Tipo', value: _kind, choices: fiscalKinds, onChanged: (v) => setState(() => _kind = v)),
      ChoiceFilter(label: 'Situação', value: _status, choices: fiscalStatuses, onChanged: (v) => setState(() => _status = v)),
    ],
    columns: [
      col('NF', 'number', numeric: true),
      col('Série', 'series', numeric: true),
      col('CFOP', 'cfopCode'),
      labelCol('Tipo', 'kind', fiscalKinds),
      col('Destinatário', 'recipientName'),
      moneyCol('Valor', 'invoiceTotal'),
      dateCol('Emissão', 'issuedAt'),
      labelCol('Situação', 'status', fiscalStatuses),
      ColumnSpec('Simulada', (e) => e['simulated'] == true ? 'Sim' : ''),
    ],
    onTap: (e) async {
      await openFiscalDocument(context, widget.session, e['id'] as int);
      _list.currentState?.reload();
    },
  );
}

class FiscalDocumentScreen extends StatefulWidget {
  const FiscalDocumentScreen({super.key, required this.session, required this.id});

  final Session session;
  final int id;

  @override
  State<FiscalDocumentScreen> createState() => _FiscalDocumentScreenState();
}

class _FiscalDocumentScreenState extends State<FiscalDocumentScreen> {
  Map<String, dynamic>? _d;
  String? _error;

  ApiClient get api => widget.session.api;
  Session get s => widget.session;
  String get base => '/api/fiscal/documents/${widget.id}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await api.get(base) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _d = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _cancel() async {
    final d = _d!;
    final r = await submitForm(
      context,
      api: api,
      title: 'Cancelar NF ${d['number']}',
      fields: const [
        FieldSpec('reason', 'Motivo do cancelamento', required: true, hint: 'Mínimo de 15 caracteres (regra da SEFAZ)'),
        FieldSpec('password', 'Sua senha', required: true, obscure: true, hint: 'Confirma que é você cancelando'),
      ],
      submit: (b) => api.post('$base/cancel', b),
    );
    if (r != null && r['number'] != null) {
      setState(() => _d = r);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('NF cancelada')));
    }
  }

  Future<void> _reconcile() async {
    try {
      final r = await api.post('$base/reconcile?minAgeMinutes=0', {}) as Map<String, dynamic>;
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${r['message']}')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final canCancel = s.canFiscalCancel && d?['status'] == 'Authorized';
    final canReconcile = s.canFiscalCancel && d?['status'] == 'Pending';
    return Scaffold(
      appBar: AppBar(
        title: Text(d == null ? 'Nota fiscal' : 'NF ${d['number']} · ${d['recipientName']}', overflow: TextOverflow.ellipsis),
        actions: [
          if (canCancel)
            PopupMenuButton<VoidCallback>(
              onSelected: (f) => f(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _cancel,
                  child: const ListTile(leading: Icon(Icons.block), title: Text('Cancelar NF')),
                ),
              ],
            ),
          if (canReconcile)
            TextButton.icon(onPressed: _reconcile, icon: const Icon(Icons.sync), label: const Text('Conciliar com a SEFAZ')),
        ],
      ),
      body: _error != null && d == null
          ? Center(child: Text(_error!))
          : d == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _load, child: _body(d)),
    );
  }

  Widget _body(Map<String, dynamic> d) {
    final cancelled = d['status'] == 'Cancelled';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        RecordHeader(
          icon: Icons.description_outlined,
          kind: fiscalKinds['${d['kind']}'] ?? '${d['kind']}',
          title: 'NF ${d['number']} · série ${d['series']}',
          badge: StatusBadge(
            fiscalStatuses[d['status']] ?? '${d['status']}',
            tone: switch (d['status']) {
              'Authorized' => Tone.success,
              'Pending' => Tone.warning,
              _ => Tone.danger,
            },
          ),
          fields: [
            ('Destinatário', '${d['recipientName']}'),
            ('CNPJ/CPF', '${d['recipientDocument']}'),
            ('CFOP', '${d['cfopCode']}'),
            ('Emissão', fmtDate(d['issuedAt'])),
            ('Valor da nota', fmtMoney(d['invoiceTotal'])),
            if (d['deliveryReference'] != null) ('Entrega', '${d['deliveryReference']}'),
          ],
        ),
        if (d['simulated'] == true) ...[
          gap,
          const NextStepCard(
            title: 'Autorização simulada',
            message: 'Esta NF foi autorizada pelo emissor de teste (stub). Não foi enviada à SEFAZ e não tem valor fiscal.',
            tone: Tone.warning,
          ),
        ],
        if (d['status'] == 'Pending' || d['status'] == 'Rejected' || d['statusMessage'] != null) ...[
          gap,
          NextStepCard(
            title: switch (d['status']) {
              'Pending' => 'Aguardando resposta da SEFAZ',
              'Rejected' => 'NF rejeitada: número perdido',
              _ => 'Observação',
            },
            message: d['status'] == 'Pending'
                ? 'A resposta da SEFAZ não chegou. Use "Conciliar com a SEFAZ" para consultar a chave antes de emitir de novo. ${fmt(d['statusMessage'])}'
                : d['status'] == 'Rejected'
                ? '${fmt(d['statusMessage'])} Se o número não será reaproveitado, use "Inutilizar numeração" na lista de notas.'
                : fmt(d['statusMessage']),
            tone: d['status'] == 'Rejected' ? Tone.danger : Tone.warning,
          ),
        ],
        if (cancelled) ...[
          gap,
          NextStepCard(title: 'NF cancelada', message: '${fmt(d['cancelReason'])} · ${fmt(d['cancelledBy'])} em ${fmtDate(d['cancelledAt'])}', tone: Tone.danger),
        ],
        gap,
        Section(
          title: 'Itens',
          child: SimpleTable(
            columns: [
              col('Item', 'sequence'),
              col('Código', 'code'),
              col('Descrição', 'description'),
              col('NCM', 'ncm'),
              ColumnSpec('Qtd.', (e) => '${fmt(e['quantity'])} ${e['unit']}', numeric: true),
              ColumnSpec('Preço', (e) => fmtNum(e['unitPrice'], 4), numeric: true),
              moneyCol('Total', 'total'),
              ColumnSpec('ICMS', (e) => '${e['icmsCst']} · ${fmtMoney(e['icmsValue'])}', numeric: true),
              ColumnSpec('IPI', (e) => '${e['ipiCst']} · ${fmtMoney(e['ipiValue'])}', numeric: true),
            ],
            rows: (d['lines'] as List).cast<Map<String, dynamic>>(),
          ),
        ),
        gap,
        Section(
          title: 'Totais',
          child: InfoGrid([
            ('Produtos', fmtMoney(d['productsTotal'])),
            ('Frete', fmtMoney(d['freightTotal'])),
            ('Base ICMS', fmtMoney(d['icmsBase'])),
            ('ICMS', fmtMoney(d['icmsTotal'])),
            ('IPI', fmtMoney(d['ipiTotal'])),
            ('PIS', fmtMoney(d['pisTotal'])),
            ('COFINS', fmtMoney(d['cofinsTotal'])),
            ('Total da nota', fmtMoney(d['invoiceTotal'])),
          ]),
        ),
        if ((d['installments'] as List).isNotEmpty) ...[
          gap,
          Section(
            title: 'Duplicatas',
            child: SimpleTable(
              columns: [col('Parcela', 'sequence'), dateCol('Vencimento', 'dueDate'), moneyCol('Valor', 'amount')],
              rows: (d['installments'] as List).cast<Map<String, dynamic>>(),
            ),
          ),
        ],
        gap,
        Section(
          title: 'Autorização',
          child: InfoGrid([
            ('Chave de acesso', fmt(d['accessKey'])),
            ('Protocolo', fmt(d['protocol'])),
            ('Ambiente', d['environment'] == 'Production' ? 'Produção' : 'Homologação'),
            ('Emitida por', fmt(d['issuedBy'])),
            ('Informações adicionais', fmt(d['additionalInfo'])),
          ]),
        ),
      ],
    );
  }
}

/// Issuer data, environment and numbering. Admin only; fiscal emission stays off until enabled here.
class FiscalSettingsScreen extends StatefulWidget {
  const FiscalSettingsScreen({super.key, required this.session});

  final Session session;

  @override
  State<FiscalSettingsScreen> createState() => _FiscalSettingsScreenState();
}

class _FiscalSettingsScreenState extends State<FiscalSettingsScreen> {
  late Future<Map<String, dynamic>> _future = _fetch();

  static const _environments = {'Homologation': 'Homologação', 'Production': 'Produção'};

  static const _fields = [
    FieldSpec('enabled', 'Emitir NF-e automaticamente', type: FieldType.boolean),
    FieldSpec('environment', 'Ambiente', type: FieldType.choice, choices: _environments, required: true),
    FieldSpec('companyName', 'Razão social'),
    FieldSpec('tradeName', 'Nome fantasia'),
    FieldSpec('cnpj', 'CNPJ'),
    FieldSpec('stateRegistration', 'Inscrição estadual'),
    FieldSpec('taxRegime', 'Regime tributário (CRT)', type: FieldType.integer, required: true, hint: '3 = regime normal'),
    FieldSpec('street', 'Logradouro'),
    FieldSpec('number', 'Número'),
    FieldSpec('complement', 'Complemento'),
    FieldSpec('district', 'Bairro'),
    FieldSpec('city', 'Município'),
    FieldSpec('cityIbgeCode', 'Código IBGE do município', hint: '7 dígitos'),
    FieldSpec('uf', 'UF', required: true),
    FieldSpec('zipCode', 'CEP'),
    FieldSpec('phone', 'Telefone'),
    FieldSpec('series', 'Série', type: FieldType.integer, required: true),
    FieldSpec('nextNumber', 'Próximo número da NF', type: FieldType.integer, required: true),
    FieldSpec('cancelWindowHours', 'Prazo para cancelar (horas)', type: FieldType.integer, required: true, hint: '0 = sem limite'),
  ];

  Future<Map<String, dynamic>> _fetch() async => await widget.session.api.get('/api/fiscal/settings') as Map<String, dynamic>;

  Future<void> _edit(Map<String, dynamic> d) async {
    final r = await submitForm(
      context,
      api: widget.session.api,
      title: 'Parâmetros fiscais',
      fields: _fields,
      initial: d,
      submit: (b) => widget.session.api.put('/api/fiscal/settings', b),
    );
    if (r != null) setState(() => _future = _fetch());
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _future,
    builder: (context, snap) {
      if (snap.hasError) return Center(child: Text(friendlyError(snap.error!)));
      final d = snap.data;
      if (d == null) return const Center(child: CircularProgressIndicator());
      String has(String k) => '${d[k] ?? ''}'.trim();
      String or(String k) => has(k).isEmpty ? 'Não informado' : has(k);
      final missing = [
        if (has('companyName').isEmpty) 'razão social',
        if (has('cnpj').isEmpty) 'CNPJ',
        if (has('stateRegistration').isEmpty) 'inscrição estadual',
        if (has('street').isEmpty || has('city').isEmpty || has('cityIbgeCode').isEmpty) 'endereço completo',
      ];
      final address = [d['street'], d['number'], d['district'], d['city'], d['uf'], d['zipCode']].where((x) => x != null && '$x'.isNotEmpty).join(', ');
      return PageColumn(child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          NextStepCard(
            title: d['enabled'] == true ? 'Emissão de NF-e ligada' : 'Emissão de NF-e desligada',
            message: d['enabled'] == true
                ? 'Expedir entrega e enviar remessa de beneficiamento sem informar a NF emitem a nota. Ambiente: ${_environments[d['environment']] ?? d['environment']}. A SEFAZ ainda é simulada.'
                : 'Enquanto desligada, o número da NF continua sendo digitado à mão.',
            tone: d['enabled'] == true ? Tone.success : Tone.warning,
            actions: [
              if (widget.session.isAdmin) FilledButton.tonalIcon(onPressed: () => _edit(d), icon: const Icon(Icons.edit_outlined), label: const Text('Editar parâmetros')),
            ],
          ),
          if (missing.isNotEmpty) ...[
            gap,
            NextStepCard(
              title: 'Dados do emitente incompletos',
              message: 'Falta preencher: ${missing.join(', ')}. A NF-e não pode ser emitida sem esses dados.',
              tone: Tone.warning,
            ),
          ],
          gap,
          Section(
            title: 'Emitente',
            actions: [
              if (widget.session.isAdmin) IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(d)),
            ],
            child: InfoGrid([
              ('Razão social', or('companyName')),
              ('CNPJ', or('cnpj')),
              ('Inscrição estadual', or('stateRegistration')),
              ('Regime tributário', switch (d['taxRegime']) {
                1 => 'Simples Nacional',
                2 => 'Simples Nacional (excesso)',
                _ => 'Regime normal',
              }),
              ('Endereço', address.isEmpty || address == '${d['uf']}' ? 'Não informado' : address),
              ('Código IBGE', or('cityIbgeCode')),
            ]),
          ),
          gap,
          Section(
            title: 'Emissão',
            actions: [
              if (widget.session.isAdmin) IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(d)),
            ],
            child: InfoGrid([
              ('Ambiente', _environments[d['environment']] ?? '${d['environment']}'),
              ('Série', '${d['series']}'),
              ('Próximo número', '${d['nextNumber']}'),
              ('Prazo para cancelar', d['cancelWindowHours'] == 0 ? 'Sem limite' : '${d['cancelWindowHours']} h'),
            ]),
          ),
        ],
      ));
    },
  );
}
