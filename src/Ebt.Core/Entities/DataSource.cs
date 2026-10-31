namespace Ebt.Core.Entities;

/// <summary>Where a record came from. Test records stay out of dashboards and reports unless asked for.</summary>
public enum DataSource { Manual = 0, Imported = 1, Test = 2 }

public interface IHasSource
{
    DataSource Source { get; set; }
}
