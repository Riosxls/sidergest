import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';
import '../labels.dart';
import '../session.dart';
import '../theme_tokens.dart';
import '../widgets/entity_form.dart';
import '../widgets/load_error.dart';
import '../widgets/record_list.dart';
import '../widgets/record_nav.dart';
import 'receivables.dart';
import 'sales_common.dart';
import 'sales_quotes.dart' show newQuote;

const customerStatuses = {'true': 'Ativos', 'false': 'Inativos'};

/// CPF (11 digits) or CNPJ (14 digits) with punctuation; other values are returned as-is.
String fmtDocument(Object? v) {
  final d = '${v ?? ''}';
  if (RegExp(r'^\d{11}$').hasMatch(d)) return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9)}';
  if (RegExp(r'^\d{14}$').hasMatch(d)) return '${d.substring(0, 2)}.${d.substring(2, 5)}.${d.substring(5, 8)}/${d.substring(8, 12)}-${d.substring(12)}';
  return d;
}

/// The 27 Brazilian states, for the UF dropdown.
const _ufs = {
  'AC': 'AC',
  'AL': 'AL',
  'AP': 'AP',
  'AM': 'AM',
  'BA': 'BA',
  'CE': 'CE',
  'DF': 'DF',
  'ES': 'ES',
  'GO': 'GO',
  'MA': 'MA',
  'MT': 'MT',
  'MS': 'MS',
  'MG': 'MG',
  'PA': 'PA',
  'PB': 'PB',
  'PR': 'PR',
  'PE': 'PE',
  'PI': 'PI',
  'RJ': 'RJ',
  'RN': 'RN',
  'RS': 'RS',
  'RO': 'RO',
  'RR': 'RR',
  'SC': 'SC',
  'SP': 'SP',
  'SE': 'SE',
  'TO': 'TO',
};

/// A stored UF that is not one of the 27 (old data typed by hand) would break the dropdown: it is upper-cased, or dropped when unknown.
Map<String, dynamic> _normalizeUf(Map<String, dynamic> m, String key) {
  final v = '${m[key] ?? ''}'.trim().toUpperCase();
  return {...m, key: _ufs.containsKey(v) ? v : null};
}

String _digits(Object? v) => '${v ?? ''}'.replaceAll(RegExp(r'\D'), '');

/// Simple format checks on the fields that changed: CNPJ/CPF has 11 or 14 digits, CEP has 8. Old values nobody touched never block a save.
/// [prefix] is the form key prefix of the fields ('company.' or ''); [before] the values already stored.
Map<String, List<String>> _formatErrors(Map<String, dynamic> now, Map<String, dynamic>? before, {String prefix = ''}) {
  final errors = <String, List<String>>{};
  bool changed(String k) => _digits(now[k]) != _digits(before?[k]);
  final doc = _digits(now['document']);
  if (doc.isNotEmpty && changed('document') && doc.length != 11 && doc.length != 14) {
    errors['${prefix}document'] = ['CNPJ tem 14 dígitos e CPF tem 11'];
  }
  final zip = _digits(now['zipCode']);
  if (zip.isNotEmpty && changed('zipCode') && zip.length != 8) errors['${prefix}zipCode'] = ['CEP tem 8 dígitos'];
  return errors;
}

void _throwIfInvalid(Map<String, List<String>> errors) {
  if (errors.isNotEmpty) throw ApiException(400, 'Confira os campos destacados.', errors);
}

Map<String, dynamic>? _defaultAddress(Map<String, dynamic> c) => c['defaultAddress'] as Map<String, dynamic>?;

Map<String, dynamic>? _company(Map<String, dynamic> c) => c['company'] as Map<String, dynamic>?;

