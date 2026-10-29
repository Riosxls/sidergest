import 'package:flutter/material.dart';

enum FieldType { text, integer, decimal, boolean, choice, lookup, date, time }

class LookupSpec {
  const LookupSpec(this.path, {this.fill = const {}, this.query = const {}, this.fetchById = true});

  final String path;
  final Map<String, String> fill;
  final Map<String, dynamic> query;
  final bool fetchById;

  static String display(Map<String, dynamic> e) {
    final code = e['code'] ?? e['lotCode'] ?? e['number'];
    final name = e['name'] ?? e['description'] ?? e['itemCode'] ?? e['title'] ?? e['reference'];
    final extra = e['remaining'] != null ? '${fmt(e['remaining'])} disp.' : (e['quantity'] != null && e['itemCode'] != null ? fmt(e['quantity']) : null);
    // Payment terms use the code only for ordering, so it is not shown.
    final shownCode = e['days'] != null ? null : code;
    return [shownCode, name, extra].whereType<Object>().join(' · ');
  }
}

class FieldSpec {
  const FieldSpec(
    this.key,
    this.label, {
    this.type = FieldType.text,
    this.required = false,
    this.choices = const {},
    this.lookup,
    this.hint,
    this.defaultValue,
    this.daysFor,
    this.dateFor,
    this.obscure = false,
  });

  final String key;
  final String label;
  final FieldType type;
  final bool required;
  final Map<String, String> choices;
  final LookupSpec? lookup;
  final String? hint;
  final Object? defaultValue;

  /// Integer field holding days from today; keeps the date field with this key in sync.
  final String? daysFor;

  /// Date field kept in sync with the days field with this key.
  final String? dateFor;

  /// Hides the typed text (passwords).
  final bool obscure;
}

class ColumnSpec {
  const ColumnSpec(this.label, this.value, {this.numeric = false});

  final String label;
  final String Function(Map<String, dynamic> e) value;
  final bool numeric;
}

class EntitySpec {
  const EntitySpec({
    required this.title,
    required this.singular,
    required this.path,
    required this.icon,
    required this.fields,
    required this.columns,
    this.whereUsed = false,
    this.searchable = true,
    this.writePolicy = 'write',
  });

  final String title;
  final String singular;
  final String path;
  final IconData icon;
  final List<FieldSpec> fields;
  final List<ColumnSpec> columns;
  final bool whereUsed;
  final bool searchable;
  final String writePolicy;
}

String fmt(Object? v) {
  if (v == null) return '';
  if (v is bool) return v ? 'Sim' : 'Não';
  if (v is num) {
    final s = v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '');
    return s.replaceAll('.', ',');
  }
  return '$v';
}

String _two(int n) => n.toString().padLeft(2, '0');

String fmtDate(Object? v) {
  if (v == null) return '';
  final s = '$v';
  final d = DateTime.tryParse(s);
  if (d == null) return s;
  if (s.length <= 10) return '${_two(d.day)}/${_two(d.month)}/${d.year}';
  final l = d.toLocal();
  return '${_two(l.day)}/${_two(l.month)}/${l.year} ${_two(l.hour)}:${_two(l.minute)}';
}

String fmtDay(Object? v) {
  final s = fmtDate(v);
  return s.length > 10 ? s.substring(0, 10) : s;
}

String isoDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

String? parseDate(String s) {
  final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2,4})$').firstMatch(s.trim());
  if (m != null) {
    var y = int.parse(m[3]!);
    if (y < 100) y += 2000;
    final d = DateTime(y, int.parse(m[2]!), int.parse(m[1]!));
    if (d.day != int.parse(m[1]!) || d.month != int.parse(m[2]!)) return null;
    return isoDate(d);
  }
  final d = DateTime.tryParse(s.trim());
  return d == null ? null : isoDate(d);
}

String fmtNum(Object? v, [int decimals = 2]) {
  if (v is! num) return fmt(v);
  final neg = v < 0;
  final parts = v.abs().toStringAsFixed(decimals).split('.');
  final digits = parts[0];
  final b = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write('.');
    b.write(digits[i]);
  }
  return '${neg ? '-' : ''}$b${parts.length > 1 ? ',${parts[1]}' : ''}';
}

String fmtMoney(Object? v) => v == null ? '' : 'R\$ ${fmtNum(v)}';

String fmtPeriod(Object? p) => p is int ? '${_two(p % 100)}/${p ~/ 100}' : fmt(p);

