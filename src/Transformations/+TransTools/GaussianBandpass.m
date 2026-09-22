function out = GaussianBandpass(data, srate, freq, fwhm)
%GAUSSIANBANDPASS  Zero-phase narrow-band filter: a Gaussian in the
%   frequency domain.
%
%   OUT = TransTools.GaussianBandpass(DATA, SRATE, FREQ, FWHM) filters DATA
%   along its SECOND dimension (samples), for any number of rows (channels)
%   and pages (trials), by multiplying its Fourier transform by a Gaussian
%   centred on FREQ Hz with a full width at half maximum of FWHM Hz, mirrored
%   onto the negative frequencies so the result is real, and transforming
%   back. The gain is 1 at FREQ and 0.5 at FREQ +/- FWHM/2.
%
%   WHY THIS FILTER. It is the one RESS was designed with (Cohen & Gulbinaite,
%   2017): no sharp edges, so no ringing in the time domain, no phase shift,
%   and a single parameter for its width. It is circular, so the edges of a
%   segment wrap into each other; filter a whole epoch and use a window away
%   from its ends, as RESSFilter does.
%
%   The reference code (filterFGx, github.com/mikexcohen/RESS) builds its
%   frequency axis with linspace(0, srate, n) rather than in steps of
%   srate / n, and converts the width with (2 pi - 1) / (4 pi), about 1%
%   narrower than the exact 1 / (2 sqrt(2 ln 2)). Both are corrected here.
%
%   See also TRANSTOOLS.RESSFILTER.
    n = size(data, 2);
    hz = (0:n - 1) * srate / n;
    hz(hz > srate / 2) = hz(hz > srate / 2) - srate;   % signed frequencies
    sigma = fwhm / (2 * sqrt(2 * log(2)));
    gain = exp(-0.5 * ((abs(hz) - freq) / sigma) .^ 2);
    out = real(ifft(fft(double(data), [], 2) .* gain, [], 2));
end
