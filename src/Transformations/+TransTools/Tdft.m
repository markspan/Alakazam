function X = Tdft(V, f, t, tapers)
%TDFT  Raw tapered single-frequency DFT of V (nsamp x nT) at frequency F,
%   one row per taper: X(k, :) = sum_t V .* taper_k .* exp(-i2*pi*f*t).
%   TAPERS is nsamp x K; a single taper may be given as a vector in either
%   orientation and is taken as one column. T is the time axis in seconds,
%   evenly spaced, and sets where the phase is measured from: a cosine
%   cos(2*pi*f*t + phi) has phase phi, so T = EEG.times / 1000 measures it
%   from the event (time zero), as FieldTrip does, and T = (0:n-1) / srate
%   from the first sample.
%
%   THE TRANSFORM IS THE SIGNAL PROCESSING TOOLBOX'S. goertzel evaluates the
%   DFT at any frequency, off the fs/N grid too (a fractional index), which
%   is what a harmonic or intermodulation row needs; this only turns F into
%   goertzel's index and moves the phase from the first sample to T's zero.
%   It agrees with the sum written out above to about 1e-13 relative.
%
%   LEFT UNNORMALISED ON PURPOSE. SpectralMeasure applies taper 0's coherent
%   gain itself for the calibrated amplitude, while SNR / ITC / coherence use
%   magnitudes or ratios in which the taper scale cancels -- which is also
%   what makes the zero-sum higher DPSS tapers safe to include here.
%
%   Shared by SpectralMeasure (K tapers) and ComputeCoherenceTopography (one
%   Hann taper); the single-taper case is just K = 1, returning a 1 x nT row.
%
%   See also SPECTRALMEASURE, COMPUTECOHERENCETOPOGRAPHY, GOERTZEL.
    if isvector(tapers)
        tapers = tapers(:);
    end
    nsamp = size(V, 1);
    nT = size(V, 2);
    K = size(tapers, 2);
    dt = 1;
    if numel(t) > 1
        dt = t(2) - t(1);
    end
    index = f * nsamp * dt + 1;          % goertzel's (fractional) DFT index
    rotation = exp(-1i * 2 * pi * f * t(1));
    % A REJECTED TRIAL IS NaN, and goertzel refuses non-finite input, so only
    % the intact columns are transformed; a column with any NaN stays NaN, as
    % it did when this was a sum, and the callers' 'omitnan' leaves it out.
    X = complex(nan(K, nT, class(V)));
    intact = all(isfinite(V), 1);
    if any(intact)
        for k = 1:K
            X(k, intact) = goertzel(V(:, intact) .* tapers(:, k), index) * rotation;
        end
    end
end
