function [EEG, options] = Measure(input, opts)
%% Measure  Quantify ERP components (mean amplitude, peak amplitude, peak
%   latency) in named time windows, for group-level statistics.
%
%   Works on an averaged dataset (a subject Average or a Grand Average),
%   the same DataFormat=='Averaged' contract ScalpDistribution.m checks:
%   EEG.data is channels x samples[ x bins]. Reads a set of named
%   measurement windows (see MeasureDialog) and, for each window x bin x
%   selected channel, computes either:
%     * Mean Amplitude -- the NaN-tolerant mean of the window's samples.
%     * Peak -- both the extreme (by polarity) amplitude in the window and
%       its latency (ms). With a reference channel set, the latency is
%       found on that one channel only, then that same sample is read on
%       every other selected channel (Analyzer's "search peak in a
%       reference channel" mode); without one, every channel is searched
%       independently.
%
%   Passes EEG.data/EEG.times/etc. through completely unchanged -- this is
%   a read-only quantification step, not a signal-processing one. Adds
%   EEG.measurements: a 1xN cell array (N = number of windows, never a
%   struct array -- see the note on WINDOWS below) of scalar structs:
%       .label, .start, .stop, .measure, .polarity, .refChannel, .channels
%           -- the window definition, carried through so the CSV export
%              can label its rows (see exportMeasurementsCSV.m)
%       .amplitude, .latency
%           -- numel(.channels) x nBins numeric matrices. .latency is all
%              NaN for a Mean Amplitude window (amplitude has no
%              meaningful associated latency there).
%
%   Signature (Alakazam transformation contract):
%     [EEG, options] = Measure(input)        % interactive: open MeasureDialog
%     [EEG, options] = Measure(input, opts)  % replay: opts.windows is a
%                                             %   stored window-definition
%                                             %   cell array
%
%   WINDOWS (both MeasureDialog's return value and options.windows) is
%   deliberately a 1xN CELL array of scalar structs, never a struct array:
%   jsonencode collapses a 1-element struct array embedded in another
%   struct's field to a bare JSON object instead of a single-element
%   array (the same gotcha documented in WorkSpaceTree.buildData and
%   worked around in Alakazam.onSaveTemplate), which would silently break
%   Save Template/Apply Template for a one-window Measure step. A cell
%   array sidesteps it regardless of count, so Measure never needs a
%   templateParams-style special case. Each window's .channels is, for
%   the same reason, always a cellstr (never a bare char for a single
%   channel) -- see MeasureDialog and resolveChannelList below.
%
%   See also: MEASUREDIALOG, AVERAGE, SCALPDISTRIBUTION, EXPORTMEASUREMENTSCSV.

%% Guard input
if nargin < 1
    throw(MException('Alakazam:Measure', ...
        'Problem in Measure: needs a dataset to run on, and none was given.'));
end
if nargin < 2
    opts = 'Init';
end

EEG = input;

if ~isfield(input, 'DataFormat') || ~strcmpi(input.DataFormat, 'Averaged')
    throw(MException('Alakazam:Measure', sprintf([ ...
        'Problem in Measure: only works on an averaged ERP (a subject Average or a Grand ' ...
        'Average), not this dataset (DataFormat = "%s"). Run Average -- or Grand Average, ' ...
        'for a group result -- on it first.'], input.DataFormat)));
end

%% Mode: interactive (Init) or replay (stored options struct)
interactive = (ischar(opts) || isstring(opts)) && strcmpi(string(opts), "Init");

if interactive
    stored = TransformSettings.get('Measure');
    if isempty(stored) || ~isfield(stored, 'windows')
        priorWindows = {};
    else
        priorWindows = stored.windows;
    end
    windows = MeasureDialog(input.chanlocs, priorWindows);
    if isempty(windows)
        % Cancelled: nothing to persist and nothing to run -- see
        % TransformOptionsDialog's own header comment for why every
        % transformation using a dialog must return [] on Cancel.
        EEG = [];
        return;
    end
    options = struct('windows', {windows});
    TransformSettings.set('Measure', options);
else
    if ~isstruct(opts) || ~isfield(opts, 'windows')
        throw(MException('Alakazam:Measure', ...
            ['Measure was asked to replay a previous run, but the stored settings it was ' ...
             'given do not look like ones Measure itself produced (no .windows field).']));
    end
    windows = opts.windows;
    options = opts;
end

if isempty(windows)
    throw(MException('Alakazam:Measure', ...
        ['No measurement windows are defined, so there is nothing for Measure to do. Add ' ...
         'at least one window (a name, a start/stop time, and a measure type).']));
end

%% Compute
allLabels = string({EEG.chanlocs.labels});
nBins = size(EEG.data, 3); % 1 for an unbinned average (2-D EEG.data)

measurements = cell(1, numel(windows));
for w = 1:numel(windows)
    measurements{w} = computeWindow(EEG, windows{w}, allLabels, nBins);
end
EEG.measurements = measurements;
end

% ======================================================================= %
%  Per-window computation
% ======================================================================= %
function m = computeWindow(EEG, win, allLabels, nBins)
%COMPUTEWINDOW  Compute one window's amplitude/latency matrices.
    channels = resolveChannelList(win.channels, allLabels, win.label);
    chanIdx = arrayfun(@(c) find(allLabels == c, 1), channels);

    [loIdx, hiIdx] = windowSampleRange(EEG.times, win.start, win.stop);

    nCh = numel(chanIdx);
    amplitude = nan(nCh, nBins);
    latency   = nan(nCh, nBins);

    isPeak = strcmpi(win.measure, 'Peak');
    if isPeak && ~isempty(win.refChannel)
        refIdx = find(allLabels == string(win.refChannel), 1);
        if isempty(refIdx)
            throw(MException('Alakazam:Measure', sprintf( ...
                'Window "%s" names a reference channel ("%s") that is not in this dataset.', ...
                win.label, win.refChannel)));
        end
        % Latency is found once per bin on the reference channel alone,
        % then that same absolute sample is read on every selected
        % channel -- Analyzer's "search peak in a reference channel" mode
        % (locks amplitude readouts across channels to one shared
        % latency, rather than letting each channel's own local peak
        % drift independently).
        refSample = nan(1, nBins);
        for b = 1:nBins
            refSample(b) = findPeakSample(EEG.data(refIdx, loIdx:hiIdx, b), win.polarity, loIdx);
        end
        for c = 1:nCh
            for b = 1:nBins
                if isnan(refSample(b)); continue; end
                amplitude(c, b) = EEG.data(chanIdx(c), refSample(b), b);
                latency(c, b)   = EEG.times(refSample(b));
            end
        end
    elseif isPeak
        for c = 1:nCh
            for b = 1:nBins
                s = findPeakSample(EEG.data(chanIdx(c), loIdx:hiIdx, b), win.polarity, loIdx);
                if isnan(s); continue; end
                amplitude(c, b) = EEG.data(chanIdx(c), s, b);
                latency(c, b)   = EEG.times(s);
            end
        end
    else % Mean Amplitude
        for c = 1:nCh
            for b = 1:nBins
                amplitude(c, b) = mean(EEG.data(chanIdx(c), loIdx:hiIdx, b), 'omitnan');
            end
        end
    end

    m = struct('label', win.label, 'start', win.start, 'stop', win.stop, ...
        'measure', win.measure, 'polarity', win.polarity, 'refChannel', win.refChannel, ...
        'channels', {cellstr(channels)}, 'amplitude', amplitude, 'latency', latency);
end

function s = findPeakSample(windowData, polarity, loIdx)
%FINDPEAKSAMPLE  The absolute sample index (into the full recording, not
%   the window-relative slice WINDOWDATA) of its extreme value by
%   POLARITY, or NaN if every sample in the window is NaN -- nothing to
%   find, e.g. an unresolved combo bin Average.m left as NaN (see its own
%   header comment: DefineBins rejects unresolvable combos at parse time,
%   so this is a defensive fallback, not the common case). max/min on an
%   all-NaN vector return NaN with idx==1, which would otherwise silently
%   look like a real match at the window's first sample.
    if strcmpi(polarity, 'Negative')
        [ext, idx] = min(windowData);
    else
        [ext, idx] = max(windowData);
    end
    if isnan(ext)
        s = NaN;
    else
        s = loIdx + idx - 1;
    end
end

function [loIdx, hiIdx] = windowSampleRange(times, startMs, stopMs)
%WINDOWSAMPLERANGE  The [loIdx, hiIdx] sample range nearest [STARTMS,
%   STOPMS] in TIMES -- nearest-sample snapping (the same t -> sample
%   lookup ScalpDistributionView.redraw uses), not a range search, so a
%   window edge a few ms outside the true data range still clamps to the
%   nearest real edge sample instead of returning an empty range.
    [~, loIdx] = min(abs(times - startMs));
    [~, hiIdx] = min(abs(times - stopMs));
    if loIdx > hiIdx
        [loIdx, hiIdx] = deal(hiIdx, loIdx);
    end
end

function channels = resolveChannelList(spec, allLabels, windowLabel)
%RESOLVECHANNELLIST  SPEC (a cellstr of requested channel labels, or empty
%   meaning "every channel") resolved to a string array in ALLLABELS' own
%   canonical casing, case-insensitively matched. Throws a friendly error
%   naming any requested label that does not exist in this dataset --
%   this runs at REPLAY time (drag-and-drop, Apply to All Raw Files,
%   Apply Template), not just interactively, since a saved window
%   definition can end up applied to a dataset whose channels differ from
%   whatever MeasureDialog originally validated against.
%
%   isempty(SPEC), not an iscell-specific check: an empty cellstr on the
%   way in (MeasureDialog's own "blank = all channels") stays empty, but
%   a stored "all channels" window can also come back as a plain [] after
%   a jsonencode/jsondecode round trip (JSON has no way to remember an
%   empty array's original element type) -- treating any empty value as
%   "all channels" handles both uniformly.
    if isempty(spec)
        channels = allLabels;
        return;
    end
    requested = string(cellstr(spec));
    channels = strings(1, numel(requested));
    missing = strings(1, 0);
    for i = 1:numel(requested)
        match = find(lower(allLabels) == lower(requested(i)), 1);
        if isempty(match)
            missing(end + 1) = requested(i); %#ok<AGROW>
        else
            channels(i) = allLabels(match);
        end
    end
    if ~isempty(missing)
        throw(MException('Alakazam:Measure', sprintf( ...
            'Window "%s" names channel(s) not in this dataset: %s.', ...
            windowLabel, strjoin(missing, ', '))));
    end
end
