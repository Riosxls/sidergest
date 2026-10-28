namespace Ebt.Core.Entities;

public enum ConsumerType { Normal = 0, FinalConsumer = 1 }
public enum ProductKind { Part = 0, Component = 1 }
public enum TubeShape { Circular = 0, Rectangular = 1 }
public enum RevisionKind { Structure = 0, Process = 1, Drawing = 2 }
public enum UserRole { Admin = 0, Engineering = 1, Reader = 2, Stock = 3, Purchasing = 4, Production = 5, Sales = 6, SalesManager = 7 }

public class Customer
{
    public int Id { get; set; }
    public string? LegacyCode { get; set; }
    public required string Name { get; set; }
    public string? TradeName { get; set; }
    public ConsumerType ConsumerType { get; set; }
    public bool Active { get; set; } = true;
    // Company (fiscal/contact) data; independent from the delivery addresses.
    public string? Document { get; set; }
    public string? StateRegistration { get; set; }
    public bool IcmsContributor { get; set; }
    public string? Street { get; set; }
    public string? Number { get; set; }
    public string? Complement { get; set; }
    public string? District { get; set; }
    public string? City { get; set; }
    public string? Uf { get; set; }
    public string? ZipCode { get; set; }
    public string? Contact { get; set; }
    public string? Email { get; set; }
    public string? Phone { get; set; }
    public int? DefaultPaymentTermId { get; set; }
    public PaymentTerm? DefaultPaymentTerm { get; set; }
    public List<CustomerAddress> Addresses { get; set; } = new();
}

public class CustomerAddress
{
    public int Id { get; set; }
    public int CustomerId { get; set; }
    public Customer? Customer { get; set; }
    public string? LegacyCode { get; set; }
    public required string Document { get; set; }
    public string? StateRegistration { get; set; }
    public bool IcmsContributor { get; set; }
    public string? Street { get; set; }
    public string? Number { get; set; }
    public string? Complement { get; set; }
    public string? District { get; set; }
    public string? City { get; set; }
    public string? CityIbgeCode { get; set; }
    public required string Uf { get; set; }
    public string? ZipCode { get; set; }
    public string? DefaultCfop { get; set; }
    public string? Buyer { get; set; }
    public string? Email { get; set; }
    public string? Phone { get; set; }
}

public class Supplier
{
    public int Id { get; set; }
    public string? LegacyCode { get; set; }
    public required string Name { get; set; }
    public string? TradeName { get; set; }
    public string? GroupCode { get; set; }
    public bool Active { get; set; } = true;
    public List<SupplierAddress> Addresses { get; set; } = new();
}

public class SupplierAddress
{
    public int Id { get; set; }
    public int SupplierId { get; set; }
    public Supplier? Supplier { get; set; }
    public string? LegacyCode { get; set; }
    public string? Document { get; set; }
    public string? StateRegistration { get; set; }
    public string? Street { get; set; }
    public string? Number { get; set; }
    public string? District { get; set; }
    public string? City { get; set; }
    public string? CityIbgeCode { get; set; }
    public required string Uf { get; set; }
    public string? ZipCode { get; set; }
    public string? Email { get; set; }
    public string? Phone { get; set; }
}

public class MaterialClass
{
    public int Id { get; set; }
    public required string Code { get; set; }
    public required string Name { get; set; }
}

public class MaterialGroup
{
    public int Id { get; set; }
    public required string Code { get; set; }
    public required string Name { get; set; }
}

public class MaterialSubgroup
{
    public int Id { get; set; }
    public required string Code { get; set; }
    public required string Name { get; set; }
    public string? Standard { get; set; }
}

public class Material
{
    public int Id { get; set; }
    public required string Code { get; set; }
    public required string Description { get; set; }
    public int? ClassId { get; set; }
    public MaterialClass? Class { get; set; }
    public int? GroupId { get; set; }
    public MaterialGroup? Group { get; set; }
    public int? SubgroupId { get; set; }
    public MaterialSubgroup? Subgroup { get; set; }
    public required string StockUnit { get; set; }
    public required string PurchaseUnit { get; set; }
    public decimal PurchaseFactor { get; set; } = 1m;
    public decimal? ThicknessMm { get; set; }
    public decimal? WidthMm { get; set; }
    public string? Ncm { get; set; }
    public int? LeadTimeDays { get; set; }
    public decimal? PurchaseLot { get; set; }
    public decimal? MinStock { get; set; }
    public decimal? MaxStock { get; set; }
    public bool RequiresInspection { get; set; }
    public bool GeneratesPurchaseOrder { get; set; } = true;
    public bool ExternalProcessing { get; set; }
    public bool Active { get; set; } = true;
}

