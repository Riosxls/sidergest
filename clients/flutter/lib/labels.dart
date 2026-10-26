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
