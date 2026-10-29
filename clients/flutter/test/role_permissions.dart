const rolePermissions = <String, Set<String>>{
  'Admin': {'read', 'write', 'admin', 'stock', 'purchasing-request', 'purchasing', 'receiving', 'production', 'production-materials', 'sales', 'sales-approve', 'sales-release', 'sales-ship'},
  'Engineering': {'read', 'write', 'purchasing-request'},
  'Stock': {'read', 'stock', 'purchasing-request', 'receiving', 'production-materials', 'sales-ship'},
  'Purchasing': {'read', 'purchasing-request', 'purchasing', 'receiving'},
  'Production': {'read', 'production', 'production-materials', 'sales-release'},
  'Sales': {'read', 'sales', 'sales-release', 'sales-ship'},
  'SalesManager': {'read', 'sales', 'sales-approve', 'sales-release', 'sales-ship'},
  'Reader': {'read'},
};
