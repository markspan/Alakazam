function [draws, nEqual, counts] = EqualisedDraws(EEG, trialSets, nDraws)
%EQUALISEDDRAWS  Random subsets of each bin's trials, all of one size.
%   [DRAWS, NEQUAL, COUNTS] = TransTools.EqualisedDraws(EEG, TRIALSETS, NDRAWS).
%   TRIALSETS holds each bin's trials (a cell per bin; a combination bin's is
%   empty). DRAWS{b} is a cell of trial-number vectors: NDRAWS random subsets of
%   NEQUAL trials, or the one set for the bin that has the fewest. NEQUAL is the
%   smallest number of trials any bin kept, and COUNTS what each bin kept: a
%   trial counts if any of its samples is finite, since rejection blanks a trial
%   to NaN and leaves it in its bin.
%
%   WHY. Coherence and phase locking are biased upwards by few trials: on
%   unrelated signals magnitude-squared coherence averages 1/N (.050 at 20
%   trials, .010 at 100) and inter-trial coherence sqrt(pi/(4N)). Two conditions
%   with different counts therefore differ for that reason alone. Keil et al.
%   (2022) and Bastos & Schoffelen (2016) advise equating the counts by randomly
%   deleting trials, and the second ideally by repeating the deletion, which is
%   what the several draws are for: the caller computes on each and averages.
%
%   THE SEED IS FIXED, so a replay reproduces the numbers, and the session's
%   random state is left as it was.
%
%   See also SPECTRALMEASURE, COMPUTECOHERENCEMAP, COMPUTECOHERENCETOPOGRAPHY.
    if nargin < 3 || isempty(nDraws)
        nDraws = 20;
    end
    nDraws = max(1, round(double(nDraws)));
    nBins = numel(trialSets);
    kept = cell(1, nBins);
    counts = zeros(1, nBins);
    for b = 1:nBins
        trials = reshape(trialSets{b}, 1, []);
        if isempty(trials)
            kept{b} = trials;
            continue;
        end
        stack = reshape(double(EEG.data(:, :, trials)), [], numel(trials));
        kept{b} = trials(any(isfinite(stack), 1));
        counts(b) = numel(kept{b});
    end
    nEqual = min(counts(counts > 0));
    if isempty(nEqual)
        nEqual = 0;
    end
    draws = TransTools.WithRestoredRng(@() drawAll(kept, counts, nEqual, nDraws));
end

function draws = drawAll(kept, counts, nEqual, nDraws)
    rng(20260101, 'twister');
    draws = cell(1, numel(kept));
    for b = 1:numel(kept)
        if counts(b) <= nEqual
            draws{b} = kept(b);
            continue;
        end
        draws{b} = cell(1, nDraws);
        for k = 1:nDraws
            draws{b}{k} = sort(kept{b}(randperm(counts(b), nEqual)));
        end
    end
end
