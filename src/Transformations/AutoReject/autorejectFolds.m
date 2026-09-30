function folds = autorejectFolds(nEpochs, nFolds)
%AUTOREJECTFOLDS  The cross-validation folds autoreject uses: NFOLDS
%   contiguous blocks of the epochs, in order, no shuffling.
%
%   FOLDS = autorejectFolds(NEPOCHS, NFOLDS) returns a 1 x NFOLDS cell array,
%   each cell the row of epoch indices held out in that fold. The first
%   mod(NEPOCHS, NFOLDS) folds hold one epoch more than the rest.
%
%   This is scikit-learn's KFold(n_splits) without shuffling, which is what
%   autoreject makes of its default cv=10, reproduced exactly. It is also
%   what makes AutoReject deterministic: no random split, so a replay gives
%   the same thresholds.
%
%   See also AUTOREJECT, AUTOREJECTTHRESHOLDS, AUTOREJECTCONSENSUS.
    if nFolds < 2 || nFolds > nEpochs || nFolds ~= round(nFolds)
        throw(MException('Alakazam:AutoReject', ['I''m afraid %d-fold cross-validation ' ...
            'needs at least %d epochs to hold out, and there are %d.'], nFolds, nFolds, nEpochs));
    end
    sizes = repmat(floor(nEpochs / nFolds), 1, nFolds);
    extra = mod(nEpochs, nFolds);
    sizes(1:extra) = sizes(1:extra) + 1;
    lasts = cumsum(sizes);
    firsts = lasts - sizes + 1;
    folds = arrayfun(@(a, b) a:b, firsts, lasts, 'UniformOutput', false);
end