num? parseDecimal(String s) => num.tryParse(s.contains(',') ? s.replaceAll('.', '').replaceAll(',', '.') : s);

ColumnSpec col(String label, String key, {bool numeric = false}) => ColumnSpec(label, (e) => fmt(e[key]), numeric: numeric);
ColumnSpec dateCol(String label, String key) => ColumnSpec(label, (e) => fmtDay(e[key]));
ColumnSpec moneyCol(String label, String key) => ColumnSpec(label, (e) => fmtMoney(e[key]), numeric: true);
ColumnSpec labelCol(String label, String key, Map<String, String> labels) => ColumnSpec(label, (e) => labels[e[key]] ?? fmt(e[key]));

const kinds = {'Part': 'Peça', 'Component': 'Componente'};
const shapes = {'Circular': 'Circular', 'Rectangular': 'Retangular'};
const revisionKinds = {'Structure': 'Estrutura', 'Process': 'Processo', 'Drawing': 'Desenho'};

const codeName = [FieldSpec('code', 'Código', required: true), FieldSpec('name', 'Nome', required: true)];

final products = EntitySpec(
  title: 'Produtos',
  singular: 'Produto',
  path: '/api/products',
  icon: Icons.precision_manufacturing_outlined,
  fields: const [
    FieldSpec('code', 'Código', required: true),
    FieldSpec('name', 'Descrição', required: true),
    FieldSpec('kind', 'Tipo', type: FieldType.choice, choices: kinds, required: true, defaultValue: 'Part'),
    FieldSpec('shape', 'Formato do tubo', type: FieldType.choice, choices: shapes),
    FieldSpec('diameterMm', 'Diâmetro (mm)', type: FieldType.decimal),
    FieldSpec('widthMm', 'Largura (mm)', type: FieldType.decimal),
    FieldSpec('heightMm', 'Altura (mm)', type: FieldType.decimal),
    FieldSpec('thicknessMm', 'Parede (mm)', type: FieldType.decimal),
    FieldSpec('lengthMm', 'Comprimento (mm)', type: FieldType.decimal),
    FieldSpec('netWeightKg', 'Peso líquido (kg)', type: FieldType.decimal, hint: 'Vazio = calculado pelo formato'),
    FieldSpec('lossPercent', 'Perda (%)', type: FieldType.decimal),
    FieldSpec('ncm', 'NCM', required: true),
    FieldSpec('stockUnit', 'Unidade', required: true, defaultValue: 'PC'),
    FieldSpec('piecesPerPackage', 'Peças por embalagem', type: FieldType.integer),
    FieldSpec('blocked', 'Bloqueado', type: FieldType.boolean, defaultValue: false),
    FieldSpec('drawingRevision', 'Revisão desenho'),
    FieldSpec('processRevision', 'Revisão processo'),
  ],
  columns: [
    col('Código', 'code'),
    col('Descrição', 'name'),
    ColumnSpec('Tipo', (e) => kinds[e['kind']] ?? ''),
    col('NCM', 'ncm'),
    col('Peso (kg)', 'netWeightKg', numeric: true),
    col('Operações', 'operationCount', numeric: true),
    ColumnSpec('Bloqueado', (e) => e['blocked'] == true ? 'Sim' : ''),
  ],
  whereUsed: true,
);

final materials = EntitySpec(
  title: 'Materiais',
  singular: 'Material',
  path: '/api/materials',
  icon: Icons.inventory_2_outlined,
  fields: const [
    FieldSpec('code', 'Código', required: true),
    FieldSpec('description', 'Descrição', required: true),
    FieldSpec('classId', 'Classe', type: FieldType.lookup, lookup: LookupSpec('/api/material-classes')),
    FieldSpec('groupId', 'Grupo', type: FieldType.lookup, lookup: LookupSpec('/api/material-groups')),
    FieldSpec('subgroupId', 'Subgrupo', type: FieldType.lookup, lookup: LookupSpec('/api/material-subgroups')),
    FieldSpec('stockUnit', 'Unidade estoque', required: true, defaultValue: 'KG'),
    FieldSpec('purchaseUnit', 'Unidade compra', required: true, defaultValue: 'KG'),
    FieldSpec('purchaseFactor', 'Fator compra', type: FieldType.decimal, required: true, defaultValue: 1),
    FieldSpec('thicknessMm', 'Espessura (mm)', type: FieldType.decimal),
    FieldSpec('widthMm', 'Largura (mm)', type: FieldType.decimal),
    FieldSpec('ncm', 'NCM'),
    FieldSpec('leadTimeDays', 'Lead time (dias)', type: FieldType.integer),
    FieldSpec('purchaseLot', 'Lote compra', type: FieldType.decimal),
    FieldSpec('minStock', 'Estoque mínimo', type: FieldType.decimal),
    FieldSpec('maxStock', 'Estoque máximo', type: FieldType.decimal),
    FieldSpec('requiresInspection', 'Exige inspeção', type: FieldType.boolean, defaultValue: false),
    FieldSpec('generatesPurchaseOrder', 'Gera pedido de compra', type: FieldType.boolean, defaultValue: true),
    FieldSpec('externalProcessing', 'Beneficiamento externo', type: FieldType.boolean, defaultValue: false),
    FieldSpec('active', 'Ativo', type: FieldType.boolean, defaultValue: true),
  ],
  columns: [
    col('Código', 'code'),
    col('Descrição', 'description'),
    col('Subgrupo', 'subgroupName'),
    col('Un.', 'stockUnit'),
    col('Espessura', 'thicknessMm', numeric: true),
    col('NCM', 'ncm'),
    ColumnSpec('Ativo', (e) => e['active'] == true ? 'Sim' : 'Não'),
  ],
  whereUsed: true,
);

