function [EEG, options] = Filter(input, varargin)
%% Filter  FIR windowed-sinc, zero-phase high-pass / low-pass / notch filtering,
%   and a filter designed in MATLAB's Filter Designer.
%
%   Each of the three filters is specified by a frequency and a dB rating
%   (the stopband attenuation); by default everything else -- the Kaiser
%   window, the filter order and the transition bandwidth -- is worked out
%   automatically, and with .auto false the transition band and the order
%   are set instead, each following from the other (filterDesign). The
%   design is EEGLAB's own windowed-sinc FIR (firfilt plugin): a
%   linear-phase Kaiser-windowed sinc whose stopband attenuation equals the
%   requested dB, applied with group-delay compensation so it is zero-phase
%   (no latency shift), and boundary-aware (it does not filter across
%   epoch/boundary discontinuities). FIR windowed-sinc, zero-phase, is the
%   EEGLAB/Luck best-practice for EEG/ERP filtering.
%
%   OPTIONS carries three sub-structs, each {enabled, freq (Hz), db} and,
%   optionally, {auto, transition (Hz), order} and, for the notch, width (Hz):
%       options.highpass  -- keep frequencies above freq
%       options.lowpass   -- keep frequencies below freq
%       options.notch     -- reject a narrow band around freq (line noise)
%   and, optionally, options.designed, a filter made in MATLAB's Filter
%   Designer app and stored as its coefficients (designedFilterFromObject).
%   It is applied after the other three, to every channel: a linear-phase
%   FIR of odd length once with firfilt, as the others are, and anything
%   else forward and backward with filtfilt, zero-phase, as EEGLAB's IIR
%   filtering and FieldTrip's 'twopass' default apply one
%   (designedFilterPasses). It must have been designed for the data's own
%   sample rate; another is refused.
%
%   EEG.etc.alz.filter records every filter applied, with each parameter of
%   its design.
%
%   Signature (Alakazam transformation contract):
%     [EEG, options] = Filter(input)        % interactive: open FilterDialog
%     [EEG, options] = Filter(input, opts)  % replay a stored options struct
%
%   A high-pass at a very low frequency needs a long FIR, so filter the
%   continuous recording before epoching; on data too short for the filter
%   this reports a friendly error rather than the raw firfilt one.
%
%   See also: FILTERDIALOG, FIRWS, FIRFILT (EEGLAB firfilt plugin).
[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:Filter', varargin{:});
if ~isfield(input, 'data') || ~isfield(input, 'srate') || isempty(input.srate)
    throw(MException('Alakazam:Filter', ...
        'Problem in Filter: this dataset has no data, or no sample rate, so there is nothing here for me to filter.'));
end

if interactive
    options = FilterDialog(input.srate, channelLabels(input), TransformSettings.get('Filter'));
    if isempty(options)
        EEG = [];   % cancelled
        return;
    end
    TransformSettings.set('Filter', options);
else
    options = opts;
end

EEG = input;
EEG.data = double(EEG.data);
applied = {};

if isfield(options, 'perChannel') && logical(options.perChannel)
    EEG = applyPerChannel(EEG, options.perChannelRows);
    applied{end + 1} = struct('filter', 'per channel', 'rows', options.perChannelRows);
else
    for kind = {'highpass', 'high'; 'lowpass', 'low'; 'notch', 'notch'}'
        if isEnabled(options, kind{1})
            [EEG, design] = applyFir(EEG, kind{2}, options.(kind{1}), []);
            applied{end + 1} = rmfield(design, {'fc', 'ftype'}); %#ok<AGROW>
        end
    end
end
if isEnabled(options, 'designed')
    [EEG, record] = applyDesigned(EEG, options.designed);
    applied{end + 1} = record;
end
EEG.etc.alz.filter = struct('applied', {applied});
end

% ======================================================================= %
function tf = isEnabled(options, name)
    tf = isfield(options, name) && isstruct(options.(name)) ...
        && isfield(options.(name), 'enabled') && logical(options.(name).enabled);
end

function EEG = applyPerChannel(EEG, rows)
%APPLYPERCHANNEL  Apply each channel's own high-pass / low-pass / notch.
%   Each filter has its own enable tickbox (the per-channel dialog's own
%   hpEnabled/lpEnabled/notchEnabled), independent of the other two on the
%   same channel -- unticking just Notch, say, still runs that channel's
%   own High-pass/Low-pass -- and a frequency of 0 also means that filter
%   is off, so a row from before these tickboxes existed still replays
%   correctly. Channels are matched by label, so a stored per-channel set
%   can be replayed on a dataset whose channels differ (rows naming absent
%   channels are skipped). FieldOr's default (true) covers a row saved
%   before a given tickbox existed (either the single-checkbox design's
%   .enabled, or no enable concept at all), which has no .hpEnabled/
%   .lpEnabled/.notchEnabled field of its own.
    labels = channelLabels(EEG);
    for r = 1:numel(rows)
        row = rows(r);
        c = find(strcmpi(labels, char(string(row.label))), 1);
        if isempty(c)
            continue;
        end
        if TransTools.FieldOr(row, 'hpEnabled', true) && row.hpFreq > 0
            EEG = applyFir(EEG, 'high', struct('freq', row.hpFreq, 'db', row.hpDb), c);
        end
        if TransTools.FieldOr(row, 'lpEnabled', true) && row.lpFreq > 0
            EEG = applyFir(EEG, 'low', struct('freq', row.lpFreq, 'db', row.lpDb), c);
        end
        if TransTools.FieldOr(row, 'notchEnabled', true) && row.notchFreq > 0
            EEG = applyFir(EEG, 'notch', struct('freq', row.notchFreq, 'db', row.notchDb), c);
        end
    end
end

function labels = channelLabels(EEG)
    if isfield(EEG, 'chanlocs') && ~isempty(EEG.chanlocs) && isfield(EEG.chanlocs, 'labels')
        labels = {EEG.chanlocs.labels};
    else
        labels = arrayfun(@(i) sprintf('ch%d', i), 1:size(EEG.data, 1), 'UniformOutput', false);
    end
end

function [EEG, design] = applyFir(EEG, type, spec, chanind)
%APPLYFIR  Design a Kaiser windowed-sinc FIR for one filter (from SPEC's
%   freq and db, and its auto/transition/order/width where given, see
%   filterDesign) and apply it zero-phase with EEGLAB's firfilt. CHANIND (a
%   channel index, or [] for all channels) limits the filter to one channel
%   for per-channel mode. DESIGN is filterDesign's record of it.
    [b, design] = designFilterKernel(type, spec.freq, spec.db, EEG.srate, spec);

    if numel(b) > size(EEG.data, 2)
        throw(MException('Alakazam:Filter', sprintf([ ...
            'Problem in Filter: the %s filter needs %d samples, but this data is only %d long. ' ...
            'Filtering the continuous recording before epoching would help, or you could raise the cutoff or lower the dB.'], ...
            type, numel(b), size(EEG.data, 2))));
    end
    EEG = firfiltBins(EEG, b, chanind);
