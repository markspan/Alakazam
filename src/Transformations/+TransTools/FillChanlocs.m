function EEG = FillChanlocs(EEG, errorId, elcFile)
%FILLCHANLOCS  Auto-fill electrode positions from a standard 10-5 template.
%   EEG = FILLCHANLOCS(EEG, ERRORID, ELCFILE) fills in any missing channel
%   X/Y/Z from ELCFILE, an absolute path to an electrode template: pop_
%   chanedit's 'lookup' only special-cases a couple of specific filenames by
%   name (see pop_chanedit.m), anything else -- including this file -- needs
%   a full path, or its underlying readlocs() call cannot find it.
%
%   This does NOT require every channel to end up positioned: a channel
%   whose label the template does not recognise (e.g. an EOG or ECG
%   channel, which has no scalp position) is simply left with an empty/NaN
%   X. ERRORID is only used for infrastructure failures (the given file
%   missing), so it still reports as the calling transformation. Callers
%   that only need *some* channels positioned (AutoEyeICA and AutoGEDAI,
%   which both process just the channels with a recognised scalp position
%   and splice the rest back unmodified) check EEG.chanlocs.X themselves
%   afterward to split channels into an eligible/ineligible set.
%
%   Callers pick their own template: AutoEyeICA uses dipfit's standard 10-5
%   template (see Dipfit1005File); AutoGEDAI uses GEDAI's own bundled copy
%   (see GedaiElcFile), so its electrode set exactly matches what GEDAI
%   itself expects.
%
%   See also: Dipfit1005File, AutoEyeICA, AutoGEDAI.

    hasAllLocs = isfield(EEG, 'chanlocs') && ~isempty(EEG.chanlocs) ...
        && isfield(EEG.chanlocs, 'X') ...
        && all(arrayfun(@(c) ~isempty(c.X) && ~isnan(c.X), EEG.chanlocs));
    if hasAllLocs
        return;
    end

    if exist(elcFile, 'file') ~= 2
        throw(MException(errorId, ...
            'Cannot auto-fill electrode positions: %s was not found.', elcFile));
    end
    EEG = pop_chanedit(EEG, 'lookup', elcFile);
end
