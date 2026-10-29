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

const lotStatuses = {'Released': 'Liberado', 'Quarantine': 'Quarentena', 'Rejected': 'Rejeitado'};
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
  'Rejected': 'Recusada',
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
  'declined': 'Recusado pelo cliente',
  'revised': 'Revisado',
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
const salesBadges = {'discount': 'Desconto acima do limite', 'expiring': 'Vence em breve', 'late': 'Atrasado', 'ready': 'Pronto', 'partial': 'Parcial'};

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
