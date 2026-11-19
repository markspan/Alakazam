function [EEG, options] = Measure(input, varargin)
%% Measure  Quantify ERP components (mean amplitude, peak amplitude, peak
%   latency) in named time windows, for group-level statistics.
%
%   Works on an averaged dataset (a subject Average or a Grand Average),
%   the same DataFormat=='Averaged' contract ScalpDistribution.m checks:
%   EEG.data is channels x samples[ x bins]. Reads a set of named
%   measurement windows (see MeasureDialog) and, for each window x bin x
%   selected channel, computes one of:
%     * Mean Amplitude -- the NaN-tolerant mean of the window's samples.
%     * Peak -- both the extreme (by polarity) amplitude in the window and
%       its latency (ms). With a reference channel set, the latency is
%       found on that one channel only, then that same sample is read on
%       every other selected channel (Analyzer's "search peak in a
%       reference channel" mode); without one, every channel is searched
%       independently.
%     * Area -- the area (uV.ms) over either the whole window (.width 0 or
%       blank) or a peak-locked band .width ms wide centered on the located
%       peak (.width > 0). .areaMode picks how: 'signed' (numerical
%       integration, negatives subtract), 'rectified' (|v|), 'positive'
%       (only above 0) or 'negative' (only below 0). A peak-band Area also
%       reports the peak's amplitude and latency, and honors a reference
%       channel the same way Peak does. (The old Integral = signed whole-
%       window Area; the old Peak Area = signed peak-band Area; both still
%       replay, folded into Area.)
%     * Fractional Peak Latency -- the latency at which the waveform rises
%       through .fraction x its peak amplitude on the onset side (ERPLAB's
%       fractional peak latency), interpolated between samples.
%     * Fractional Area Latency -- the latency dividing the window's
%       cumulative area at .fraction (e.g. 0.5 = 50% area latency, the
%       robust onset measure), interpolated between samples. .areaMode
%       selects WHICH area is accumulated, the same four choices Area
%       itself offers: 'signed', 'rectified', 'positive' or 'negative'
%       (ERPLAB's fninteglat, fareatlat, fareaplat and fareanlat). Prefer a
%       single-signed mode for a window spanning both polarities: only the
%       signed cumulative area can reach its own fraction more than once,
%       and this reports the first (earliest) crossing.
%
%   The peak-locating measures (Peak, peak-band Area, Fractional Peak
%   Latency) honour .localPoints: 0 = the absolute extreme; >=1 = the most
%   extreme LOCAL peak (more extreme than that many neighbours each side),
%   falling back to the absolute extreme if the window has none.
%
%   Every measure honours an optional .baseline interval: each channel's
%   own mean over it is subtracted before the measure is taken (matters
%   most for the area measures, which a DC offset inflates).
%
%   Optionally derives new channels first from a block of "let" statements
%   (options.derivations, e.g. "let LRP = C3 - C4"): each is appended to
%   EEG.data/EEG.chanlocs (marked .type = 'derived') so it can be measured
%   here AND shows up downstream on the ERP plot and in grand averages, and
%   can be named in any window's Channels/Reference cell. A difference
%   channel has no scalp position, so ScalpDistribution drops it from the
%   head map automatically. See TransTools.ApplyDerivations.m. Apart from those
%   opt-in derived channels, EEG.data/EEG.times/etc. pass through unchanged.
%
%   Adds EEG.measurements: a 1xN cell array (N = number of windows, never a
%   struct array -- see the note on WINDOWS below) of scalar structs:
%       .label, .start, .stop, .measure, .polarity, .width, .localPoints,
%       .fraction, .areaMode, .baseline, .refChannel, .channels
%           -- the window definition, carried through so the CSV export
%              can label its rows (see exportMeasurementsCSV.m). .width is
%              the Area band width / scope switch, .fraction the fractional
%              latency (0..1), .localPoints the local-peak neighbourhood
%              (0 = absolute), .baseline a "[start stop] ms" pre-window (or
%              blank). The OUTPUT struct additionally carries .areaMode and
%              .scope ('band'/'window', or '' for non-area) so the exporter
%              knows how to label an Area row; .channels on output is the
%              resolved list of output-channel labels (a pool shows as
%              "{Pz+POz+CPz}") -- see measureChannelSpecs.
%       .amplitude, .latency, .area
%           -- numel(.channels) x nBins numeric matrices, each filled only
%              for the measures it applies to and NaN elsewhere: .amplitude
%              for Mean Amplitude, Peak and peak-band Area; .latency for
%              Peak, peak-band Area and the two fractional-latency measures;
%              .area for Area. The CSV exporter picks the right field(s) per
%              window from .measure/.areaMode/.scope.
%
%   The scoring of one waveform is TransTools.MeasureScorer, which erpScoreSME
%   shares, so the SME beside a value is the standard error of that value.
%
%   TOOLBOX OR OWN CODE. These are ERPLAB's measures (geterpvalues), but
%   ERPLAB is not a toolbox Alakazam installs, and geterpvalues reads ERPLAB's
%   ERPsets, where this works on Alakazam's averages and grand averages, pools
%   channels, searches a peak on a reference channel, and reports the SME
%   beside each value. Measured against ERPLAB 13.10's geterpvalues on all ten
%   published N400 erpsets, 100 cells per measure (Docs/luck.md): amplitudes
%   and areas to a relative 4e-8, latencies exactly.
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
%   array sidesteps that on the ENCODE side regardless of count -- but
%   jsondecode still hands back a plain struct array on the way IN
%   (Apply Template's own readTemplate/jsondecode round trip), same as it
%   would for any same-shaped-objects JSON array, one level up (see
%   readTemplate's own asItemList, which normalises exactly this for the
%   template's step list); the replay branch below re-normalises
%   options.windows the same way, so Measure still doesn't need a
%   templateParams-style special CASE, just this one CONVERSION. Each
%   window's .channels is, for the same reason, always a cellstr (never a
%   bare char for a single channel) -- see MeasureDialog and
%   resolveChannelList below.
%
%   See also: MEASUREDIALOG, AVERAGE, SCALPDISTRIBUTION, EXPORTMEASUREMENTSCSV.

%% Guard input
[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:Measure', varargin{:});

EEG = input;

% EPOCHED DATA IS ACCEPTED, AND MEANS SOMETHING DIFFERENT. On an average
% the third dimension of EEG.data is bins and every window yields one value
% per bin; on epoched data it is TRIALS, and the identical computation
% yields one value per trial. computeWindow below simply iterates that
% dimension and never asks what it represents, so single-trial measurement
% needs no second implementation of peak-picking, fractional-area latency
% or channel pooling -- which is the only reason it is offered here rather
% than as a parallel transformation that would have to duplicate all of it.
%
% The two are not interchangeable and the result says which it is:
% averaged input fills EEG.measurements, epoched input fills
% EEG.trialMeasurements. Nothing downstream has to guess.
dataFormat = char(string(TransTools.FieldOr(input, 'DataFormat', 'not set')));
perTrial = strcmpi(dataFormat, 'EPOCHED');
if ~perTrial && ~strcmpi(dataFormat, 'Averaged')
    % TransTools.FieldOr, not input.DataFormat: the condition above is true
    % when the field is ABSENT as well as when it is wrong, and reading it
    % directly then threw a bare MATLAB "Unrecognized field name" from
    % inside the very sprintf meant to explain the problem.
    throw(MException('Alakazam:Measure', sprintf([ ...
        'Problem in Measure: this works on an averaged ERP (a subject Average or a Grand ' ...
        'Average), or on epoched data for per-trial measurement, and not on this dataset ' ...
        '(DataFormat = "%s"). Would you run Average -- or Grand Average, for a group result ' ...
        '-- on it first?'], dataFormat)));
end

if interactive
    stored = TransformSettings.get('Measure');
    if isempty(stored) || ~isfield(stored, 'windows')
        priorWindows = {};
    else
        priorWindows = stored.windows;
        if isstruct(priorWindows)
            % A node created (or recalculated) before this normalisation
            % existed can still have a struct-array .windows baked into
            % its own saved .params -- recalculateTransformNode seeds
            % TransformSettings straight from that node's own file (see
            % its own header comment), so this reaches here un-normalised
            % on the very first Recalculate. MeasureDialog's rowsFromWindows
            % indexes priorWindows{i}, which errors ("Brace indexing is
            % not supported for variables of type struct") on a struct
            % array before the dialog even finishes building -- normalise
            % here too, not just in the replay branch below, so reopening
            % an old node's dialog self-heals it instead of crashing.
            priorWindows = num2cell(priorWindows);
        end
    end
    priorDerivations = '';
    if isstruct(stored) && isfield(stored, 'derivations')
        priorDerivations = stored.derivations;
    end
    [windows, derivations] = MeasureDialog(input.chanlocs, priorWindows, priorDerivations);
    if isempty(windows)
        % Cancelled: nothing to persist and nothing to run -- see
        % TransformOptionsDialog's own header comment for why every
        % transformation using a dialog must return [] on Cancel. OPTIONS
        % (the second declared output) must still be assigned: every
        % caller here (onTransformation.m, recalculateTransformNode.m)
        % requests both outputs unconditionally, so leaving it unset
        % throws "Output argument not assigned" instead of the clean
        % cancel this branch means to be.
        EEG = [];
        options = [];
        return;
    end
    options = struct('windows', {windows}, 'derivations', derivations);
    TransformSettings.set('Measure', options);
else
    if ~isstruct(opts) || ~isfield(opts, 'windows')
        throw(MException('Alakazam:Measure', ...
            ['Measure has been asked to replay a previous run, but I''m afraid the stored ' ...
             'settings it was given do not look like ones Measure itself produced (there is no .windows field).']));
    end
    windows = opts.windows;
    if isstruct(windows)
        % A template round trip through jsonencode/jsondecode (Apply
        % Template) turns a cell array of same-shaped structs back into a
        % struct array, not a cell array -- unlike the direct .mat-cache
        % replay path (drag-drop/Apply to All Raw Files), which preserves
        % the cell array exactly. Normalise back so the cell-array
        % indexing below (and computeWindow's own windows{w} caller)
        % works regardless of which replay path got us here.
        windows = num2cell(windows);
    end
    % options.windows must carry the NORMALISED (cell array) form, not
    % whatever shape opts.windows happened to arrive in: options becomes
    % this run's own EEG.params (onTransformation.m/applyStepToTarget.m
    % both save it verbatim onto the resulting node), so options = opts
    % alone would keep re-saving a struct-array-contaminated .windows on
    % every node built this way -- self-perpetuating the exact "Brace
    % indexing is not supported for variables of type struct" crash the
    % local normalisation above only fixed for THIS run's own computation,
    % not for the node a later Recalculate would read back.
    options = opts;
    options.windows = windows;
    derivations = '';
    if isfield(opts, 'derivations')
        derivations = opts.derivations;
    end
end

if isempty(windows)
    throw(MException('Alakazam:Measure', ...
        ['No measurement windows have been defined, so there is nothing for Measure to do. ' ...
         'Please add at least one window (a name, a start/stop time, and a measure type).']));
end

%% Derived channels: evaluate any "let" statements and append them to EEG
% (channels x samples[ x bins]) before measuring, so a derivation like
% "let LRP = C3 - C4" is both measurable here and visible downstream (the
% ERP line plot, grand averages). TransTools.ApplyDerivations is a no-op when the
% block is empty; a name the data already has (an upstream DeriveChannels
% node's, say) is overwritten rather than added twice, and channels the
% block does not name are left as they are. See TransTools.ApplyDerivations.m.
EEG = TransTools.ApplyDerivations(EEG, derivations);

%% Compute
allLabels = string({EEG.chanlocs.labels});
nBins = size(EEG.data, 3); % bins on an average, TRIALS on epoched input
                           % (1 for an unbinned average, 2-D EEG.data)

measurements = cell(1, numel(windows));
for w = 1:numel(windows)
    measurements{w} = computeWindow(EEG, windows{w}, allLabels, nBins);
end

if perTrial
    % WHICH BIN EACH TRIAL BELONGS TO, recorded alongside the values,
    % because a per-trial value is useless for a group model without its
    % condition. Read through TransTools.BinMembership, the same membership
    % the rest of the app uses, so a trial in two bins (a combination bin
    % overlapping a base one) is reported as being in both rather than
    % silently assigned to the first.
    EEG.trialMeasurements = measurements;
    EEG.trialBinIndex = arrayfun(@(t) {TransTools.BinMembership.ofTrial(EEG, t)}, 1:nBins);
else
    EEG.measurements = measurements;
end
end

% ======================================================================= %
%  Per-window computation
% ======================================================================= %
function m = computeWindow(EEG, win, allLabels, nBins)
%COMPUTEWINDOW  Compute one window's amplitude/latency/area matrices, per
%   channel x bin. Each of the three matrices is filled only for the
%   measures it applies to (see this file's own header) and left NaN
%   otherwise; the CSV exporter picks the right one(s) from .measure:
%     Mean Amplitude          -> amplitude
%     Peak                    -> amplitude, latency
%     Peak Area               -> amplitude, latency, area
%     Integral                -> area   (signed trapz over the window)
%     Fractional Peak Latency -> latency
%     Fractional Area Latency -> latency
%   The scoring itself is TransTools.MeasureScorer, shared with erpScoreSME.
    % Resolve the Channels field into one output "channel" per spec (a
    % single electrode, or a "{A+B+C}" pool), and build each spec's virtual
    % waveform V(c,:,b): the electrode itself, or the NaN-tolerant mean of
    % a pool's members. Every measure below then runs on V exactly as it
    % used to run on a single electrode -- pooling is just "measure the
    % averaged waveform", invisible to the rest of the maths.
    specs = measureChannelSpecs(win.channels, allLabels, win.label);
    nCh = numel(specs);
    nSamp = size(EEG.data, 2);
    V = nan(nCh, nSamp, nBins);
    for c = 1:nCh
        mem = specs(c).members;
        if isscalar(mem)
            V(c, :, :) = EEG.data(mem, :, :);
        else
            V(c, :, :) = mean(EEG.data(mem, :, :), 1, 'omitnan');
        end
    end

    scoring = TransTools.MeasureScorer.prepare(win, EEG.times);

    amplitude = nan(nCh, nBins);
    latency   = nan(nCh, nBins);
    area      = nan(nCh, nBins);

    % Peak and peak-band Area may share the peak across channels via a
    % reference channel (Analyzer's "search peak in a reference channel"
    % mode); Fractional Peak Latency is always per-channel (each channel's
    % rise to a fraction of its own peak).
    usesRef = ~isempty(win.refChannel) && (strcmp(scoring.measure, 'peak') ...
        || (strcmp(scoring.measure, 'area') && scoring.useBand));
    if usesRef
        refIdx = find(allLabels == string(win.refChannel), 1);
        if isempty(refIdx)
            throw(MException('Alakazam:Measure', sprintf( ...
                'Window "%s" names a reference channel ("%s") that I''m afraid is not in this dataset.', ...
                win.label, win.refChannel)));
        end
    end

    for b = 1:nBins
        if usesRef
            shared = TransTools.MeasureScorer.findPeak(EEG.data(refIdx, scoring.lo:scoring.hi, b), scoring);
        end
        for c = 1:nCh
            if usesRef
                s = TransTools.MeasureScorer.score(V(c, :, b), EEG.times, scoring, shared);
            else
                s = TransTools.MeasureScorer.score(V(c, :, b), EEG.times, scoring);
            end
            amplitude(c, b) = s.amplitude;
            latency(c, b)   = s.latency;
            area(c, b)      = s.area;
        end
    end

    % The area mode is the window's for the fractional area latency too: it
    % selects which area is accumulated, and the SME has to read it from here.
    if strcmp(scoring.measure, 'area')
        outMode = scoring.areaMode;
        if scoring.useBand; outScope = 'band'; else; outScope = 'window'; end
    elseif strcmp(scoring.measure, 'fractional area latency')
        outMode = scoring.areaMode;
        outScope = '';
    else
        outMode = '';
        outScope = '';
    end

    m = struct('label', win.label, 'start', win.start, 'stop', win.stop, ...
        'measure', win.measure, 'polarity', win.polarity, 'width', scoring.width, ...
        'localPoints', scoring.localPoints, 'fraction', scoring.fraction, 'areaMode', outMode, ...
        'scope', outScope, 'baseline', scoring.baseline, 'refChannel', win.refChannel, ...
        'channels', {{specs.label}}, 'amplitude', amplitude, 'latency', latency, 'area', area);
end