final materialClasses = EntitySpec(
  title: 'Classes de material',
  singular: 'Classe',
  path: '/api/material-classes',
  icon: Icons.category_outlined,
  fields: codeName,
  columns: [col('Código', 'code'), col('Nome', 'name')],
  searchable: false,
);

final materialGroups = EntitySpec(
  title: 'Grupos de material',
  singular: 'Grupo',
  path: '/api/material-groups',
  icon: Icons.folder_outlined,
  fields: codeName,
  columns: [col('Código', 'code'), col('Nome', 'name')],
  searchable: false,
);

final materialSubgroups = EntitySpec(
  title: 'Subgrupos de material',
  singular: 'Subgrupo',
  path: '/api/material-subgroups',
  icon: Icons.folder_open_outlined,
  fields: const [...codeName, FieldSpec('standard', 'Norma')],
  columns: [col('Código', 'code'), col('Nome', 'name'), col('Norma', 'standard')],
  searchable: false,
);

final workCenters = EntitySpec(
  title: 'Centros de trabalho',
  singular: 'Centro de trabalho',
  path: '/api/work-centers',
  icon: Icons.factory_outlined,
  fields: const [...codeName, FieldSpec('costCenter', 'Centro de custo')],
  columns: [col('Código', 'code'), col('Nome', 'name'), col('Centro de custo', 'costCenter')],
  searchable: false,
);

final machines = EntitySpec(
  title: 'Máquinas',
  singular: 'Máquina',
  path: '/api/machines',
  icon: Icons.settings_outlined,
  fields: const [
    ...codeName,
    FieldSpec('workCenterId', 'Centro de trabalho', type: FieldType.lookup, lookup: LookupSpec('/api/work-centers')),
    FieldSpec('family', 'Família'),
  ],
  columns: [col('Código', 'code'), col('Nome', 'name'), col('Centro de trabalho', 'workCenterName'), col('Família', 'family')],
);

final tools = EntitySpec(
  title: 'Ferramentas',
  singular: 'Ferramenta',
  path: '/api/tools',
  icon: Icons.handyman_outlined,
  fields: const [
    ...codeName,
    FieldSpec('warningLimit', 'Limite de aviso', type: FieldType.integer),
    FieldSpec('inspectionLimit', 'Limite de inspeção', type: FieldType.integer),
  ],
  columns: [col('Código', 'code'), col('Nome', 'name'), col('Aviso', 'warningLimit', numeric: true), col('Inspeção', 'inspectionLimit', numeric: true)],
  searchable: false,
);

final standardOperations = EntitySpec(
  title: 'Operações padrão',
  singular: 'Operação',
  path: '/api/standard-operations',
  icon: Icons.linear_scale,
  fields: codeName,
  columns: [col('Código', 'code'), col('Nome', 'name')],
  searchable: false,
);

