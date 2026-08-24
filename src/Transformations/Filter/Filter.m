function [EEG, options] = Filter(input, varargin)
%% Filter  FIR windowed-sinc, zero-phase high-pass / low-pass / notch filtering.
%
%   Each of the three filters is specified by just a frequency and a dB
%   rating (the stopband attenuation); everything else -- the Kaiser window,
%   the filter order and the transition bandwidth -- is worked out
%   automatically. The design is EEGLAB's own windowed-sinc FIR (firfilt
%   plugin): a linear-phase Kaiser-windowed sinc whose stopband attenuation
%   equals the requested dB, applied with group-delay compensation so it is
%   zero-phase (no latency shift), and boundary-aware (it does not filter
%   across epoch/boundary discontinuities). FIR windowed-sinc, zero-phase, is
%   the EEGLAB/Luck best-practice for EEG/ERP filtering.
%
%   OPTIONS carries three sub-structs, each {enabled, freq (Hz), db}:
%       options.highpass  -- keep frequencies above freq
%       options.lowpass   -- keep frequencies below freq
%       options.notch     -- reject a narrow band around freq (line noise)
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

if isfield(options, 'perChannel') && logical(options.perChannel)
    EEG = applyPerChannel(EEG, options.perChannelRows);
else
    if isEnabled(options, 'highpass')
        EEG = applyFir(EEG, 'high', options.highpass.freq, options.highpass.db, []);
    end
    if isEnabled(options, 'lowpass')
        EEG = applyFir(EEG, 'low', options.lowpass.freq, options.lowpass.db, []);
    end
    if isEnabled(options, 'notch')
        EEG = applyFir(EEG, 'notch', options.notch.freq, options.notch.db, []);
    end
end
end

% ======================================================================= %
function tf = isEnabled(options, name)
    tf = isfield(options, name) && isstruct(options.(name)) ...
        && isfield(options.(name), 'enabled') && logical(options.(name).enabled);
end

function EEG = applyPerChannel(EEG, rows)
%APPLYPERCHANNEL  Apply each channel's own high-pass / low-pass / notch (a
%   frequency of 0 means that filter is off for that channel). Channels are
%   matched by label, so a stored per-channel set can be replayed on a dataset
%   whose channels differ (rows naming absent channels are skipped).
    labels = channelLabels(EEG);
    for r = 1:numel(rows)
        row = rows(r);
        c = find(strcmpi(labels, char(string(row.label))), 1);
        if isempty(c)
            continue;
        end
        if row.hpFreq > 0
            EEG = applyFir(EEG, 'high', row.hpFreq, row.hpDb, c);
        end
        if row.lpFreq > 0
            EEG = applyFir(EEG, 'low', row.lpFreq, row.lpDb, c);
        end
        if row.notchFreq > 0
            EEG = applyFir(EEG, 'notch', row.notchFreq, row.notchDb, c);
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

function EEG = applyFir(EEG, type, freq, db, chanind)
%APPLYFIR  Design a Kaiser windowed-sinc FIR for one filter (from FREQ and DB)
%   and apply it zero-phase with EEGLAB's firfilt. CHANIND (a channel index, or
%   [] for all channels) limits the filter to one channel for per-channel mode.
    srate = EEG.srate;
    nyq   = srate / 2;
    freq  = double(freq);
    db    = double(db);
    if ~(freq > 0 && freq < nyq)
        throw(MException('Alakazam:Filter', sprintf( ...
            'Problem in Filter: the %s frequency (%.4g Hz) needs to sit between 0 and the Nyquist frequency (%.4g Hz) -- would you choose a value in that range?', ...
            type, freq, nyq)));
    end
    if ~(db > 0)
        throw(MException('Alakazam:Filter', ...
            'Problem in Filter: the %s dB rating needs to be a positive number (the stopband attenuation) -- could you check that value?', type));
    end

    dev  = 10 ^ (-db / 20);          % stopband deviation from the dB rating
    beta = kaiserbeta(dev);          % EEGLAB firfilt helper

    switch type
        case 'high'
            df    = min(max(freq * 0.25, 1), freq * 0.9);
            fc    = freq / nyq;
            ftype = 'high';
        case 'low'
            df    = min(max(freq * 0.25, 2), (nyq - freq) * 0.9);
            fc    = freq / nyq;
            ftype = '';              % lowpass (no type token)
        case 'notch'
            hbw = 1;                 % half stop-band width (Hz)
            df  = 1;                 % transition bandwidth (Hz)
            if freq - hbw <= 0 || freq + hbw >= nyq
                throw(MException('Alakazam:Filter', ...
                    'Problem in Filter: I''m afraid the notch frequency (%.4g Hz) sits too close to 0 or to Nyquist for a %.4g Hz notch.', ...
                    freq, 2 * hbw));
            end
            fc    = [(freq - hbw) / nyq, (freq + hbw) / nyq];
            ftype = 'stop';
    end

    m = firwsord('kaiser', srate, df, dev);   % order from transition bw + deviation
    m = m + mod(m, 2);                         % firws needs an even order
    w = windows('kaiser', m + 1, beta);

    if m + 1 > size(EEG.data, 2)
        throw(MException('Alakazam:Filter', sprintf([ ...
            'Problem in Filter: the %s filter needs %d samples, but this data is only %d long. ' ...
            'Filtering the continuous recording before epoching would help, or you could raise the cutoff or lower the dB.'], ...
            type, m + 1, size(EEG.data, 2))));
    end

    if isempty(ftype)
        b = firws(m, fc, w);
    else
        b = firws(m, fc, ftype, w);
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

function EEG = firfiltOne(EEG, b, chanind)
%FIRFILTONE  A single firfilt call, over every channel or just CHANIND.
    if isempty(chanind)
        EEG = firfilt(EEG, b);
    else
        EEG = firfilt(EEG, b, [], chanind);
    end
end
