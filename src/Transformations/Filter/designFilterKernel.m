function [b, d] = designFilterKernel(type, freq, db, srate, spec)
%DESIGNFILTERKERNEL  The FIR kernel Filter applies for one filter.
%   B = designFilterKernel(TYPE, FREQ, DB, SRATE) designs a Kaiser-windowed
%   sinc (EEGLAB's firfilt plugin: kaiserbeta, firwsord, windows, firws) for
%   TYPE 'high', 'low' or 'notch' at FREQ Hz with DB of stopband attenuation,
%   for data sampled at SRATE Hz, its transition band and order chosen
%   automatically. B is a row vector of odd length (an even order),
%   symmetric, so applying it with its group delay compensated, as firfilt
%   does, is zero-phase.
%
%   B = designFilterKernel(TYPE, FREQ, DB, SRATE, SPEC) takes the rest of the
%   design from SPEC: .auto, .transition, .order and, for a notch, .width
%   (see filterDesign, which works out every parameter). [B, D] also returns
%   them, D being filterDesign's struct.
%
%   ONE DESIGN, THREE READERS. Filter applies these kernels, and FilterDialog
%   shows their parameters (filterDesign) and plots their combined frequency
%   response (filterFrequencyResponse), so what the dialog shows is exactly
%   what the step does.
%
%   See also FILTERDESIGN, FILTER, FILTERFREQUENCYRESPONSE, FIRWS, FIRWSORD.
    if nargin < 5 || ~isstruct(spec)
        spec = struct();
    end
    spec.freq = freq;
    spec.db = db;
    d = filterDesign(type, spec, srate);

    w = windows('kaiser', d.order + 1, d.beta);
    if isempty(d.ftype)
        b = firws(d.order, d.fc, w);
    else
        b = firws(d.order, d.fc, d.ftype, w);
    end
    b = reshape(b, 1, []);
end
