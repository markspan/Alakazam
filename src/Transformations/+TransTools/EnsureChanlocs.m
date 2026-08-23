function EEG = EnsureChanlocs(EEG, errorId, elcFile)
%ENSURECHANLOCS  Guarantee every channel has a real X/Y/Z scalp position.
%   EEG = ENSURECHANLOCS(EEG, ERRORID, ELCFILE) auto-fills any missing
%   electrode position from ELCFILE (see FillChanlocs) and requires every
%   channel to end up positioned: one whose label the template does not
%   recognise is a hard error (ERRORID, e.g. 'Alakazam:AutoEyeICA'), naming
%   the channel, rather than a silent gap.
%
%   Currently UNUSED: AutoEyeICA used to call this (requiring every
%   channel, including EOG/ECG, to be positioned before running ICA), which
%   meant a dataset with an unlocatable EOG channel -- the common case --
%   threw outright instead of just excluding that channel. AutoEyeICA now
%   follows AutoGEDAI's pattern instead: FillChanlocs, then process only
%   the channels that resolve to a position and splice the rest back
%   unmodified. Kept here in case a future caller genuinely needs the
%   all-or-nothing behaviour; delete if it stays unused.
%
%   See also: FillChanlocs, Dipfit1005File, AutoEyeICA, AutoGEDAI.

    EEG = TransTools.FillChanlocs(EEG, errorId, elcFile);

    missing = arrayfun(@(c) isempty(c.X) || isnan(c.X), EEG.chanlocs);
    if any(missing)
        throw(MException(errorId, ...
            ['I''m afraid every electrode needs an X/Y/Z position, and no standard ' ...
             '10-5 position could be found for: %s. Please rename these channels to ' ...
             'match 10-5 nomenclature, or set their locations manually ' ...
             '(Edit > Channel locations) first.'], ...
            strjoin({EEG.chanlocs(missing).labels}, ', ')));
    end
end
