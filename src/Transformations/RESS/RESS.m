function [EEG, options] = RESS(input, varargin)
%% RESS  Rhythmic entrainment source separation: for each stimulation
%   frequency, one new channel that combines the scalp channels with the
%   weights that carry the most power at that frequency.
%
%   WHAT IT IS FOR. A response to flicker is usually read from one electrode,
%   or a few, chosen for where the response looks strongest. That choice
%   differs between people and frequencies, and choosing channels by their
%   own response is circular. RESS (Cohen & Gulbinaite, 2017, NeuroImage
%   147, 43-56) replaces it with a spatial filter per recording and
%   frequency: the combination of all scalp channels whose power at the
%   stimulation frequency is largest relative to the frequencies beside it.
%   The component is added as a channel, "RESS60Hz" say, so everything
%   downstream reads it like an electrode: Spectral Measure's coherence and
%   phase lag to a photodiode, SNR and phase-locking, the coherence map.
%   See TransTools.RESSFilter for the method and its fidelity to the
%   authors' own code.
%
%   WHICH TRIALS BUILD A FILTER. Each row names the bins whose trials build
%   it, pooled: for the RIFT design, the 60 Hz filter from the central and
%   the peripheral 60 Hz bins together. That is the authors' advice: a
%   filter built from every condition at a frequency compares those
%   conditions fairly, because none of them had the filter fitted to it
%   alone. The component is then computed for EVERY trial, so the filter is
%   also applied to the bins it was not built from. Those are its null: what
%   the filter gives where the flicker it was built for was absent. (Not a
%   bin whose frequency divides it: 30 Hz flicker drives a 60 Hz harmonic.
%   The report keeps the two apart; see ReportSections.ressSection.)
%
%   WHICH CHANNELS. Scalp EEG only (TransTools.RESSChannels), optionally
%   with the mastoids; never eye channels, the photodiode or an earlier
%   component. Running RESS again replaces its earlier channels.
%
%   The weights, the scalp map (forward model), the eigenvalues and what
%   each filter was built from are kept in EEG.etc.alz.ress, one element per
%   component, for the report and for inspection.
%
%   A RECORDING WITHOUT A ROW'S TRIALS. One recording of a study may lack a
%   condition another has (in the RIFT study subjects 1 to 3 ran the 30 Hz
%   control, 4 to 10 the peripheral 60 Hz). Its component is then added all
%   NaN, with nTrials 0 and a .note saying why, and a warning; the other
%   components are built as usual, so Apply to All carries on and every
%   recording keeps the same channels. The report names those recordings.
%
%   Options (see TransTools.RESSPlan): rows (label, freq, bins),
%   includeMastoids, timeStart/timeStop (ms; blank for the whole epoch),
%   peakFWHM, neighbourDistance, neighbourFWHM (Hz), shrinkage (0 to 1).
%
%   Signature (Alakazam transformation contract):
%     [EEG, options] = RESS(input)        % interactive dialog
%     [EEG, options] = RESS(input, opts)  % replay a stored struct
%
%   See also TRANSTOOLS.RESSFILTER, TRANSTOOLS.RESSPLAN, RESSDIALOG,
%   SPECTRALMEASURE.
[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:RESS', varargin{:});
EEG = input;
if interactive
    options = RESSDialog(input, TransformSettings.get('RESS'));
    if isempty(options)
        EEG = [];     % cancelled; OPTIONS must still be assigned (see SpectralMeasure)
        options = [];
        return;
    end
    TransformSettings.set('RESS', options);
else
    options = opts;
end

EEG = stripComponents(EEG);
plan = TransTools.RESSPlan(EEG, options);
options.rows = arrayfun(@(r) struct('label', r.label, 'freq', r.freq, ...
    'bins', strjoin(r.bins, ', ')), plan.rows, 'UniformOutput', false);   % normalised, as stored on the node

channelLabels = {EEG.chanlocs(plan.channels).labels};
X = EEG.data(plan.channels, :, :);
filterOpts = plan.filter;
filterOpts.Window = plan.window;
info = struct('label', {}, 'freq', {}, 'bins', {}, 'channels', {}, 'weights', {}, 'map', {}, ...
    'eigenvalues', {}, 'nTrials', {}, 'rank', {}, 'shrinkage', {}, 'window', {}, ...
    'peakFWHM', {}, 'neighbourDistance', {}, 'neighbourFWHM', {}, 'note', {});
window = [];
if ~all(plan.window)
    window = [EEG.times(find(plan.window, 1)), EEG.times(find(plan.window, 1, 'last'))];
end
notes = {};
for k = 1:numel(plan.rows)
    row = plan.rows(k);
    % A row this recording has no usable trial for (none of its bins
    % occurred here, or every such trial was rejected) is noted, not fatal:
    % its channel is added all NaN, so every recording of a study keeps the
    % same channels and a Spectral Measure row naming it still runs (with
    % a missing value here), and the other components are built as usual.
    usable = row.trials(reshape(all(all(isfinite(X(:, plan.window, row.trials)), 1), 2), 1, []));
    if isempty(usable)
        note = sprintf(['%s has no usable trial of %s in this recording, so no filter was built and ' ...
            'its channel is left empty (NaN)'], row.label, strjoin(row.bins, ', '));
        EEG = appendComponent(EEG, row.label, nan(1, EEG.pnts, size(X, 3)));
        info(k) = struct('label', row.label, 'freq', row.freq, 'bins', {row.bins}, ...
            'channels', {channelLabels}, 'weights', nan(numel(channelLabels), 1), ...
            'map', nan(numel(channelLabels), 1), 'eigenvalues', [], 'nTrials', 0, 'rank', 0, ...
            'shrinkage', plan.filter.Shrinkage, 'window', window, 'peakFWHM', plan.filter.PeakFWHM, ...
            'neighbourDistance', plan.filter.NeighbourDistance, 'neighbourFWHM', plan.filter.NeighbourFWHM, ...
            'note', note);
        notes{end + 1} = note; %#ok<AGROW>
        continue;
    end
    result = TransTools.RESSFilter(X(:, :, row.trials), EEG.srate, row.freq, filterOpts);
    component = TransTools.RESSComponent(X, result.weights);
    EEG = appendComponent(EEG, row.label, component);
    info(k) = struct('label', row.label, 'freq', row.freq, 'bins', {row.bins}, ...
        'channels', {channelLabels}, 'weights', result.weights, 'map', result.map, ...
        'eigenvalues', result.eigenvalues, 'nTrials', nnz(result.trialsUsed), 'rank', result.rank, ...
        'shrinkage', result.shrinkage, 'window', window, 'peakFWHM', plan.filter.PeakFWHM, ...
        'neighbourDistance', plan.filter.NeighbourDistance, 'neighbourFWHM', plan.filter.NeighbourFWHM, ...
        'note', '');
    [~, peak] = max(abs(result.map));
    fprintf(['RESS: %s from %d trial(s) of %s, %d channels: power at %g Hz %.2f times that beside ' ...
             'it (next component %.2f); its map peaks at %s.\n'], row.label, nnz(result.trialsUsed), ...
        strjoin(row.bins, ', '), numel(channelLabels), row.freq, result.eigenvalues(1), ...
        result.eigenvalues(min(2, end)), channelLabels{peak});
end
if ~isempty(notes)
    % One warning for all of them, in the command window like the other
    % transformations' notes; the report names the recordings (see
    % ReportSections.ressSection), from the note kept in EEG.etc.alz.ress.
    warning('Alakazam:RESS:noTrials', '%s.', strjoin(notes, '; '));
