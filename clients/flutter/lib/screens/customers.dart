import 'package:flutter/material.dart';

import '../entities.dart';
import '../labels.dart';
import '../session.dart';
import '../widgets/entity_form.dart';
import '../widgets/record_list.dart';
import 'sales_common.dart';

const customerStatuses = {'true': 'Ativos', 'false': 'Inativos'};

/// CPF (11 digits) or CNPJ (14 digits) with punctuation; other values are returned as-is.
String fmtDocument(Object? v) {
  final d = '${v ?? ''}';
  if (RegExp(r'^\d{11}$').hasMatch(d)) return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9)}';
  if (RegExp(r'^\d{14}$').hasMatch(d)) return '${d.substring(0, 2)}.${d.substring(2, 5)}.${d.substring(5, 8)}/${d.substring(8, 12)}-${d.substring(12)}';
  return d;
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
  FieldSpec('uf', 'UF'),
  FieldSpec('zipCode', 'CEP'),
  FieldSpec('contact', 'Contato'),
  FieldSpec('email', 'E-mail'),
  FieldSpec('phone', 'Telefone'),
  FieldSpec('paymentTermId', 'Prazo padrão', type: FieldType.lookup, lookup: LookupSpec('/api/sales/payment-terms'), hint: 'Usado como padrão nos orçamentos'),
];

List<FieldSpec> _companyFormFields() => [
  for (final f in _companyFields) FieldSpec('company.${f.key}', f.label, type: f.type, hint: f.hint, lookup: f.lookup, defaultValue: f.defaultValue),
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
  FieldSpec('uf', 'UF', required: true),
  FieldSpec('zipCode', 'CEP'),
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
      ),
];

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
    if (r != null) _list.currentState?.reload();
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
    onTap: (e) => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerScreen(session: widget.session, customer: e),
      ),
    ),
  );
}

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
      initial: {..._c, if (company != null) for (final e in company.entries) 'company.${e.key}': e.value},
      readOnly: !s.canCustomers,
      onSubmit: (b) async {
        final (rest, co) = _splitCompany(b);
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
            _CustomerCompany(customer: _c, canEdit: s.canCustomers, onEdit: _edit),
            _CustomerAddresses(session: s, customerId: id),
            _CustomerQuotes(session: s, customerId: id),
            _CustomerOrders(session: s, customerId: id),
          ],
        ),
      ),
    );
  }
}

class _CustomerCompany extends StatelessWidget {
  const _CustomerCompany({required this.customer, required this.canEdit, required this.onEdit});

  final Map<String, dynamic> customer;
  final bool canEdit;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final a = _company(customer);
    final filled = a != null && a.entries.any((e) => e.key != 'icmsContributor' && e.value != null && '${e.value}'.isNotEmpty);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Section(
          title: 'Dados da empresa',
          actions: [if (canEdit) TextButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit_outlined), label: const Text('Editar'))],
          child: !filled
              ? const Text('Sem dados cadastrados. Use Editar para informar CNPJ/CPF, endereço e contato.')
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
      ],
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

  void _reload() => setState(() => _future = _fetch());

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
      initial: current,
      readOnly: !s.canCustomers,
      onSubmit: (b) async {
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
        ? FloatingActionButton.extended(heroTag: 'new-customer-address', onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Novo local'))
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

class _CustomerQuotes extends StatelessWidget {
  const _CustomerQuotes({required this.session, required this.customerId});

  final Session session;
  final int customerId;

  @override
  Widget build(BuildContext context) => RecordList(
    api: session.api,
    path: '/api/sales/quotes',
    query: {'customerId': customerId},
    searchHint: 'Orçamento ou referência do cliente',
    columns: [
      col('Orçamento', 'reference'),
      labelCol('Situação', 'status', quoteStatuses),
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
