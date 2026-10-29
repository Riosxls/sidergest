const _all = {
  'read', 'write', 'admin', 'stock', 'purchasing-request', 'purchasing', 'receiving', 'production', 'production-materials',
  'certificates', 'fiscal-prices', 'fiscal-cancel', 'steel', 'viability-quality', 'viability-production', 'viability-commercial',
  'customers', 'sales', 'sales-approve', 'sales-release', 'sales-ship',
};

/// Mirrors the server's Access matrix (src/Ebt.Api/Infrastructure/Access.cs).
const rolePermissions = <String, Set<String>>{
  'Admin': _all,
  'Engineering': {'read', 'write', 'purchasing-request', 'certificates', 'viability-quality', 'customers'},
  'Stock': {'read', 'stock', 'purchasing-request', 'receiving', 'production-materials', 'steel', 'sales-ship'},
  'Purchasing': {'read', 'purchasing-request', 'purchasing', 'receiving', 'steel'},
  'Production': {'read', 'production', 'production-materials', 'certificates', 'viability-production', 'sales-release'},
  'Sales': {'read', 'certificates', 'viability-commercial', 'customers', 'sales', 'sales-release', 'sales-ship'},
  'SalesManager': {'read', 'certificates', 'fiscal-prices', 'fiscal-cancel', 'viability-commercial', 'customers', 'sales', 'sales-approve', 'sales-release', 'sales-ship'},
  'Reader': {'read'},
};