// Company data lives on the customer itself, independent from the delivery locais.
const _companyFields = [
  FieldSpec('document', 'CNPJ/CPF', hint: 'Somente números ou com pontuação'),
  FieldSpec('stateRegistration', 'Inscrição estadual'),
  FieldSpec('icmsContributor', 'Contribuinte de ICMS', type: FieldType.boolean, defaultValue: false),
  FieldSpec('street', 'Endereço fiscal'),
  FieldSpec('number', 'Número'),
  FieldSpec('complement', 'Complemento'),
  FieldSpec('district', 'Bairro'),
  FieldSpec('city', 'Cidade'),
  FieldSpec('uf', 'UF', type: FieldType.choice, choices: _ufs),
  FieldSpec('zipCode', 'CEP', hint: '8 dígitos'),
  FieldSpec('contact', 'Contato'),
  FieldSpec('email', 'E-mail'),
  FieldSpec('phone', 'Telefone'),
  FieldSpec('paymentTermId', 'Prazo padrão', type: FieldType.lookup, lookup: LookupSpec('/api/sales/payment-terms'), hint: 'Usado como padrão nos orçamentos'),
  FieldSpec('creditLimit', 'Limite de crédito (R\$)', type: FieldType.decimal, hint: 'Vazio = vale o limite do prazo'),
];

List<FieldSpec> _companyFormFields() => [
  for (final f in _companyFields) FieldSpec('company.${f.key}', f.label, type: f.type, hint: f.hint, lookup: f.lookup, defaultValue: f.defaultValue, choices: f.choices),
];

(Map<String, dynamic>, Map<String, dynamic>) _splitCompany(Map<String, dynamic> b) {
  final company = <String, dynamic>{};
  final body = <String, dynamic>{};
  b.forEach((k, v) => k.startsWith('company.') ? company[k.substring(8)] = v : body[k] = v);
  return (body, company);
}

String _addressLine(Map<String, dynamic>? a) {
  if (a == null) return '';
  final street = [a['street'], a['number']].where((x) => x != null && '$x'.isNotEmpty).join(', ');
  final place = [a['district'], a['city'] == null ? null : '${a['city']}/${a['uf']}'].where((x) => x != null && '$x'.isNotEmpty).join(' · ');
  return [street, if (a['complement'] != null) a['complement'], place].where((x) => '$x'.isNotEmpty).join(' - ');
}

const _addressFields = [
  FieldSpec('document', 'CNPJ/CPF', required: true, hint: 'Somente números ou com pontuação'),
  FieldSpec('stateRegistration', 'Inscrição estadual'),
  FieldSpec('icmsContributor', 'Contribuinte de ICMS', type: FieldType.boolean, defaultValue: false),
  FieldSpec('street', 'Endereço'),
  FieldSpec('number', 'Número'),
  FieldSpec('complement', 'Complemento'),
  FieldSpec('district', 'Bairro'),
  FieldSpec('city', 'Cidade'),
  FieldSpec('uf', 'UF', required: true, type: FieldType.choice, choices: _ufs),
  FieldSpec('zipCode', 'CEP', hint: '8 dígitos'),
  FieldSpec('buyer', 'Contato'),
  FieldSpec('email', 'E-mail'),
  FieldSpec('phone', 'Telefone'),
];

const _shippingKeys = {'street', 'number', 'complement', 'district', 'city', 'uf', 'zipCode', 'buyer', 'phone', 'email'};
final _shippingFields = [
  for (final f in _addressFields)
    if (_shippingKeys.contains(f.key))
      FieldSpec(
        f.key,
        switch (f.key) {
          'street' => 'Endereço de entrega',
          'buyer' => 'Contato de entrega',
          _ => f.label,
        },
        required: f.required,
        type: f.type,
        choices: f.choices,
        hint: f.hint,
      ),
];

