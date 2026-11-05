using Ebt.Core.Entities;

namespace Ebt.Core.Services;

public static class TubeWeight
{
    public const decimal SteelDensityKgPerMm3 = 0.00000785m;

    /// <summary>Loss (perda) added to the net weight when the product has none: the "Peso Bruto" of the legacy spreadsheet.</summary>
    public const decimal DefaultLossPercent = 2.8m;

    /// <summary>Oblong (flat-oval, "stadium") tube: <paramref name="widthMm"/> is the long outside side, <paramref name="heightMm"/> the short one; the ends are half circles.
    /// Wall area = outer stadium minus inner stadium (both sides smaller by twice the wall). Null when the numbers do not make a tube.</summary>
    public static decimal? OblongNetWeightKg(decimal? widthMm, decimal? heightMm, decimal? thicknessMm, decimal? lengthMm)
    {
        if (widthMm is not > 0 || heightMm is not > 0 || thicknessMm is not > 0 || lengthMm is not > 0) return null;
        var w = widthMm.Value; var h = heightMm.Value; var t = thicknessMm.Value;
        if (w < h || t * 2 >= h) return null;
        static decimal Stadium(decimal width, decimal height) => (width - height) * height + (decimal)Math.PI * height * height / 4m;
        var area = Stadium(w, h) - Stadium(w - 2 * t, h - 2 * t);
        return Math.Round(area * lengthMm.Value * SteelDensityKgPerMm3, 5);
    }

    /// <summary>Diameter of the round tube whose outside perimeter equals that of the oblong one: the round tube a price history of round tubes can be compared with.</summary>
    public static decimal OblongEquivalentDiameterMm(decimal widthMm, decimal heightMm) => Math.Round((2 * (widthMm - heightMm) + (decimal)Math.PI * heightMm) / (decimal)Math.PI, 3);

    /// <summary>Diameter of the round tube whose outside perimeter equals that of the rectangular (or square) one: 2 x (width + height) / pi.</summary>
    public static decimal RectEquivalentDiameterMm(decimal widthMm, decimal heightMm) => Math.Round(2 * (widthMm + heightMm) / (decimal)Math.PI, 3);

    public static decimal? NetWeightKg(TubeShape? shape, decimal? diameterMm, decimal? widthMm, decimal? heightMm, decimal? thicknessMm, decimal? lengthMm)
    {
        if (shape is null || thicknessMm is not > 0 || lengthMm is not > 0) return null;
        var t = thicknessMm.Value;
        decimal area;
        switch (shape)
        {
            case TubeShape.Circular when diameterMm is > 0 && t * 2 < diameterMm:
                var d = diameterMm.Value;
                area = (decimal)Math.PI * t * (d - t);
                break;
            case TubeShape.Rectangular when widthMm is > 0 && heightMm is > 0 && t * 2 < Math.Min(widthMm.Value, heightMm.Value):
                area = 2 * t * (widthMm.Value + heightMm.Value - 2 * t);
                break;
            default:
                return null;
        }
        return Math.Round(area * lengthMm.Value * SteelDensityKgPerMm3, 5);
    }
}
