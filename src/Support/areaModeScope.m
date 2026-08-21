function [mode, isBand] = areaModeScope(win, measureName)
%AREAMODESCOPE  A window's area mode ('signed'/'rectified'/'positive'/
%   'negative', default 'signed') and whether its scope is a peak-locked
%   band. Tolerates a measurement stored before the Area family was unified
%   into one measure (Peak Area -> band, Integral -> whole window), which
%   carries no areaMode/scope field.
%
%   Extracted from exportMeasurementsCSV.m (its own local function of the
%   same name) so measureRowTypes.m can share the exact same area-mode
%   logic rather than re-deriving it a second way.
    mode = 'signed';
    if isfield(win, 'areaMode') && ~isempty(win.areaMode)
        cand = lower(strtrim(char(string(win.areaMode))));
        if ismember(cand, {'signed', 'rectified', 'positive', 'negative'})
            mode = cand;
        end
    end
    if isfield(win, 'scope') && ~isempty(win.scope)
        isBand = strcmpi(strtrim(char(string(win.scope))), 'band');
    else
        isBand = strcmp(measureName, 'peak area');
    end
end
