function spec = designedFilterFromObject(obj, name, dataSrate)
%DESIGNEDFILTERFROMOBJECT  A Filter Designer filter, as Filter stores it.
%   SPEC = designedFilterFromObject(OBJ, NAME, DATASRATE) turns OBJ, a digitalFilter
%   (what MATLAB's Filter Designer app exports to the workspace or a
%   MAT-file by default, and what designfilt returns) called NAME, into the
%   plain struct Filter keeps in its options, so that a replay, a template
%   or Apply to All needs neither the app nor the object:
%     .enabled      true
%     .kind         'fir' or 'iir'
%     .b            an FIR's coefficients, a row; [] for an IIR
%     .sos          an IIR's second-order sections, N x 6, its gain folded
%                   in (digitalFilter's own Coefficients); [] for an FIR
%     .srate        the sample rate it was designed for, in Hz
%     .normalised   true when it was designed in normalised frequency and
%                   .srate is the data's rate it was read at (below)
%     .order        its order (filtord)
%     .linearPhase  islinphase
%     .response     its FrequencyResponse ('lowpass', 'bandpass', ...)
%     .source       where it came from, for the record
%   How Filter applies it follows from these (designedFilterPasses).
%
%   An object of another class is refused.
%
%   A FILTER DESIGNED IN NORMALISED FREQUENCY is read at DATASRATE, the
%   sample rate of the data it is chosen for. Its coefficients do not depend
%   on a rate: its band edges are fractions of the Nyquist frequency, so a
%   normalised frequency w lies at w * DATASRATE / 2 Hz on those data. That
%   rate is then recorded as the filter's own, which fixes its band edges in
%   Hz: a replay onto data sampled at another rate is refused, as it is for a
%   filter designed in Hz, rather than letting a 50 Hz stopband slide to 25
%   Hz on data at half the rate. Without DATASRATE there is nothing to read
%   it at, and it is refused.
%
%   See also DESIGNEDFILTERPASSES, PICKDESIGNEDFILTER, FILTER, DESIGNFILT.
    if ~isa(obj, 'digitalFilter')
        throw(MException('Alakazam:Filter', ['Problem in Filter: "%s" is a %s, not a ' ...
            'digitalFilter. In the Filter Designer, export the filter as a Digital Filter ' ...
            'Object.'], name, class(obj)));
    end
    normalised = obj.NormalizedFrequency || ~(obj.SampleRate > 0);
    if normalised
        if nargin < 3 || isempty(dataSrate) || ~(dataSrate > 0)
            throw(MException('Alakazam:Filter', ['Problem in Filter: "%s" was designed in ' ...
                'normalised frequency, and there is no sample rate to read it at.'], name));
        end
        srate = double(dataSrate);
        source = sprintf('digitalFilter "%s", designed in normalised frequency and read at %g Hz', ...
            name, srate);
    else
        srate = double(obj.SampleRate);
        source = sprintf('digitalFilter "%s"', name);
    end
    kind = lower(char(string(obj.ImpulseResponse)));
    spec = struct('enabled', true, 'kind', kind, 'b', [], 'sos', [], ...
        'srate', srate, 'normalised', normalised, 'order', filtord(obj), ...
        'linearPhase', logical(islinphase(obj)), ...
        'response', char(string(obj.FrequencyResponse)), ...
        'source', source);
    if strcmp(kind, 'fir')
        spec.b = reshape(double(obj.Coefficients), 1, []);
    else
        spec.sos = double(obj.Coefficients);
    end
end
