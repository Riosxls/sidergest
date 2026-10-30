const movementTypes = {
  'OpeningBalance': 'Saldo inicial',
  'Receipt': 'Entrada de compra',
  'ThirdPartyReturn': 'Retorno de terceiros',
  'ProductionReceipt': 'Entrada de produção',
  'CustomerReturn': 'Devolução de cliente',
  'AdjustmentIn': 'Ajuste de entrada',
  'Issue': 'Requisição (consumo)',
  'IndirectIssue': 'Consumo indireto',
  'Shipment': 'Expedição',
  'ReturnToSupplier': 'Devolução a fornecedor',
  'ThirdPartySend': 'Remessa a terceiros',
  'AdjustmentOut': 'Ajuste de saída',
  'Transfer': 'Transferência',
  'InventoryCount': 'Inventário',
  'Reversal': 'Estorno',
};

const postableTypes = [
  'Receipt',
  'Issue',
  'IndirectIssue',
  'Transfer',
  'ThirdPartySend',
  'ThirdPartyReturn',
  'ProductionReceipt',
  'Shipment',
  'CustomerReturn',
  'ReturnToSupplier',
  'AdjustmentIn',
  'AdjustmentOut',
  'InventoryCount',
  'OpeningBalance',
];

const userRoles = {
  'Admin': 'Administrador',
  'Engineering': 'Engenharia',
  'Reader': 'Leitura',
  'Stock': 'Estoque',
  'Purchasing': 'Compras',
  'Production': 'Produção',
  'Sales': 'Vendas',
  'SalesManager': 'Gerente de vendas',
};

const auditActions = {'Insert': 'Criado', 'Update': 'Alterado', 'Delete': 'Excluído'};

const auditEntities = [
  'Customer', 'CustomerAddress', 'Supplier', 'SupplierAddress', 'Material', 'Product', 'AppUser', 'StockLocation', 'StockSettings', 'StockClosing',
  'FiscalSettings', 'Cfop', 'TaxRule', 'MonthlyPrice', 'PaymentTerm', 'PriceListEntry', 'SalesSettings', 'ProductionSettings', 'SteelLot', 'SlitterJob',
];

const policyDescriptions = {
  'read': 'Consultar todos os cadastros e telas',
  'write': 'Alterar cadastros de engenharia',
  'admin': 'Administrar usuários, parâmetros e auditoria',
  'stock': 'Lançar movimentações, lotes e reservas de estoque',
  'purchasing-request': 'Criar requisições de compra',
  'purchasing': 'Aprovar requisições, cotar e emitir pedidos de compra',
  'receiving': 'Receber notas fiscais de compra',
  'production': 'Operar ordens de fabricação e apontamentos',
  'production-materials': 'Movimentar materiais da produção',
  'sales': 'Criar orçamentos e pedidos de venda',
  'sales-approve': 'Aprovar orçamentos e pedidos de venda',
  'sales-release': 'Liberar pedidos para produção',
  'sales-ship': 'Expedir entregas',
  'customers': 'Manter clientes',
  'certificates': 'Emitir certificados de qualidade',
  'fiscal-prices': 'Manter preços fiscais mensais',
  'fiscal-cancel': 'Cancelar notas fiscais',
  'steel': 'Controle de aço (bobinas e slitter)',
  'viability-quality': 'Assinar viabilidade (qualidade)',
  'viability-production': 'Assinar viabilidade (produção)',
  'viability-commercial': 'Assinar viabilidade (comercial)',
};

const lotStatuses ={'Released': 'Liberado', 'Quarantine': 'Quarentena', 'Rejected': 'Rejeitado'};
const reservationStatuses = {'Open': 'Aberta', 'Consumed': 'Consumida', 'Released': 'Liberada'};

const requisitionStatuses = {
  'PendingApproval': 'Aguardando aprovação',
  'Approved': 'Aprovada',
  'Rejected': 'Reprovada',
  'Quoting': 'Em cotação',
  'QuoteApproved': 'Cotação aprovada',
  'QuoteRejected': 'Cotação reprovada',
  'OrderIssued': 'Pedido emitido',
  'PartiallyReceived': 'Recebida parcial',
  'Received': 'Recebida',
  'Cancelled': 'Cancelada',
};

const quotationStatuses = {'Open': 'Aberta', 'Closed': 'Encerrada', 'Cancelled': 'Cancelada'};
const bidStatuses = {'Pending': 'Pendente', 'Approved': 'Vencedora', 'Rejected': 'Reprovada'};
const orderStatuses = {'Open': 'Aberto', 'PartiallyReceived': 'Recebido parcial', 'Received': 'Recebido', 'Closed': 'Encerrado', 'Cancelled': 'Cancelado'};

const productionStatuses = {
  'Created': 'Criada',
  'Released': 'Liberada',
  'Stopped': 'Parada',
  'InProduction': 'Em produção',
  'Cancelled': 'Cancelada',
  'Finished': 'Finalizada',
  'Closed': 'Encerrada',
};
const productionKinds = {'Standard': 'OF', 'Internal': 'OPI (interna)'};

