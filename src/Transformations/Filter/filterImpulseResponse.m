function [t, h] = filterImpulseResponse(options, srate)
%FILTERIMPULSERESPONSE  The impulse response of Filter's global filters together.
%   [T, H] = filterImpulseResponse(OPTIONS, SRATE) returns the response of
%   the high-pass, low-pass and notch filters enabled in OPTIONS (the global
%   .highpass/.lowpass/.notch, each {enabled, freq, db}) applied one after
%   the other, as Filter applies them to data sampled at SRATE Hz. H is a
%   row vector and T its times in seconds, centred on 0: each filter is
%   applied zero-phase, so the response is symmetric about the impulse.
%   With no filter enabled, H is [1] at T = 0, the response of doing
%   nothing.
%
%   Filters applied in turn are one filter whose kernel is the convolution
%   of theirs, so this convolves the kernels designFilterKernel makes, the
%   same ones Filter applies. A setting Filter would refuse is refused here
%   with the same message.
%
%   The response is what a methods section should show beside the filter
%   settings (de Cheveigné & Nelken, 2019): how far one sample of data is
%   smeared, and what ringing a filter adds.
%
%   See also FILTER, DESIGNFILTERKERNEL, FILTERFREQUENCYRESPONSE, FILTERDIALOG.
    h = 1;
    for kind = {'highpass', 'high'; 'lowpass', 'low'; 'notch', 'notch'}'
        key = kind{1};
        if isfield(options, key) && isstruct(options.(key)) ...
                && isfield(options.(key), 'enabled') && logical(options.(key).enabled)
            b = designFilterKernel(kind{2}, options.(key).freq, options.(key).db, srate);
            h = conv(h, b);
        end
    end
    t = ((0:numel(h) - 1) - (numel(h) - 1) / 2) / srate;
end
