function [f, gain] = filterFrequencyResponse(options, srate)
%FILTERFREQUENCYRESPONSE  The frequency response of Filter's global filters together.
%   [F, GAIN] = filterFrequencyResponse(OPTIONS, SRATE) returns the gain of
%   the high-pass, low-pass and notch filters enabled in OPTIONS (the global
%   .highpass/.lowpass/.notch, each {enabled, freq, db}) applied one after
%   the other, as Filter applies them to data sampled at SRATE Hz. F is a
%   row vector of frequencies in Hz running from 0 to the Nyquist frequency
%   (SRATE / 2), both included, and GAIN the matching row vector of linear
%   magnitudes: 1 passes a frequency unchanged, 0.5 is the -6 dB point at
%   which a windowed-sinc filter's cutoff is defined, and 0 removes it.
%   With no filter enabled, GAIN is 1 everywhere, the response of doing
%   nothing.
%
%   The gain is the magnitude of the Fourier transform of the combined
%   impulse response (filterImpulseResponse), which is built from the same
%   kernels Filter applies, so it is the response of the filtering that is
%   done. Filter applies each kernel zero-phase, so the gain is the whole
%   effect: no frequency is shifted in time. A setting Filter would refuse
%   is refused here with the same message.
%
%   RESOLUTION. The transform is zero-padded to OVERSAMPLE times the length
%   of the impulse response, and to at least MIN_POINTS, so the points are
%   spaced much more finely than the narrowest transition band. A plot of F
%   against GAIN therefore shows the shape of each transition band when
%   zoomed in on it, not just a step between two samples.
%
%   Together with the impulse response it is the description of a filter a
%   methods section should give (de Cheveigné & Nelken, 2019): which
%   frequencies it passes, where it cuts off, and how much it attenuates.
%
%   See also FILTER, FILTERIMPULSERESPONSE, DESIGNFILTERKERNEL, FILTERDIALOG.
    OVERSAMPLE = 8;      % transform points per sample of the impulse response
    MIN_POINTS = 4096;   % a short response still gets a smooth curve

    [~, h] = filterImpulseResponse(options, srate);
    nfft = 2 ^ nextpow2(max(OVERSAMPLE * numel(h), MIN_POINTS));

    % Along the second dimension explicitly: with no filter enabled H is the
    % scalar 1, which fft would otherwise pad into a column.
    spectrum = fft(h, nfft, 2);
    gain = abs(spectrum(1:nfft / 2 + 1));
    f = (0:nfft / 2) * (srate / nfft);
end
