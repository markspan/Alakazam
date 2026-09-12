function X = Tdft(V, f, t, tapers)
%TDFT  Raw tapered single-frequency DFT of V (nsamp x nT) at frequency F,
%   one row per taper: X(k, :) = sum_t V .* taper_k .* exp(-i2*pi*f*t).
%   TAPERS is nsamp x K; a single taper may be given as a vector in either
%   orientation and is taken as one column. T is the time axis in seconds.
%
%   LEFT UNNORMALISED ON PURPOSE. SpectralMeasure applies taper 0's coherent
%   gain itself for the calibrated amplitude, while SNR / ITC / coherence use
%   magnitudes or ratios in which the taper scale cancels -- which is also
%   what makes the zero-sum higher DPSS tapers safe to include here.
%
%   Previously reimplemented in SpectralMeasure.m (K tapers) and
%   TransTools.ComputeCoherenceTopography (one Hann taper, whose own copy
%   said "the same tapered single-frequency DFT SpectralMeasure.m uses");
%   consolidated here. The single-taper case is just K = 1, returning the
%   1 x nT row those callers already annotated and expected.
%
%   ONE FORMULATION, NOT TWO. The coherence copy summed elementwise
%   (sum(V .* kern, 1)) where the spectral one used this matrix product.
%   They agree to about 1e-15 relative -- floating-point summation order,
%   nothing more -- and measured directly before consolidating: identical
%   to the last bit against the spectral copy, and 6e-14 absolute against
%   the coherence copy on data of magnitude ~10. Coherence is a ratio of
%   these quantities, so that difference cannot reach a reported figure.
%   Keeping both formulations to preserve each caller's last bit would have
%   meant two code paths inside the function whose whole point is that there
%   is one.
%
%   See also SPECTRALMEASURE, TRANSTOOLS.COMPUTECOHERENCETOPOGRAPHY.
    if isvector(tapers)
        tapers = tapers(:);
    end
    e = exp(-1i * 2 * pi * f * t(:));    % nsamp x 1
    X = (tapers .* e).' * V;             % K x nT
end