const routingFields = [
  FieldSpec('sequence', 'Sequência', type: FieldType.integer, required: true, hint: 'Múltiplo de 10'),
  FieldSpec('standardOperationId', 'Operação padrão', type: FieldType.lookup, lookup: LookupSpec('/api/standard-operations')),
  FieldSpec(
    'machineId',
    'Máquina',
    type: FieldType.lookup,
    lookup: LookupSpec('/api/machines', fill: {'workCenterId': 'workCenterId'}),
  ),
  FieldSpec('workCenterId', 'Centro de trabalho', type: FieldType.lookup, lookup: LookupSpec('/api/work-centers')),
  FieldSpec('toolId', 'Ferramenta', type: FieldType.lookup, lookup: LookupSpec('/api/tools')),
  FieldSpec('setupHours', 'Setup (h)', type: FieldType.decimal),
  FieldSpec('piecesPerHour', 'Peças/hora', type: FieldType.decimal),
  FieldSpec('operators', 'Operadores', type: FieldType.decimal),
  FieldSpec('description', 'Descrição'),
  FieldSpec('standard', 'Norma'),
  FieldSpec('notes', 'Observações'),
];

const bomItemFields = [
  FieldSpec(
    'materialId',
    'Material',
    type: FieldType.lookup,
    lookup: LookupSpec('/api/materials', fill: {'unit': 'stockUnit'}),
    hint: 'Material ou componente, não ambos',
  ),
  FieldSpec(
    'componentProductId',
    'Componente (produto)',
    type: FieldType.lookup,
    lookup: LookupSpec('/api/products', fill: {'unit': 'stockUnit'}),
  ),
  FieldSpec('quantity', 'Quantidade', type: FieldType.decimal, required: true),
  FieldSpec('unit', 'Unidade', required: true),
  FieldSpec('factor', 'Fator', type: FieldType.decimal, required: true, defaultValue: 1),
];

const revisionFields = [
  FieldSpec('kind', 'Tipo', type: FieldType.choice, choices: revisionKinds, required: true, defaultValue: 'Process'),
  FieldSpec('code', 'Revisão', required: true),
  FieldSpec('reason', 'Motivo'),
];

const locationKinds = {'Internal': 'Interno', 'Quarantine': 'Quarentena', 'ThirdParty': 'Terceiros', 'Shipping': 'Expedição'};

final stockLocations = EntitySpec(
  title: 'Locais de estoque',
  singular: 'Local',
  path: '/api/stock-locations',
  icon: Icons.place_outlined,
  fields: const [
    ...codeName,
    FieldSpec('kind', 'Tipo', type: FieldType.choice, choices: locationKinds, required: true, defaultValue: 'Internal'),
    FieldSpec('active', 'Ativo', type: FieldType.boolean, defaultValue: true),
  ],
  columns: [
    col('Código', 'code'),
    col('Nome', 'name'),
    labelCol('Tipo', 'kind', locationKinds),
    ColumnSpec('Ativo', (e) => e['active'] == true ? 'Sim' : 'Não'),
  ],
  writePolicy: 'stock',
);

final suppliers = EntitySpec(
  title: 'Fornecedores',
  singular: 'Fornecedor',
  path: '/api/suppliers',
  icon: Icons.local_shipping_outlined,
  fields: const [
    FieldSpec('name', 'Razão social', required: true),
    FieldSpec('tradeName', 'Nome fantasia'),
    FieldSpec('legacyCode', 'Código antigo'),
    FieldSpec('groupCode', 'Grupo'),
    FieldSpec('active', 'Ativo', type: FieldType.boolean, defaultValue: true),
  ],
  columns: [
    col('Razão social', 'name'),
    col('Fantasia', 'tradeName'),
    col('Código antigo', 'legacyCode'),
    col('Grupo', 'groupCode'),
    ColumnSpec('Ativo', (e) => e['active'] == true ? 'Sim' : 'Não'),
  ],
);

final masterData = [products, materials, machines, standardOperations, workCenters, tools, materialClasses, materialGroups, materialSubgroups];

const occurrenceKindLabels = {'Downtime': 'Parada', 'Scrap': 'Refugo'};


final shifts = EntitySpec(
  title: 'Turnos',
  singular: 'Turno',
  path: '/api/production/shifts',
  icon: Icons.schedule_outlined,
  fields: const [
    ...codeName,
    FieldSpec('startsAt', 'Início', type: FieldType.time),
    FieldSpec('endsAt', 'Fim', type: FieldType.time),
    FieldSpec('hours', 'Horas', type: FieldType.decimal),
  ],
  columns: [
    col('Código', 'code'),
    col('Nome', 'name'),
    ColumnSpec('Início', (e) => fmtTime(e['startsAt'])),
    ColumnSpec('Fim', (e) => fmtTime(e['endsAt'])),
    col('Horas', 'hours', numeric: true),
  ],
  searchable: false,
  writePolicy: 'production',
);

