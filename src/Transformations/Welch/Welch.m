function [EEG, options] = Welch(input, varargin)
%% Welch  Averaged-periodogram power spectral density of a CONTINUOUS recording.
%
%   Splits the recording into overlapping segments, tapers each, and averages
%   their periodograms: Welch's method. The result is one calibrated spectrum
%   per channel, in units^2/Hz, whose integral over frequency equals the
%   signal's mean square.
%
%   WHY THIS IS A SEPARATE TRANSFORMATION FROM Fourier, and when NOT to use
%   it. On epoched data you already have Welch's method: Fourier gives one
%   periodogram per trial and Average means them per bin, which is exactly an
%   averaged periodogram with epochs as the segments. Measured against
%   theory, that route reduces the estimate's relative sd as 1/sqrt(K):
%   0.467 at 4 trials, 0.208 at 16, 0.138 at 64. It already buys what Welch
%   is for. Sub-segmenting inside a one-second epoch on top of that would
%   spend frequency resolution twice over, since four segments take a 1 s
%   epoch from 1 Hz bins to 2 Hz bins, at which point the delta band spans
%   1.5 of them.
%
%   A continuous recording is the opposite case. It is long enough to afford
%   many segments AND still resolve low frequencies, and it has no trials to
%   average over, so the segmentation has to come from somewhere. That is
%   what this provides, and it is why it refuses epoched input rather than
%   quietly duplicating the other route.
%
%   Signature (Alakazam transformation contract):
%     [EEG, options] = Welch(input)       % interactive dialog
%     [EEG, options] = Welch(input, opts) % replay a stored struct
%
%   Options:
%     - SegmentSeconds : segment length in seconds. Frequency resolution is
%       1/SegmentSeconds Hz, so this is the resolution/variance trade-off.
%     - Overlap : percentage overlap between consecutive segments (50 is the
%       usual choice for a Hanning taper).
%     - Window : taper name, see TransTools.WindowByName.
%
%   Output fields mirror Fourier's: .data (nchan x nfreq x 1), .freqs, .pnts,
%   .DataType = 'FrequencyDomain'. DataFormat is inherited unchanged, as
%   Fourier does, so AlakazamPlotter routes the result to FourierView.
%
%   See also FOURIER, AVERAGE, TRANSTOOLS.WINDOWBYNAME, PWELCH.

%% Guard
[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:Welch', varargin{:});

if ~isfield(input, 'DataFormat') || ~strcmpi(input.DataFormat, 'CONTINUOUS')
    throw(MException('Alakazam:Welch', '%s', sprintf( ...
        ['Problem in Welch: this needs a continuous recording (DataFormat = ' ...
         '"CONTINUOUS"), and not this dataset (DataFormat = "%s"). On epoched ' ...
         'data the same estimate is already available, with better frequency ' ...
         'resolution: run Fourier with Output = PSD and then Average, which ' ...
         'averages one periodogram per trial within each bin.'], ...
        char(string(input.DataFormat)))));
end

if interactive
    defaults = struct('SegmentSeconds', 4, 'Overlap', 50, 'Window', 'Hanning');
    seed = defaults;
    stored = TransformSettings.get('Welch');
    if ~isempty(stored)
        f = fieldnames(defaults);
        for si = 1:numel(f)
            if isfield(stored, f{si}) && ~isempty(stored.(f{si}))
                seed.(f{si}) = stored.(f{si});
            end
        end
    end

    windows = {'Hanning', 'Hamming', 'Bartlett', 'BlackmanHarris', 'BohmanWin', ...
               'NuttallWin', 'ParzenWin', 'RectWin', 'Triang', 'No'};

    options = TransformOptionsDialog( ...
        'title', 'Welch options', ...
        'Description', ['Power spectral density of a continuous recording, as the ' ...
            'average of overlapping tapered periodograms. Longer segments resolve ' ...
            'lower frequencies; more segments give a steadier estimate.'], ...
        'separator', 'Segmentation:', ...
        {'Segment length (s)'; 'SegmentSeconds'}, seed.SegmentSeconds, ...
        {'Overlap (%)'; 'Overlap'}, seed.Overlap, ...
        'separator', 'Window:', ...
        {'Taper'; 'Window'}, TransTools.PutFirst(windows, seed.Window));
    if isempty(options)
        % Cancelled. Both outputs must still be assigned: the callers request
        % both unconditionally, so leaving OPTIONS unset throws "Output
        % argument not assigned" instead of the clean cancel this means.
        EEG = [];
        options = [];
        return;
    end
    options.Name = 'Welch';
    TransformSettings.set('Welch', options);
else
    if ~isstruct(opts) || ~isfield(opts, 'SegmentSeconds')
        throw(MException('Alakazam:Welch', '%s', ...
            ['Welch has been asked to replay a previous run, but the stored settings ' ...
             'do not look like ones it produced (there is no .SegmentSeconds field).']));
    end
    options = opts;
end

%% Compute
EEG = input;
srate = input.srate;
[nchan, nsamp, ~] = size(input.data);

segLen = round(options.SegmentSeconds * srate);
if segLen < 8 || segLen > nsamp
    throw(MException('Alakazam:Welch', '%s', sprintf( ...
        ['Problem in Welch: a %g s segment is %d samples, and this recording is %d ' ...
         'samples (%.1f s). Choose a segment shorter than the recording and at ' ...
         'least 8 samples long.'], ...
        options.SegmentSeconds, segLen, nsamp, nsamp/srate)));
end

overlap = min(max(options.Overlap, 0), 99);
step = max(1, round(segLen * (1 - overlap/100)));
starts = 1:step:(nsamp - segLen + 1);
if isempty(starts)
    throw(MException('Alakazam:Welch', '%s', ...
        'Problem in Welch: that segment length and overlap yield no complete segments.'));
end

win = reshape(TransTools.WindowByName(options.Window, segLen), 1, []);
NFFT = 2^nextpow2(segLen);

% SAME CALIBRATION AS FOURIER'S 'PSD' OUTPUT, and for the same reasons.
% Dividing by srate*sum(w.^2) is the standard Welch normalisation, which
% removes the taper's effect on total power. Doubling the POWER of the folded
% bins (rather than the amplitude, then squaring it) is what makes the
% integral over frequency equal the signal's mean square; DC and Nyquist are
% left alone, having no mirror partner. Amplitude-doubling followed by
% squaring is exactly what leaves Power/PowerDens a factor 2 out.
scale = srate * sum(win .^ 2);

acc  = zeros(nchan, NFFT);
used = 0;
TransTools.progressbar;
for k = 1:numel(starts)
    TransTools.progressbar(k / numel(starts));
    seg = double(input.data(:, starts(k):starts(k)+segLen-1));
    if any(~isfinite(seg(:)))
        continue;   % a segment overlapping rejected or absent data
    end
    X   = fft(win .* seg, NFFT, 2);
    acc = acc + (abs(X) .^ 2) ./ scale;
    used = used + 1;
end
if used == 0
    throw(MException('Alakazam:Welch', '%s', ...
        ['Problem in Welch: every segment contained non-finite samples, so there ' ...
         'is nothing to average.']));
end

psd = acc / used;
psd(:, 2:NFFT/2) = 2 * psd(:, 2:NFFT/2);

EEG.data     = psd(:, 1:NFFT/2+1);
EEG.freqs    = srate/2 * linspace(0, 1, NFFT/2+1);
EEG.pnts     = NFFT/2+1;
EEG.trials   = 1;
EEG.DataType = 'FrequencyDomain';
EEG.WelchSegments = used;   % how many segments the estimate actually averaged
end
