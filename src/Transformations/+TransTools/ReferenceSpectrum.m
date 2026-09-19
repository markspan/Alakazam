function [spec, specFreqs, peakHz] = ReferenceSpectrum(input, refIdx)
%REFERENCESPECTRUM  The reference channel's own amplitude spectrum, per bin,
%   over a range far wider than the coherence band.
%
%   [SPEC, SPECFREQS, PEAKHZ] = ReferenceSpectrum(INPUT, REFIDX) returns, for
%   an EPOCHED EEG struct, the amplitude spectrum of channel REFIDX averaged
%   over each bin's trials.
%
%   WHY THIS EXISTS. The coherence map only covers the band the analyst chose
%   (52 to 68 Hz for the RIFT settings of Dimigen et al. 2025), and its
%   REFPOWER only that band too. A condition tagged outside the band, a 30 Hz
%   SSVEP among 60 Hz RIFT conditions, is therefore invisible to it: the
%   reference's strongest frequency INSIDE the band is reported as the tag,
%   which is a 1% residual, not the tag. The reference's full spectrum is what
%   shows that (a photodiode measures the flicker directly, so its spectrum is
%   the ground truth for what was displayed, Arora et al. 2026).
%
%   SPEC is nCells x nBins, in the units of the reference (a root-mean-square
%   amplitude over trials of a Hann-tapered, mean-removed FFT, scaled so a
%   sinusoid of amplitude A reads A). SPECFREQS is the cell centres. To keep
%   the exported file small the spectrum is reduced to cells of 0.25 Hz, or
%   the FFT resolution if that is coarser, by taking the maximum within each
%   cell, which keeps a narrow peak at its full height. The range is 0 Hz to
%   the lower of Nyquist and 150 Hz.
%
%   PEAKHZ (1 x nBins) is the exact FFT frequency of the strongest component
%   at 5 Hz or above, the tag for a flicker reference. Below 5 Hz sit DC,
%   drift and stimulus-onset transients that are not a tag. Combination bins
%   and bins with no trials are NaN in both outputs.
%
%   See also COMPUTECOHERENCEMAP, COHERENCEMAP, EXPORTCOHERENCECSVS.
    srate = input.srate;
    nT = size(input.data, 2);
    nBins = numel(input.bindesc);

    freqs = (0:floor(nT / 2)) * srate / nT;
    cellWidth = max(0.25, srate / nT);
    keep = find(freqs <= min(srate / 2, 150));
    cellOf = round(freqs(keep) / cellWidth) + 1;
    nCells = max(cellOf);
    specFreqs = (0:nCells - 1) * cellWidth;

    taper = 0.5 - 0.5 * cos(2 * pi * (0:nT - 1) / max(1, nT - 1));
    scale = 2 / sum(taper);
    usable = freqs(keep) >= 5;

    spec = nan(nCells, nBins);
    peakHz = nan(1, nBins);
    isCombo = false(1, nBins);
    if isfield(input.bindesc, 'combo')
        isCombo = ~cellfun(@isempty, {input.bindesc.combo});
    end

    for b = find(~isCombo)
        trials = input.bindesc(b).trials;
        if isempty(trials)
            continue;
        end
        summed = zeros(1, numel(keep));
        for tr = trials(:)'
            x = double(input.data(refIdx, :, tr));
            x = (x(:).' - mean(x(:))) .* taper;
            F = fft(x);
            summed = summed + abs(F(keep)).^2;
        end
        amp = sqrt(summed / numel(trials)) * scale;
        spec(:, b) = accumarray(cellOf(:), amp(:), [nCells 1], @max, NaN);

        candidates = amp;
        candidates(~usable) = -Inf;
        [top, at] = max(candidates);
        if isfinite(top) && top > 0
            peakHz(b) = freqs(keep(at));
        end
    end
end
