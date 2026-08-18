function EEG = ResolveScalpDistribution(EEG, errorId)
%RESOLVESCALPDISTRIBUTION  Resolve channel scalp positions and a shared
%   colour scale for an averaged ERP -- everything ScalpDistribution.m and
%   Brain3D.m both need before drawing, factored out here since it is
%   otherwise identical between them (2D flat topography vs. projection
%   onto a 3D brain mesh, see DrawScalpMap/DrawBrainMap): only the drawing
%   differs, not what gets resolved.
%
%   A scalp map only makes sense for channels with a real scalp position:
%   look each one up, by label, directly in the standard 10-5 template
%   (most datasets also carry a few non-scalp channels, e.g. EOG/ECG, which
%   a template has no position for -- keep only the ones that resolve).
%
%   This deliberately does not use TransTools.FillChanlocs (which resolves
%   positions via pop_chanedit): pop_chanedit runs eeg_checkset on the whole
%   EEG struct, which expects native per-trial EEG.event(i).epoch bookkeeping
%   that our bin-based Session model never populates (DefineBins/Average tag
%   events with .bini, not EEGLAB's own .epoch) -- on a real Averaged dataset
%   (as opposed to a fresh eeg_emptyset(), which papers over this) that
%   mismatch makes eeg_checkset abort outright ("the event info structure
%   does not contain an 'epoch' field"). A direct template lookup by label
%   only ever touches a plain chanlocs array, never eeg_checkset, and is the
%   same approach AutoGEDAI already uses for its own template matching.
%
%   ERRORID is the caller's own MException id (e.g. 'Alakazam:Brain3D');
%   every error message here is prefixed "Problem in <Name>: ..." (NAME
%   taken from the part of ERRORID after the colon), matching every other
%   transformation's own error-message convention despite this code living
%   outside the transformation function itself.
%
%   Sets, and returns EEG with:
%     .ScalpChanlocs    the positioned channels only (chanlocs(hasPos))
%     .ScalpHasPos      logical row into the ORIGINAL EEG.chanlocs
%     .ScalpMapLimit    one shared, symmetric |value| colour limit across
%                        the whole dataset (every bin, every instant), so a
%                        low-amplitude moment never looks just as saturated
%                        as a high-amplitude one while scrubbing
%     .ScalpSourceFile  EEG.File, stashed under its ORIGINAL value: by the
%                        time the resulting view runs, Alakazam.
%                        persistResultNode has already overwritten EEG.File
%                        with this result's own new cache path, so this is
%                        exactly what a sibling AverageView tab is tagged
%                        with (see TransTools.TickedScalpBins)
%
%   See also SCALPDISTRIBUTION, BRAIN3D, TRANSTOOLS.DRAWSCALPMAP,
%   TRANSTOOLS.DRAWBRAINMAP, TRANSTOOLS.TEMPLATESCALPLOCS.
    parts = strsplit(errorId, ':');
    name = parts{end};

    if ~isfield(EEG, 'DataFormat') || ~strcmpi(EEG.DataFormat, 'Averaged')
        throw(MException(errorId, sprintf([ ...
            'Problem in %s: only works on an averaged ERP (a subject Average ' ...
            'or a Grand Average), not this dataset (DataFormat = "%s"). Run ' ...
            'Average -- or Grand Average, for a group result -- on it ' ...
            'first.'], name, EEG.DataFormat)));
    end

    [chanlocs, hasPos] = TransTools.TemplateScalpLocs(EEG.chanlocs, TransTools.Dipfit1005File(errorId));

    if ~any(hasPos)
        throw(MException(errorId, sprintf([ ...
            'Problem in %s: none of this dataset''s channels match a ' ...
            'standard scalp position, so there is nothing to plot. Rename ' ...
            'channels to match 10-5 nomenclature, or set their locations ' ...
            'manually first.'], name)));
    end

    % Scale on the scalp EEG channels only: a positioned EOG/ECG channel
    % would otherwise set the limit and wash out the EEG maps (see
    % eegChannelMask). The maps still draw every positioned channel; only
    % the shared colour limit is restricted. Falls back to all positioned
    % channels when no channel is left.
    scaleMask = hasPos(:)' & eegChannelMask(chanlocs);
    if ~any(scaleMask); scaleMask = hasPos(:)'; end
    mapLimit = max(abs(EEG.data(scaleMask, :, :)), [], 'all');
    if mapLimit == 0 || isnan(mapLimit)
        mapLimit = 1; % an all-zero (or all-NaN) dataset would otherwise give an empty [0 0] scale
    end

    EEG.ScalpSourceFile = EEG.File; % stash before persistResultNode overwrites EEG.File, see above
    EEG.ScalpChanlocs   = chanlocs(hasPos);
    EEG.ScalpHasPos     = hasPos;
    EEG.ScalpMapLimit   = mapLimit;
end