end

function EEG = firfiltBins(EEG, b, chanind)
%FIRFILTBINS  Apply the designed FIR with firfilt, once per bin.
%   An averaged dataset -- one subject's Average, or a GrandAverage -- keeps
%   one waveform per bin in the third dimension of EEG.data, but still
%   reports EEG.trials == 1. firfilt reads that as continuous data and
%   filters EEG.pnts columns, which for an nchan x npnts x nbin array is bin
%   1 alone, leaving every later bin untouched. So hand firfilt each bin
%   separately, as genuinely 2-D data. That is also the behaviour we want:
%   no filtering across a bin boundary, exactly as firfilt keeps epochs
%   apart. Epoched data (trials > 1) goes straight through -- there the
%   third dimension is trials, which firfilt already handles itself.
    nbin = size(EEG.data, 3);
    if nbin <= 1 || TransTools.FieldOr(EEG, 'trials', 1) > 1
        EEG = firfiltOne(EEG, b, chanind);
        return;
    end

    filtered = EEG.data;
    for k = 1:nbin
        binEEG        = EEG;
        binEEG.data   = EEG.data(:, :, k);
        binEEG.trials = 1;
        binEEG.nbchan = size(EEG.data, 1);
        binEEG.pnts   = size(EEG.data, 2);
        % An averaged dataset still carries the events of the epoched
        % dataset it was built from, whose latencies index a different (much
        % longer) timeline. firfilt is boundary-aware, so leaving them in
        % place would let a stale boundary event split a bin at a
        % meaningless sample; each bin is one continuous waveform.
        binEEG.event  = struct('type', {}, 'latency', {});
        binEEG        = firfiltOne(binEEG, b, chanind);
        filtered(:, :, k) = binEEG.data;
    end
    EEG.data = filtered;
