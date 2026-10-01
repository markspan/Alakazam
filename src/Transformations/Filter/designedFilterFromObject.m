function spec = designedFilterFromObject(obj, name)
%DESIGNEDFILTERFROMOBJECT  A Filter Designer filter, as Filter stores it.
%   SPEC = designedFilterFromObject(OBJ, NAME) turns OBJ, a digitalFilter
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
%     .order        its order (filtord)
%     .linearPhase  islinphase
%     .response     its FrequencyResponse ('lowpass', 'bandpass', ...)
%     .source       where it came from, for the record
%   How Filter applies it follows from these (designedFilterPasses).
%
%   An object of another class is refused, and so is a digitalFilter
%   designed in normalised frequency: its cutoffs mean nothing without a
%   sample rate, and the step has to check that the data have the one it
%   was designed for.
%
%   See also DESIGNEDFILTERPASSES, PICKDESIGNEDFILTER, FILTER, DESIGNFILT.
    if ~isa(obj, 'digitalFilter')
        throw(MException('Alakazam:Filter', ['Problem in Filter: "%s" is a %s, not a ' ...
            'digitalFilter. In the Filter Designer, export the filter as a Digital Filter ' ...
            'Object.'], name, class(obj)));
    end
    if obj.NormalizedFrequency || ~(obj.SampleRate > 0)
        throw(MException('Alakazam:Filter', ['Problem in Filter: "%s" was designed in ' ...
            'normalised frequency, so it has no sample rate. Would you design it again with ' ...
            'the sample rate of the data?'], name));
    end
    kind = lower(char(string(obj.ImpulseResponse)));
    spec = struct('enabled', true, 'kind', kind, 'b', [], 'sos', [], ...
        'srate', double(obj.SampleRate), 'order', filtord(obj), ...
        'linearPhase', logical(islinphase(obj)), ...
        'response', char(string(obj.FrequencyResponse)), ...
        'source', sprintf('digitalFilter "%s"', name));
    if strcmp(kind, 'fir')
        spec.b = reshape(double(obj.Coefficients), 1, []);
    else
        spec.sos = double(obj.Coefficients);
    end
end
