function [starts, centres] = FrameStarts(nSamples, win)
%FRAMESTARTS  Where the analysis frames of a sliding-window coherence begin.
%
%   [STARTS, CENTRES] = TransTools.FrameStarts(NSAMPLES, WIN) returns the first
%   sample of every frame of WIN samples slid across NSAMPLES with 75% overlap
%   (a step of WIN/4), and the sample each is centred on.
%
%   ONE DEFINITION, so that the coherence map and the coherence a
%   SpectralMeasure or CoherenceTopography reports are averaged over the same
%   frames. CoherenceMap draws frames on the FFT grid and TransTools.FrameCoherence
%   reads a single frequency exactly, but both slide the same window by the same
%   step, which is what makes their numbers comparable.
%
%   A signal shorter than one window gives one frame at sample 1.
%
%   See also COMPUTECOHERENCEMAP, TRANSTOOLS.FRAMECOHERENCE.
    step = max(1, round(win / 4));
    starts = 1:step:(nSamples - win + 1);
    if isempty(starts)
        starts = 1;
    end
    centres = starts + floor(win / 2);
end