end

function [EEG, record] = applyDesigned(EEG, spec)
%APPLYDESIGNED  Apply a filter made in the Filter Designer, to every channel:
%   once with firfilt when it is a linear-phase FIR of odd length, forward
%   and backward with filtfilt otherwise (designedFilterPasses). It has to
%   have been designed for this sample rate; its cutoffs are in Hz.
    if abs(double(spec.srate) - double(EEG.srate)) > 1e-6
        throw(MException('Alakazam:Filter', sprintf([ ...
            'Problem in Filter: the designed filter (%s) was made for a sample rate of %g Hz, ' ...
            'and this dataset is sampled at %g Hz, so its cutoffs would land elsewhere. Would ' ...
            'you design it again for %g Hz?'], spec.source, spec.srate, EEG.srate, EEG.srate)));
    end
    passes = designedFilterPasses(spec);
    record = struct('filter', 'designed', 'source', spec.source, 'kind', spec.kind, ...
        'order', spec.order, 'response', spec.response, 'srate', spec.srate, 'passes', passes, ...
        'shortStretches', 0);
    if passes == 1
        b = reshape(double(spec.b), 1, []);
        if numel(b) > size(EEG.data, 2)
            throw(MException('Alakazam:Filter', sprintf([ ...
                'Problem in Filter: the designed filter needs %d samples, but this data is only ' ...
                '%d long.'], numel(b), size(EEG.data, 2))));
        end
        EEG = firfiltBins(EEG, b, []);
        return;
    end
    [EEG, record.shortStretches] = twoPass(EEG, spec);
end

function [EEG, nShort] = twoPass(EEG, spec)
%TWOPASS  filtfilt over every stretch of data that may be filtered as one:
%   each epoch, or each bin of an average, and in a continuous recording the
%   stretches between boundary events, as firfilt splits them. Within a
%   stretch, a channel's rejected samples (NaN) split it again, so that one
%   rejected stretch does not, through the filter's infinite response, take
%   the rest of the recording with it. A run too short for filtfilt (three
%   times the filter's order) is left NaN, and the number of such runs is
%   returned.
    if strcmp(spec.kind, 'fir')
        num = reshape(double(spec.b), 1, []);
    else
        num = double(spec.sos);
    end
    minLength = 3 * max(1, double(spec.order)) + 1;
    [nChan, nPnts, nPages] = size(EEG.data);
    if nPages == 1 && TransTools.FieldOr(EEG, 'trials', 1) <= 1
        edges = findboundaries(TransTools.FieldOr(EEG, 'event', struct([])));
        edges = edges(edges >= 1 & edges <= nPnts);
        edges = unique([edges, nPnts + 1]);
    else
        edges = [1, nPnts + 1];
    end
    if ~any(diff(edges) >= minLength)
        throw(MException('Alakazam:Filter', sprintf([ ...
            'Problem in Filter: the designed filter needs stretches of at least %d samples, and ' ...
            'this data has none that long.'], minLength)));
    end
    nShort = 0;
    for page = 1:nPages
        for e = 1:numel(edges) - 1
            span = edges(e):edges(e + 1) - 1;
            for c = 1:nChan
                x = EEG.data(c, span, page);
                finite = isfinite(x);
                starts = find(diff([false, finite]) == 1);
                stops  = find(diff([finite, false]) == -1);
                for r = 1:numel(starts)
                    stretch = starts(r):stops(r);
                    if numel(stretch) < minLength
                        x(stretch) = NaN;
                        nShort = nShort + 1;
                    else
                        x(stretch) = filtfilt(num, 1, x(stretch).').';
                    end
                end
                EEG.data(c, span, page) = x;
            end
        end
    end
end

function EEG = firfiltOne(EEG, b, chanind)
%FIRFILTONE  A single firfilt call, over every channel or just CHANIND.
    if isempty(chanind)
        EEG = firfilt(EEG, b);
    else
        EEG = firfilt(EEG, b, [], chanind);
    end
end