final employees = EntitySpec(
  title: 'Funcionários',
  singular: 'Funcionário',
  path: '/api/production/employees',
  icon: Icons.badge_outlined,
  fields: const [
    FieldSpec('code', 'Matrícula', required: true),
    FieldSpec('name', 'Nome', required: true),
    FieldSpec('nickname', 'Apelido'),
    FieldSpec('function', 'Função'),
    FieldSpec('workCenterId', 'Centro de trabalho', type: FieldType.lookup, lookup: LookupSpec('/api/work-centers')),
    FieldSpec('shiftId', 'Turno', type: FieldType.lookup, lookup: LookupSpec('/api/production/shifts')),
    FieldSpec('active', 'Ativo', type: FieldType.boolean, defaultValue: true),
  ],
  columns: [
    col('Matrícula', 'code'),
    col('Nome', 'name'),
    col('Apelido', 'nickname'),
    col('Função', 'function'),
    ColumnSpec('Ativo', (e) => e['active'] == true ? 'Sim' : 'Não'),
  ],
  writePolicy: 'production',
);

final occurrences = EntitySpec(
  title: 'Ocorrências',
  singular: 'Ocorrência',
  path: '/api/production/occurrences',
  icon: Icons.report_problem_outlined,
  fields: const [
    FieldSpec('code', 'Código', required: true),
    FieldSpec('description', 'Descrição', required: true),
    FieldSpec('kind', 'Tipo', type: FieldType.choice, choices: occurrenceKindLabels, required: true, defaultValue: 'Downtime'),
    FieldSpec('stopsOrder', 'Para a OF', type: FieldType.boolean, defaultValue: false),
  ],
  columns: [
    col('Código', 'code'),
    col('Descrição', 'description'),
    labelCol('Tipo', 'kind', occurrenceKindLabels),
    ColumnSpec('Para a OF', (e) => e['stopsOrder'] == true ? 'Sim' : ''),
  ],
  searchable: false,
  writePolicy: 'production',
);

final holidays = EntitySpec(
  title: 'Feriados',
  singular: 'Feriado',
  path: '/api/production/holidays',
  icon: Icons.event_busy_outlined,
  fields: const [
    FieldSpec('date', 'Data', type: FieldType.date, required: true),
    FieldSpec('name', 'Descrição', required: true),
  ],
  columns: [dateCol('Data', 'date'), col('Descrição', 'name')],
  searchable: false,
  writePolicy: 'production',
);

final productionMasters = [employees, shifts, occurrences, holidays];

final paymentTerms = EntitySpec(
  title: 'Prazos',
  singular: 'Prazo',
  path: '/api/sales/payment-terms',
  icon: Icons.payments_outlined,
  fields: const [
    FieldSpec('code', 'Código', required: true),
    FieldSpec('name', 'Descrição', required: true),
    FieldSpec('days', 'Dias (DDL)', required: true, hint: 'ex.: 28/35/42 ou 0 para à vista'),
    FieldSpec('creditLimit', 'Limite de crédito (R\$)', type: FieldType.decimal, hint: 'Vazio = sem limite'),
    FieldSpec('active', 'Ativa', type: FieldType.boolean, defaultValue: true),
  ],
  columns: [
    col('Código', 'code'),
    col('Descrição', 'name'),
    col('Dias', 'days'),
    moneyCol('Limite de crédito', 'creditLimit'),
    ColumnSpec('Ativa', (e) => e['active'] == true ? 'Sim' : 'Não'),
  ],
  writePolicy: 'sales-approve',
);

final priceList = EntitySpec(
  title: 'Tabela de preços',
  singular: 'Preço',
  path: '/api/sales/price-list',
  icon: Icons.sell_outlined,
  fields: const [
    FieldSpec('productId', 'Produto', type: FieldType.lookup, required: true, lookup: LookupSpec('/api/products')),
    FieldSpec('customerId', 'Cliente', type: FieldType.lookup, lookup: LookupSpec('/api/customers'), hint: 'Vazio = preço geral'),
    FieldSpec('unitPrice', 'Preço unitário (R\$)', type: FieldType.decimal, required: true),
    FieldSpec('ipiPercent', 'IPI (%)', type: FieldType.decimal),
    FieldSpec('icmsPercent', 'ICMS (%)', type: FieldType.decimal),
    FieldSpec('validFrom', 'Válido de', type: FieldType.date, required: true),
    FieldSpec('validTo', 'Válido até', type: FieldType.date),
  ],
  columns: [
    col('Produto', 'productCode'),
    col('Descrição', 'productName'),
    ColumnSpec('Cliente', (e) => '${e['customerName'] ?? 'Geral'}'),
    ColumnSpec('Preço', (e) => fmtNum(e['unitPrice'], 4), numeric: true),
    col('IPI %', 'ipiPercent', numeric: true),
    dateCol('De', 'validFrom'),
    dateCol('Até', 'validTo'),
  ],
  writePolicy: 'sales',
);

