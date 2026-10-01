function passes = designedFilterPasses(spec)
%DESIGNEDFILTERPASSES  How Filter applies a designed filter: 1 or 2 passes.
%   PASSES = designedFilterPasses(SPEC) is 1 for a linear-phase FIR of odd
%   length (a type I filter, symmetric about a whole sample), which firfilt
%   applies once with its group delay compensated, zero-phase, exactly as
%   Filter applies its own kernels. It is 2 for anything else, an IIR or an
%   FIR without a whole-sample delay, which is applied forward and backward
%   (filtfilt), as EEGLAB's IIR filtering and FieldTrip's 'twopass' default
%   apply one: zero-phase, but with the magnitude response squared, so the
%   stopband attenuation and the passband ripple both double in dB.
%
%   SPEC is designedFilterFromObject's struct.
%
%   See also DESIGNEDFILTERFROMOBJECT, FILTER, FILTFILT, FIRFILT.
    passes = 2;
    b = reshape(double(spec.b), 1, []);   % a template's JSON brings a row back as a column
    if strcmp(spec.kind, 'fir') && logical(spec.linearPhase) && mod(numel(b), 2) == 1 ...
            && isequal(b, fliplr(b))
        passes = 1;
    end
end