end
if ~isfield(EEG, 'etc') || ~isstruct(EEG.etc)
    EEG.etc = struct();
end
if ~isfield(EEG.etc, 'alz') || ~isstruct(EEG.etc.alz)
    EEG.etc.alz = struct();
end
EEG.etc.alz.ress = info;
end

function EEG = appendComponent(EEG, label, component)
%APPENDCOMPONENT  Add COMPONENT (1 x samples x trials) as a last channel,
%   typed 'RESS' and without a scalp position: it is a combination of
%   channels, not an electrode, so scalp maps leave it out.
    cl = EEG.chanlocs;
    if ~isfield(cl, 'type')
        [cl.type] = deal('');
    end
    fields = fieldnames(cl);
    newChan = cell2struct(repmat({[]}, numel(fields), 1), fields, 1);
    newChan.labels = label;
    newChan.type = 'RESS';
    EEG.chanlocs = [cl(:)', newChan];
    EEG.data(end + 1, :, :) = cast(component, 'like', EEG.data);
    EEG.nbchan = size(EEG.data, 1);
end

function EEG = stripComponents(EEG)
%STRIPCOMPONENTS  Remove the channels an earlier RESS run added, so running
%   it again replaces them rather than piling them up.
    if ~isfield(EEG, 'chanlocs') || isempty(EEG.chanlocs) || ~isfield(EEG.chanlocs, 'type')
        return;
    end
    isComponent = strcmpi({EEG.chanlocs.type}, 'RESS');
    if any(isComponent)
        EEG.chanlocs = EEG.chanlocs(~isComponent);
        EEG.data = EEG.data(~isComponent, :, :);
        EEG.nbchan = size(EEG.data, 1);
    end
end