final salesMasters = [priceList, paymentTerms, monthlyPrices, taxRules];

String fmtTime(Object? v) {
  final s = v == null ? '' : '$v';
  return s.length >= 5 ? s.substring(0, 5) : s;
}

String? parseTime(Object? v) {
  final m = RegExp(r'^(\d{1,2})[:h.]?(\d{2})?$').firstMatch('${v ?? ''}'.trim());
  if (m == null) return null;
  final h = int.parse(m[1]!);
  final min = int.parse(m[2] ?? '0');
  if (h > 23 || min > 59) return null;
  return '${_two(h)}:${_two(min)}:00';
}

final monthlyPrices = EntitySpec(
  title: 'Preços mensais da NF',
  singular: 'Preço mensal',
  path: '/api/fiscal/monthly-prices',
  icon: Icons.event_note_outlined,
  fields: const [
    FieldSpec('productId', 'Produto', type: FieldType.lookup, required: true, lookup: LookupSpec('/api/products')),
    FieldSpec('customerId', 'Cliente', type: FieldType.lookup, required: true, lookup: LookupSpec('/api/customers')),
    FieldSpec('cfopCode', 'CFOP', required: true, defaultValue: '5101'),
    FieldSpec('year', 'Ano', type: FieldType.integer, required: true),
    FieldSpec('month', 'Mês', type: FieldType.integer, required: true),
    FieldSpec('unitPrice', 'Preço unitário (R\$)', type: FieldType.decimal, required: true, hint: 'Sem preço no mês, a NF de venda é bloqueada'),
  ],
  columns: [
    col('Produto', 'productCode'),
    col('Descrição', 'productName'),
    col('Cliente', 'customerName'),
    col('CFOP', 'cfopCode'),
    ColumnSpec('Mês', (e) => '${e['month'].toString().padLeft(2, '0')}/${e['year']}'),
    ColumnSpec('Preço', (e) => fmtNum(e['unitPrice'], 4), numeric: true),
  ],
  writePolicy: 'fiscal-prices',
);

final taxRules = EntitySpec(
  title: 'Regras de imposto',
  singular: 'Regra',
  path: '/api/fiscal/tax-rules',
  icon: Icons.percent,
  fields: const [
    FieldSpec('productId', 'Produto', type: FieldType.lookup, required: true, lookup: LookupSpec('/api/products')),
    FieldSpec('customerId', 'Cliente', type: FieldType.lookup, lookup: LookupSpec('/api/customers'), hint: 'Vazio = todos os clientes'),
    FieldSpec('cfopCode', 'CFOP', required: true, defaultValue: '5101'),
    FieldSpec('icmsCst', 'CST do ICMS', hint: 'Vazio = padrão do CFOP'),
    FieldSpec('icmsPercent', 'ICMS (%)', type: FieldType.decimal, required: true, defaultValue: 0),
    FieldSpec('icmsBaseReductionPercent', 'Redução da base do ICMS (%)', type: FieldType.decimal, required: true, defaultValue: 0),
    FieldSpec('ipiCst', 'CST do IPI', hint: 'Vazio = padrão do CFOP'),
    FieldSpec('ipiPercent', 'IPI (%)', type: FieldType.decimal, required: true, defaultValue: 0),
    FieldSpec('pisPercent', 'PIS (%)', type: FieldType.decimal, hint: 'Vazio = padrão do CFOP'),
    FieldSpec('cofinsPercent', 'COFINS (%)', type: FieldType.decimal, hint: 'Vazio = padrão do CFOP'),
  ],
  columns: [
    col('Produto', 'productCode'),
    ColumnSpec('Cliente', (e) => '${e['customerName'] ?? 'Todos'}'),
    col('CFOP', 'cfopCode'),
    col('ICMS %', 'icmsPercent', numeric: true),
    col('IPI %', 'ipiPercent', numeric: true),
    col('PIS %', 'pisPercent', numeric: true),
    col('COFINS %', 'cofinsPercent', numeric: true),
  ],
  writePolicy: 'fiscal-prices',
);
