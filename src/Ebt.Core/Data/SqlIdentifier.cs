using System.Text.RegularExpressions;

namespace Ebt.Core.Data;

/// <summary>Identifiers (sequence/table names) cannot be SQL parameters; they must come from code constants and pass this check.</summary>
public static partial class SqlIdentifier
{
    public static string Safe(string name) =>
        Pattern().IsMatch(name) ? name : throw new ArgumentException($"Unsafe SQL identifier: {name}", nameof(name));

    [GeneratedRegex("^[a-z_][a-z0-9_]{0,62}$")]
    private static partial Regex Pattern();
}