/// Customer list with search and creation.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key, required this.session});

  final Session session;

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _list = GlobalKey<RecordListState>();
  String? _active = 'true';

  Future<void> _new() async {
    final s = widget.session;
    final r = await showEntityForm(
      context,
      api: s.api,
      title: 'Novo cliente',
      fields: [
        const FieldSpec('name', 'Nome / razão social', required: true),
        const FieldSpec('tradeName', 'Nome fantasia'),
        ..._companyFormFields(),
      ],
      onSubmit: (b) async {
        final (rest, company) = _splitCompany(b);
        _throwIfInvalid(_formatErrors(company, null, prefix: 'company.'));
        final body = <String, dynamic>{'consumerType': 'Normal', 'active': true, ...rest, 'company': company};
        // Starting point only: the first delivery local copies the company data when it is complete enough to be saved.
        if (fmt(company['document']).isNotEmpty && fmt(company['uf']).isNotEmpty) {
          body['address'] = {
            for (final k in ['document', 'stateRegistration', 'icmsContributor', 'street', 'number', 'complement', 'district', 'city', 'uf', 'zipCode', 'email', 'phone']) k: company[k],
            'buyer': company['contact'],
          };
        }
        return await s.api.post('/api/customers', body) as Map<String, dynamic>?;
      },
    );
    if (r != null) unawaited(_list.currentState?.reload());
  }

  @override
  Widget build(BuildContext context) => RecordList(
    key: _list,
    api: widget.session.api,
    path: '/api/customers',
    query: {'active': _active},
    searchHint: 'Nome, fantasia, CNPJ/CPF ou código antigo',
    filters: [ChoiceFilter(label: 'Situação', value: _active, choices: customerStatuses, onChanged: (v) => setState(() => _active = v))],
    fab: widget.session.canCustomers
        ? FloatingActionButton.extended(heroTag: 'new-customer', onPressed: _new, icon: const Icon(Icons.add), label: const Text('Novo cliente'))
        : null,
    columns: [
      col('Cliente', 'name'),
      col('Fantasia', 'tradeName'),
      ColumnSpec('CNPJ/CPF', (e) => fmtDocument(_company(e)?['document'])),
      ColumnSpec('Cidade', (e) => _company(e)?['city'] == null ? '' : '${_company(e)!['city']}/${_company(e)!['uf'] ?? ''}'),
      ColumnSpec('Contato', (e) => fmt(_company(e)?['contact'])),
      ColumnSpec('E-mail', (e) => fmt(_company(e)?['email'])),
      ColumnSpec('Telefone', (e) => fmt(_company(e)?['phone'])),
      ColumnSpec('Situação', (e) => e['active'] == true ? 'Ativo' : 'Inativo'),
    ],
    rowColor: (ctx, e) => e['active'] == true ? null : Theme.of(ctx).colorScheme.surfaceContainerHighest,
    onTap: (e) => openCustomer(context, widget.session, e['id'] as int, e),
  );
}

/// Customer detail: company data, addresses, default prazo and credit limit.
/// Opens a customer; pass [known] when the list already holds its data, otherwise it is loaded.
Future<void> openCustomer(BuildContext context, Session session, int id, [Map<String, dynamic>? known]) => pushRecord<void>(
  context,
  'customer',
  id,
  (_) => known != null ? CustomerScreen(session: session, customer: known) : customerScreenById(session, id),
);

/// A customer page for an id alone (web address, restored place).
Widget customerScreenById(Session session, int id) => RecordLoader(
  title: 'Cliente',
  load: () => session.api.get('/api/customers/$id'),
  builder: (c) => CustomerScreen(session: session, customer: c),
);

class CustomerScreen extends StatefulWidget {
  const CustomerScreen({super.key, required this.session, required this.customer});

  final Session session;
  final Map<String, dynamic> customer;

  @override
  State<CustomerScreen> createState() => _CustomerScreenState();
}

class _CustomerScreenState extends State<CustomerScreen> {
  late Map<String, dynamic> _c = widget.customer;
  int get id => _c['id'] as int;
  bool get _isActive => _c['active'] == true;

