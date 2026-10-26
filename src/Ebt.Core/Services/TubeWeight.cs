using Ebt.Core.Entities;

namespace Ebt.Core.Services;

public static class TubeWeight
{
    public const decimal SteelDensityKgPerMm3 = 0.00000785m;

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
