function EEG = ClearForeignResultFields(EEG, varargin)
%CLEARFOREIGNRESULTFIELDS  Drop another transformation's own result field(s)
%   from EEG, if present.
%
%   EEG = CLEARFOREIGNRESULTFIELDS(EEG, NAME1, NAME2, ...) removes every
%   field in each named group below, when EEG carries it. Call this right
%   after EEG = input and before adding this transformation's OWN result
%   fields, once for every sibling named in the comment at the top of the
%   caller.
%
%   WHY THIS EXISTS. AlakazamPlotter.plotEpoched picks a view for an EPOCHED
%   result by "eeg.id matches this transformation's name, OR this result
%   field is present" -- the field fallback exists so a grand average (whose
%   id gets renamed to the grand average's own name, see
%   Alakazam.saveGrandAverage) still routes to the right view. TimeFrequency
%   (.ersp), CoherenceMap (.coherence), CoherenceTopography (.CohTopoValues),
%   CrossCorrelation (.xcorr) and Covariance (.covariance) all use this
%   pattern, checked in that order. Every one of these transformations does
%   EEG = input, then adds only its own field(s) -- so chaining one onto
%   another's result (an entirely normal workflow: they all just need
%   EPOCHED data, most with a reference channel) used to leave the final
%   struct carrying BOTH transformations' fields. Since the check is
%   evaluated top to bottom and stops at the first match, a result left
%   carrying an EARLIER-checked sibling's stale, non-empty field renders
%   with that sibling's view instead of its own -- reported directly for
%   CoherenceMap/CoherenceTopography: "coherence map and coherence
%   topography look to give the same plots." See CoherenceChainingTest.m
%   for that specific case, and the *ChainingTest.m files alongside it for
%   the others this was found to also reach.
%
%   Only a transformation checked EARLIER in plotEpoched's elseif chain than
%   the caller needs clearing here: the caller's own id always matches its
%   own branch before a LATER sibling's field check is even reached, so
%   nothing later needs guarding against. (SpectralMeasure is id-only, no
%   field fallback of its own, so nothing needs to clear ITS fields --  but
%   it still needs to clear an inherited .ersp, since TimeFrequency's check
%   runs before SpectralMeasure's own id check.)
%
%   See also ALAKAZAMPLOTTER, COHERENCEMAP, COHERENCETOPOGRAPHY,
%   CROSSCORRELATION, COVARIANCE, SPECTRALMEASURE, TIMEFREQUENCY.
    groups = struct( ...
        'TimeFrequency',       {{'ersp', 'freqs'}}, ...
        'CoherenceMap',        {{'coherence', 'cohFreqs', 'cohTimes', 'cohRef', 'cohMethod'}}, ...
        'CoherenceTopography', {{'CohTopoValues', 'CohTopoChanlocs', 'CohTopoDrawn', 'CohTopoFreqs', ...
                                  'CohTopoRef', 'CohTopoLimit', 'CohTopoRefAmp', 'CohTopoAmpFreqs', ...
                                  'CohTopoBins', 'CohTopoBinLabels'}}, ...
        'CrossCorrelation',    {{'xcorr', 'xcorrSE', 'xcorrLags', 'xcorrRef', 'xcorrLabels', ...
                                  'xcorrBinLabels', 'xcorrTrials', 'xcorrPeakR', 'xcorrPeakLagMs', ...
                                  'xcorrWindowMs'}}, ...
        'Covariance',          {{'covariance', 'covLabels', 'covBinLabels', 'covStatistic', ...
                                  'covShrinkage', 'covN', 'covDropped', 'covWindowMs'}});

    for k = 1:numel(varargin)
        for f = groups.(varargin{k})
            if isfield(EEG, f{1})
                EEG = rmfield(EEG, f{1});
            end
        end
    end
end