  Future<Map<String, dynamic>?> _save(Map<String, dynamic> changes) async {
    final r = await widget.session.api.put('/api/customers/$id', {
      'name': _c['name'],
      'tradeName': _c['tradeName'],
      'legacyCode': _c['legacyCode'],
      'consumerType': _c['consumerType'],
      'active': _c['active'],
      ...changes,
    }) as Map<String, dynamic>?;
    if (r != null && mounted) setState(() => _c = r);
    return r;
  }

  Future<void> _edit() async {
    final s = widget.session;
    final company = _company(_c);
    final r = await showEntityForm(
      context,
      api: s.api,
      title: 'Cliente',
      fields: [
        const FieldSpec('name', 'Nome / razão social', required: true),
        const FieldSpec('tradeName', 'Nome fantasia'),
        const FieldSpec('legacyCode', 'Código antigo'),
        ..._companyFormFields(),
      ],
      initial: {..._c, if (company != null) for (final e in _normalizeUf(company, 'uf').entries) 'company.${e.key}': e.value},
      readOnly: !s.canCustomers,
      onSubmit: (b) async {
        final (rest, co) = _splitCompany(b);
        _throwIfInvalid(_formatErrors(co, company, prefix: 'company.'));
        return _save({...rest, 'company': co});
      },
    );
    if (r != null && mounted) setState(() {});
  }

  Future<void> _toggleActive() async {
    final msg = _isActive ? 'Inativar este cliente? Ele deixa de aparecer nas buscas de novos orçamentos e pedidos.' : 'Reativar este cliente?';
    if (!await confirm(context, msg)) return;
    try {
      await _save({'active': !_isActive});
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    // The pencil is the one way to edit the company data; the tabs scroll when the page is narrow.
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${_c['name']}${_isActive ? '' : ' (inativo)'}', overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(tooltip: 'Editar cadastro', onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
            if (s.canCustomers)
              IconButton(
                tooltip: _isActive ? 'Inativar' : 'Reativar',
                onPressed: _toggleActive,
                icon: Icon(_isActive ? Icons.block : Icons.check_circle_outline),
              ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Empresa'),
              Tab(text: 'Locais de entrega'),
              Tab(text: 'Orçamentos'),
              Tab(text: 'Pedidos'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _CustomerCompany(session: s, customer: _c),
            _CustomerAddresses(session: s, customerId: id),
            _CustomerQuotes(session: s, customerId: id, customerName: '${_c['name']}'),
            _CustomerOrders(session: s, customerId: id),
          ],
        ),
      ),
    );
  }
}

class _CustomerCompany extends StatelessWidget {
  const _CustomerCompany({required this.session, required this.customer});

  final Session session;
  final Map<String, dynamic> customer;

  @override
  Widget build(BuildContext context) {
    final a = _company(customer);
    final filled = a != null && a.entries.any((e) => e.key != 'icmsContributor' && e.value != null && '${e.value}'.isNotEmpty);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Section(
          title: 'Dados da empresa',
          child: !filled
              ? const Text('Sem dados cadastrados. Use o lápis (Editar cadastro) para informar CNPJ/CPF, endereço e contato.')
              : InfoGrid([
                  ('Nome', fmt(customer['name'])),
                  ('Fantasia', fmt(customer['tradeName'])),
                  ('CNPJ/CPF', fmtDocument(a['document'])),
                  ('Inscrição estadual', fmt(a['stateRegistration'])),
                  ('Endereço fiscal', _addressLine(a)),
                  ('Cidade', fmt(a['city'])),
                  ('UF', fmt(a['uf'])),
                  ('CEP', fmt(a['zipCode'])),
                  ('Contato', fmt(a['contact'])),
                  ('E-mail', fmt(a['email'])),
                  ('Telefone', fmt(a['phone'])),
                  ('Prazo padrão', fmt(a['paymentTermName'])),
                ]),
        ),
        _CustomerReceivable(session: session, customerId: customer['id'] as int),
      ],
    );
  }
}