public class WorkCenter
{
    public int Id { get; set; }
    public required string Code { get; set; }
    public required string Name { get; set; }
    public string? CostCenter { get; set; }
}

public class Machine
{
    public int Id { get; set; }
    public required string Code { get; set; }
    public required string Name { get; set; }
    public int? WorkCenterId { get; set; }
    public WorkCenter? WorkCenter { get; set; }
    public string? Family { get; set; }
}

public class Tool
{
    public int Id { get; set; }
    public required string Code { get; set; }
    public required string Name { get; set; }
    public int? WarningLimit { get; set; }
    public int? InspectionLimit { get; set; }
}

public class StandardOperation
{
    public int Id { get; set; }
    public required string Code { get; set; }
    public required string Name { get; set; }
}

public class Product
{
    public int Id { get; set; }
    public required string Code { get; set; }
    public required string Name { get; set; }
    public ProductKind Kind { get; set; }
    public TubeShape? Shape { get; set; }
    public decimal? DiameterMm { get; set; }
    public decimal? WidthMm { get; set; }
    public decimal? HeightMm { get; set; }
    public decimal? ThicknessMm { get; set; }
    public decimal? LengthMm { get; set; }
    public decimal? NetWeightKg { get; set; }
    public decimal? LossPercent { get; set; }
    public required string Ncm { get; set; }
    public required string StockUnit { get; set; }
    public int? PiecesPerPackage { get; set; }
    public bool Blocked { get; set; }
    public string? DrawingRevision { get; set; }
    public string? ProcessRevision { get; set; }
    public List<RoutingOperation> Routing { get; set; } = new();
    public List<ProductCustomer> Customers { get; set; } = new();
}

public class ProductCustomer
{
    public int ProductId { get; set; }
    public Product? Product { get; set; }
    public int CustomerId { get; set; }
    public Customer? Customer { get; set; }
    public string? CustomerPartNumber { get; set; }
    public string? CustomerDescription { get; set; }
    public bool Active { get; set; } = true;
}

public class RoutingOperation
{
    public int Id { get; set; }
    public int ProductId { get; set; }
    public Product? Product { get; set; }
    public int Sequence { get; set; }
    public int? StandardOperationId { get; set; }
    public StandardOperation? StandardOperation { get; set; }
    public int? MachineId { get; set; }
    public Machine? Machine { get; set; }
    public int? WorkCenterId { get; set; }
    public WorkCenter? WorkCenter { get; set; }
    public int? ToolId { get; set; }
    public Tool? Tool { get; set; }
    public decimal? SetupHours { get; set; }
    public decimal? PiecesPerHour { get; set; }
    public decimal? Operators { get; set; }
    public string? Description { get; set; }
    public string? Standard { get; set; }
    public string? Notes { get; set; }
    public List<BomItem> Items { get; set; } = new();
}

public class BomItem
{
    public int Id { get; set; }
    public int RoutingOperationId { get; set; }
    public RoutingOperation? RoutingOperation { get; set; }
    public int? MaterialId { get; set; }
    public Material? Material { get; set; }
    public int? ComponentProductId { get; set; }
    public Product? ComponentProduct { get; set; }
    public decimal Quantity { get; set; }
    public required string Unit { get; set; }
    public decimal Factor { get; set; } = 1m;
}

public class Revision
{
    public int Id { get; set; }
    public int ProductId { get; set; }
    public Product? Product { get; set; }
    public RevisionKind Kind { get; set; }
    public required string Code { get; set; }
    public string? Reason { get; set; }
    public string? User { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
}

public class AppUser
{
    public int Id { get; set; }
    public required string Username { get; set; }
    public required string PasswordHash { get; set; }
    public UserRole Role { get; set; }
    public bool Active { get; set; } = true;
}
