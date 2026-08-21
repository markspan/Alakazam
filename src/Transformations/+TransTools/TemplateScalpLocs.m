function [locs, hasPos] = TemplateScalpLocs(chanlocs, elcFile)
%TEMPLATESCALPLOCS  Fill channel scalp coordinates from a 10-5 template by label.
%   Returns CHANLOCS with each recognised channel's theta/radius/X/Y/Z copied
%   from the template read from ELCFILE, and HASPOS, a logical row marking which
%   channels the template positioned. A direct readlocs lookup (no pop_chanedit
%   / eeg_checkset, which choke on the app's bin-based averaged structs, and no
%   nose-direction rewrite), so DrawScalpMap orients the maps nose-up. Shared by
%   ScalpDistribution, CoherenceTopography and RemoveComponents.
    locs = chanlocs;
    hasPos = false(1, numel(locs));
    template = readlocs(elcFile);
    templateLabels = lower(string({template.labels}));
    for c = 1:numel(locs)
        m = find(templateLabels == lower(string(locs(c).labels)), 1);
        if isempty(m); continue; end
        locs(c).X      = template(m).X;
        locs(c).Y      = template(m).Y;
        locs(c).Z      = template(m).Z;
        locs(c).theta  = template(m).theta;
        locs(c).radius = template(m).radius;
        hasPos(c) = true;
    end
end
