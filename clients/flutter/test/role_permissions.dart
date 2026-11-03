const _all = {
  'read', 'write', 'admin', 'stock', 'purchasing-request', 'purchasing', 'receiving', 'production', 'production-materials',
  'certificates', 'certificates-issue', 'fiscal-prices', 'fiscal-cancel', 'fiscal-emit', 'receivables-post', 'price-edit', 'steel', 'viability-quality', 'viability-production', 'viability-commercial',
  'customers', 'sales', 'sales-approve', 'sales-release', 'sales-ship',
};

/// Mirrors the server's Access matrix (src/Ebt.Api/Infrastructure/Access.cs).
const rolePermissions = <String, Set<String>>{
  'Admin': _all,
  'Engineering': {'read', 'write', 'purchasing-request', 'certificates', 'certificates-issue', 'viability-quality', 'customers'},
  'Stock': {'read', 'stock', 'purchasing-request', 'receiving', 'production-materials', 'steel', 'sales-ship'},
  'Purchasing': {'read', 'purchasing-request', 'purchasing', 'receiving', 'steel'},
  'Production': {'read', 'production', 'production-materials', 'certificates', 'certificates-issue', 'viability-production', 'sales-release'},
  'Sales': {'read', 'certificates', 'fiscal-emit', 'receivables-post', 'viability-commercial', 'customers', 'sales', 'sales-release', 'sales-ship'},
  'SalesManager': {'read', 'certificates', 'certificates-issue', 'fiscal-prices', 'fiscal-cancel', 'fiscal-emit', 'receivables-post', 'price-edit', 'viability-commercial', 'customers', 'sales', 'sales-approve', 'sales-release', 'sales-ship'},
  'Reader': {'read'},
};
