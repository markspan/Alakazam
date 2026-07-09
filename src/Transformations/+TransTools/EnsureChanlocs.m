function EEG = EnsureChanlocs(EEG, errorId, elcFile)
%ENSURECHANLOCS  Guarantee every channel has a real X/Y/Z scalp position.
%   EEG = ENSURECHANLOCS(EEG, ERRORID, ELCFILE) auto-fills any missing
%   electrode position from ELCFILE (see FillChanlocs) and requires every
%   channel to end up positioned: one whose label the template does not
%   recognise is a hard error (ERRORID, e.g. 'Alakazam:AutoEyeICA'), naming
%   the channel, rather than a silent gap. Used by AutoEyeICA, which runs
%   ICA (and hence needs a position) on every channel it is given.
%
%   AutoGEDAI processes only the channels that resolve to a position (e.g.
%   excluding EOG) rather than requiring all of them, so it calls
%   FillChanlocs directly instead of this stricter wrapper.
%
%   See also: FillChanlocs, Dipfit1005File, AutoEyeICA, AutoGEDAI.

    EEG = TransTools.FillChanlocs(EEG, errorId, elcFile);

    missing = arrayfun(@(c) isempty(c.X) || isnan(c.X), EEG.chanlocs);
    if any(missing)
        throw(MException(errorId, ...
            ['Needs an X/Y/Z position for every electrode. No standard ' ...
             '10-5 position was found for: %s. Rename these channels to ' ...
             'match 10-5 nomenclature, or set their locations manually ' ...
             '(Edit > Channel locations) first.'], ...
            strjoin({EEG.chanlocs(missing).labels}, ', ')));
    end
end