/// What the customer owes on authorized NFs and how much of it is late; hidden when the figures cannot be read.
class _CustomerReceivable extends StatefulWidget {
  const _CustomerReceivable({required this.session, required this.customerId});

  final Session session;
  final int customerId;

  @override
  State<_CustomerReceivable> createState() => _CustomerReceivableState();
}

class _CustomerReceivableState extends State<_CustomerReceivable> {
  Map<String, dynamic>? _balance;
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    Map<String, dynamic>? b;
    String? error;
    try {
      final rows = await widget.session.api.get('/api/receivables/balances', {'customerId': widget.customerId});
      b = rows is List && rows.isNotEmpty ? rows.first as Map<String, dynamic> : null;
    } catch (e) {
      // A failed read is not "nothing owed": say so and offer another try.
      error = friendlyError(e);
    }
    if (mounted) {
      setState(() {
        _balance = b;
        _error = error;
        _loaded = true;
      });
    }
  }

  /// The customer's duplicatas in the full receivables list.
  void _openList() {
    final session = widget.session;
    final id = widget.customerId;
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Duplicatas do cliente')),
            body: ReceivablesScreen(session: session, customerId: id),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final b = _balance;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Section(
        title: 'Contas a receber',
        actions: [
          if (_error == null) TextButton.icon(key: const ValueKey('customer-open-receivables'), onPressed: _openList, icon: const Icon(Icons.list_alt_outlined), label: const Text('Ver duplicatas')),
        ],
        child: _error != null
            ? Row(
                children: [
                  Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(_error!)),
                  TextButton(
                    onPressed: () {
                      setState(() => _loaded = false);
                      unawaited(_load());
                    },
                    child: const Text('Tentar novamente'),
                  ),
                ],
              )
            : b == null
            ? const Text('Nada em aberto.')
            : InfoGrid([
                ('Em aberto', fmtMoney(b['open'])),
                ('Vencido', fmtMoney(b['overdue'])),
                ('Próximo vencimento', fmtDay(b['nextDue'])),
              ]),
      ),
    );
  }
}

class _CustomerAddresses extends StatefulWidget {
  const _CustomerAddresses({required this.session, required this.customerId});

  final Session session;
  final int customerId;

  @override
  State<_CustomerAddresses> createState() => _CustomerAddressesState();
}

class _CustomerAddressesState extends State<_CustomerAddresses> {
  late Future<dynamic> _future = _fetch();

  String get _path => '/api/customers/${widget.customerId}/addresses';

  Future<dynamic> _fetch() => widget.session.api.get(_path);

  void _reload() => setState(() {
    _future = _fetch();
  });

