using System.Text.RegularExpressions;
using Ebt.Api.Infrastructure;
using Ebt.Core.Entities;

namespace Ebt.Tests;

/// <summary>The Flutter test matrix and the labels screen mirror <see cref="Access"/>; this fails when they drift.</summary>
public class AccessParityTests
{
    private static string RepoFile(params string[] parts)
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir != null && !File.Exists(Path.Combine(dir.FullName, "Ebt.sln"))) dir = dir.Parent;
        Assert.NotNull(dir);
        return Path.Combine([dir.FullName, .. parts]);
    }

    private static HashSet<string> Quoted(string text) =>
        Regex.Matches(text, "'([a-z-]+)'").Select(m => m.Groups[1].Value).ToHashSet();

    [Fact]
    public void Flutter_role_matrix_matches_the_server()
    {
        var dart = File.ReadAllText(RepoFile("clients", "flutter", "test", "role_permissions.dart"));
        var all = Quoted(Regex.Match(dart, @"const _all = \{(.*?)\};", RegexOptions.Singleline).Groups[1].Value);
        var roles = Regex.Matches(dart, @"'(?<role>[A-Za-z]+)': (?:(?<all>_all)|\{(?<set>[^}]*)\})");
        Assert.NotEmpty(roles);

        foreach (Match m in roles)
        {
            var role = Enum.Parse<UserRole>(m.Groups["role"].Value);
            var mirrored = m.Groups["all"].Success ? all : Quoted(m.Groups["set"].Value);
            Assert.True(Access.PoliciesFor(role).ToHashSet().SetEquals(mirrored),
                $"role_permissions.dart is out of sync for {role}: server={string.Join(",", Access.PoliciesFor(role).Order())} dart={string.Join(",", mirrored.Order())}");
        }
        Assert.Equal(Enum.GetValues<UserRole>().Length, roles.Count);
    }

    [Fact]
    public void Every_policy_has_a_description_on_the_permissions_screen()
    {
        var labels = File.ReadAllText(RepoFile("clients", "flutter", "lib", "labels.dart"));
        var block = Regex.Match(labels, @"policyDescriptions\s*=\s*(?:<[^>]*>)?\{(.*?)\n\};", RegexOptions.Singleline).Groups[1].Value;
        var described = Regex.Matches(block, @"'([a-z-]+)'\s*:").Select(m => m.Groups[1].Value).ToHashSet();
        var missing = Access.Matrix.Keys.Append(Policies.Read).Where(p => !described.Contains(p)).ToList();
        Assert.True(missing.Count == 0, "policyDescriptions in labels.dart lacks: " + string.Join(", ", missing));
    }
}