const quoteStatuses = {
  'Draft': 'Rascunho',
  'PendingApproval': 'Aguardando aprovação',
  'Approved': 'Aprovada internamente',
  'Sent': 'Enviada ao cliente',
  'Accepted': 'Aceita pelo cliente',
  'PurchaseOrder': 'Pedido de compra recebido',
  'Rejected': 'Perdida',
  'Expired': 'Expirada',
  'Cancelled': 'Cancelada',
  'Converted': 'Convertida em pedido',
};
const salesOrderStatuses = {
  'Created': 'Criado',
  'Released': 'Liberado p/ produção',
  'PartiallyShipped': 'Expedido parcial',
  'Shipped': 'Expedido',
  'Delivered': 'Entregue',
  'Cancelled': 'Cancelado',
};
const deliveryStatuses = {'Planned': 'Programada', 'Shipped': 'Expedida', 'Delivered': 'Entregue', 'Cancelled': 'Cancelada'};
const certificateStatuses = {'Draft': 'Rascunho', 'Issued': 'Emitido', 'Cancelled': 'Cancelado'};
const freightTerms = {'Cif': 'CIF (frete nosso)', 'Fob': 'FOB (frete do cliente)', 'CustomerPickup': 'Retira na fábrica'};
const pipelineStages = {
  'quote': 'Orçamento',
  'sent': 'Enviada',
  'accepted': 'Aceita',
  'po': 'Pedido de compra',
  'order': 'Pedido',
  'production': 'Ordem de Produção',
  'certificate': 'Certificado',
  'ready': 'Pronto p/ expedir',
  'shipped': 'Expedido',
  'delivered': 'Entregue',
};
const salesActions = {
  'created': 'Criado',
  'edited': 'Editado',
  'submitted': 'Enviado para aprovação do gerente',
  'approved': 'Desconto aprovado',
  'approval-rejected': 'Desconto recusado',
  'sent': 'Enviado ao cliente',
  'po-received': 'Pedido de compra recebido',
  'accepted': 'Aceito pelo cliente',
  'declined': 'Venda perdida: cliente recusou',
  'gave-up': 'Venda perdida: cliente desistiu',
  'reopened': 'Voltou para rascunho',
  'validity-extended': 'Validade prorrogada',
  'revised': 'Nova revisão criada',
  'duplicated': 'Copiado de outro orçamento',
  'approval-lapsed': 'Aprovação de desconto vencida',
  'po-text': 'Texto do pedido de compra',
  'po-file': 'Pedido de compra anexado',
  'po-file-removed': 'Anexo do pedido de compra removido',
  'cancelled': 'Cancelado',
  'expired': 'Validade expirada',
  'converted': 'Convertido em pedido',
  'released': 'Liberado para produção',
  'credit-override': 'Limite de crédito liberado',
  'delivery-planned': 'Entrega programada',
  'status': 'Situação atualizada',
  'delivery': 'Entrega atualizada',
  'shipped': 'Expedido',
  'delivered': 'Entrega confirmada',
};
const salesBadges = {
  'discount': 'Desconto acima do limite',
  'expiring': 'Vence em breve',
  'followup': 'Cobrar resposta',
  'late': 'Atrasado',
  'ready': 'Pronto',
  'partial': 'Parcial',
};
const lostReasons = {
  'Price': 'Preço',
  'LeadTime': 'Prazo de entrega',
  'Competitor': 'Fechou com concorrente',
  'NoLongerNeeded': 'Não precisa mais',
  'Specification': 'Especificação / norma',
  'Other': 'Outro motivo',
  'CustomerGaveUp': 'Cliente desistiu do pedido',
};

const billToLabels = {'Ebt': 'EBT', 'Bts': 'BTS'};
const orderOrigins = {'Email': 'E-mail', 'Fax': 'Fax', 'Verbal': 'Verbal', 'System': 'Sistema'};
const deliveryConditions = {'Bk': 'BK', 'Nbk': 'NBK', 'Gbk': 'GBK'};
const saleUnits = {'KG': 'KG', 'PC': 'PÇ'};

const feasibilityStatuses = {'Draft': 'Rascunho', 'InReview': 'Em análise', 'Approved': 'Aprovada', 'Rejected': 'Reprovada'};
const signoffAreas = {'Quality': 'Qualidade', 'Production': 'Produção', 'Commercial': 'Comercial'};
const feasibilityActions = {
  'created': 'Criada',
  'edited': 'Editada',
  'submitted': 'Enviada para análise',
  'signed-quality': 'Qualidade assinou',
  'signed-production': 'Produção assinou',
  'signed-commercial': 'Comercial assinou',
  'rejected-quality': 'Qualidade reprovou',
  'rejected-production': 'Produção reprovou',
  'rejected-commercial': 'Comercial reprovou',
  'reopened': 'Reaberta',
};

/// What the customer asked for when a quote gets a new revision (written into the revision note).
const revisionReasons = {
  'Price': 'Cliente pediu: preço',
  'LeadTime': 'Cliente pediu: prazo de entrega',
  'Quantity': 'Cliente pediu: quantidade ou itens',
  'Specification': 'Cliente pediu: especificação / norma',
  'Other': 'Cliente pediu: outra alteração',
  'OurCorrection': 'Correção nossa (erro ou ajuste interno)',
};