  Future<void> _edit([Map<String, dynamic>? current]) async {
    final s = widget.session;
    // Fiscal data (CNPJ/CPF, IE) belongs to the company; delivery locais inherit it from the default address.
    Map<String, dynamic>? base = current;
    if (base == null) {
      final c = await s.api.get('/api/customers/${widget.customerId}') as Map<String, dynamic>;
      final co = _company(c);
      base = fmt(co?['document']).isNotEmpty ? {'document': co!['document'], 'stateRegistration': co['stateRegistration'], 'icmsContributor': co['icmsContributor']} : _defaultAddress(c);
    }
    if (base == null) {
      if (mounted) showError(context, 'Cadastre os dados da empresa (aba Empresa) antes de criar locais de entrega.');
      return;
    }
    if (!mounted) return;
    final r = await showEntityForm(
      context,
      api: s.api,
      title: current == null ? 'Novo local de entrega' : 'Local de entrega',
      fields: _shippingFields,
      initial: current == null ? null : _normalizeUf(current, 'uf'),
      readOnly: !s.canCustomers,
      onSubmit: (b) async {
        _throwIfInvalid(_formatErrors(b, current));
        final body = {
          ...?base,
          'legacyCode': current?['legacyCode'],
          ...b,
        };
        return await (current == null ? s.api.post(_path, body) : s.api.put('$_path/${current['id']}', body)) as Map<String, dynamic>?;
      },
      onDelete: current == null ? null : () => s.api.delete('$_path/${current['id']}'),
    );
    if (r != null) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    floatingActionButton: widget.session.canCustomers
        ? FloatingActionButton.extended(heroTag: 'new-customer-address', onPressed: _edit, icon: const Icon(Icons.add), label: const Text('Novo local'))
        : null,
    body: FutureView<dynamic>(
      future: _future,
      onRetry: _reload,
      builder: (context, data) {
        final items = (data as List).cast<Map<String, dynamic>>();
        if (items.isEmpty) return const Center(child: Text('Nenhum local de entrega'));
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 80),
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final a = items[i];
            final contact = [a['buyer'], a['email'], a['phone']].where((x) => x != null && '$x'.isNotEmpty).join(' · ');
            return ListTile(
              leading: i == 0 ? const Tooltip(message: 'Local padrão', child: Icon(Icons.star_outline)) : const Icon(Icons.place_outlined),
              title: Text('${a['city'] == null ? 'Local ${a['id']}' : '${a['city']}/${a['uf']}'}${i == 0 ? '  (padrão)' : ''}'),
              subtitle: Text([_addressLine(a), contact].where((x) => x.isNotEmpty).join('\n')),
              isThreeLine: _addressLine(a).isNotEmpty && contact.isNotEmpty,
              onTap: () => _edit(a),
            );
          },
        );
      },
    ),
  );
}

class _CustomerQuotes extends StatefulWidget {
  const _CustomerQuotes({required this.session, required this.customerId, required this.customerName});

  final Session session;
  final int customerId;
  final String customerName;

  @override
  State<_CustomerQuotes> createState() => _CustomerQuotesState();
}

class _CustomerQuotesState extends State<_CustomerQuotes> {
  final _list = GlobalKey<RecordListState>();

  Session get session => widget.session;
  int get customerId => widget.customerId;

  @override
  Widget build(BuildContext context) => RecordList(
    key: _list,
    api: session.api,
    path: '/api/sales/quotes',
    query: {'customerId': customerId},
    searchHint: 'Orçamento ou referência do cliente',
    // A quote for this customer starts with the customer, the default prazo and the delivery address already chosen.
    fab: session.canSell
        ? FloatingActionButton.extended(
            heroTag: 'customer-new-quote',
            onPressed: () => newQuote(context, session, customer: (id: customerId, name: widget.customerName), onSaved: () => _list.currentState?.reload()),
            icon: const Icon(Icons.add),
            label: const Text('Novo orçamento'),
          )
        : null,
    columns: [
      col('Orçamento', 'reference'),
      ColumnSpec('Situação', (e) => quoteSituation(e, short: true)),
      moneyCol('Total', 'total'),
      dateCol('Validade', 'validUntil'),
      dateCol('Criada', 'createdAt'),
    ],
    onTap: (e) => openQuote(context, session, e['id'] as int),
  );
}

class _CustomerOrders extends StatelessWidget {
  const _CustomerOrders({required this.session, required this.customerId});

  final Session session;
  final int customerId;

  @override
  Widget build(BuildContext context) => RecordList(
    api: session.api,
    path: '/api/sales/orders',
    query: {'customerId': customerId},
    searchHint: 'Pedido ou pedido do cliente',
    columns: [
      col('Pedido', 'reference'),
      col('Pedido do cliente', 'customerPo'),
      labelCol('Situação', 'status', salesOrderStatuses),
      moneyCol('Total', 'total'),
      dateCol('Entrega', 'nextDue'),
    ],
    onTap: (e) => openSalesOrder(context, session, e['id'] as int),
  );
}
