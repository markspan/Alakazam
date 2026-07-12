function cmap = DivergingColormap()
%DIVERGINGCOLORMAP  The app's shared colour map for a signed, zero-
%   centred quantity (ERSP power vs. baseline, ERP-image/scalp-topography
%   amplitude, ...), settings-driven via AlakazamSettings
%   ("graphics"/"colormap"/"name"): "diverging" (the default) is a short
%   hand-built blue -> white -> red map (MATLAB ships no built-in
%   diverging colormap), centred on the midpoint -- the standard
%   "decrease / no change / increase" convention; the other choices are
%   MATLAB's own built-in colour maps, for anyone who prefers a familiar
%   one over this diverging convention.
%
%   Shared by EpochView (ERP-image amplitude), TimeFrequencyView (dB
%   power vs. baseline) and TransTools.DrawScalpMap (scalp topography)
%   -- one call site, so every plot that shows a signed quantity always
%   uses the SAME colour map, and changing the setting updates all three
%   at once without touching any of their own code.
    name = AlakazamSettings.get("graphics", "colormap", "name");
    switch name
        case "parula"
            cmap = parula(64);
        case "jet"
            cmap = jet(64);
        case "turbo"
            cmap = turbo(64);
        case "hot"
            cmap = hot(64);
        case "cool"
            cmap = cool(64);
        otherwise % "diverging", and the fallback for an unrecognised/stale setting value
            n = 32;
            blue  = [0.13 0.35 0.75];
            white = [1 1 1];
            red   = [0.75 0.15 0.15];
            lower = [linspace(blue(1), white(1), n)', linspace(blue(2), white(2), n)', linspace(blue(3), white(3), n)'];
            upper = [linspace(white(1), red(1), n)', linspace(white(2), red(2), n)', linspace(white(3), red(3), n)'];
            cmap = [lower; upper(2:end, :)];
    end
end
