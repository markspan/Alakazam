function EEG = GrandAverage(sourceFiles, weighted)
%GRANDAVERAGE  Combine several subjects' Average datasets into one grand
%   average.
%
%   EEG = GRANDAVERAGE(SOURCEFILES, WEIGHTED) loads each file in
%   SOURCEFILES (a cell array of paths to Averaged .mat datasets, each
%   holding a variable "EEG"), matches their bins by label, and combines
%   them:
%
%     - WEIGHTED = false: every subject counts equally, regardless of its
%       own trial count -- the standard ERP grand-average convention. The
%       reported standard error is the across-subject SEM: the standard
%       deviation of the subjects' own per-bin means, divided by
%       sqrt(nSubjects).
%     - WEIGHTED = true: the MEAN is a trial-count-weighted average
%       instead (a subject with more trials counts more, matching
%       ERPLAB's weighted grand-average option). The reported SEM is
%       still the plain across-subject SEM either way, since that answers
%       "how much do subjects vary", which does not itself depend on how
%       the mean was weighted. A combination (difference) bin has no
%       trial count of its own, so weighting falls back to equal weights
%       for that bin specifically.
%
%   Every subject must have the same number of channels, the same number
%   of time samples, and the same set of bin labels; see
%   validateCompatibility below for the exact errors this checks for.
%
%   Returns a plain EEG struct (DataFormat = "Averaged", trials = 1) with
%   EEG.etc.GrandAverage = struct('sources', ..., 'weighted', ...,
%   'nSubjects', ...) recording how it was produced. The caller is
%   responsible for setting EEG.File and EEG.id and saving the result --
%   this function only computes.

    if numel(sourceFiles) < 2
        throw(MException('Alakazam:GrandAverage', ...
            ['A grand average needs at least two subjects to combine. ' ...
             'Pick more datasets in the dialog.']));
    end

    subjects = cell(1, numel(sourceFiles));
    for i = 1:numel(sourceFiles)
        loaded = load(sourceFiles{i}, 'EEG');
        subjects{i} = loaded.EEG;
    end

    validateCompatibility(subjects, sourceFiles);

    referenceLabels = {subjects{1}.bindesc.label};
    nSubjects = numel(subjects);
    nBins     = numel(referenceLabels);
    nChan     = size(subjects{1}.data, 1);
    nPnts     = size(subjects{1}.data, 2);

    % Re-order every subject's bins to match subject 1's label order, and
    % collect each subject's own trial count per bin (NaN for a
    % combination bin, which has no trial count of its own).
    data       = nan(nChan, nPnts, nBins, nSubjects);
    trialCount = nan(nBins, nSubjects);
    for s = 1:nSubjects
        subjectLabels = {subjects{s}.bindesc.label};
        for b = 1:nBins
            match = find(strcmp(subjectLabels, referenceLabels{b}), 1);
            data(:, :, b, s) = subjects{s}.data(:, :, match);
            n = subjects{s}.bindesc(match).n;
            if isnumeric(n)
                trialCount(b, s) = n;
            end
        end
    end

    [grandMean, grandSEM] = combineSubjects(data, trialCount, weighted);

    EEG = subjects{1};
    EEG.data  = grandMean;
    EEG.stErr = grandSEM;
    EEG.ntrials = NaN;   % a grand average has no single "original trial count"
    EEG.event = struct([]);   % stale per-subject event/epoch info; a grand
    EEG.epoch = struct([]);   % average has no trial-level data of its own
    for b = 1:nBins
        EEG.bindesc(b).label  = referenceLabels{b};
        EEG.bindesc(b).n      = sprintf('%d subjects', nSubjects);
        EEG.bindesc(b).events = [];
        EEG.bindesc(b).rt     = [];
        EEG.bindesc(b).trials = [];
    end
    EEG.etc.GrandAverage = struct('sources', {sourceFiles}, ...
        'weighted', weighted, 'nSubjects', nSubjects);
end

function [grandMean, grandSEM] = combineSubjects(data, trialCount, weighted)
%COMBINESUBJECTS  Combine subjects' per-bin means (and report the
%   across-subject spread). DATA is nchan x npnts x nbin x nsubjects;
%   GRANDMEAN/GRANDSEM are nchan x npnts x nbin.
    [nChan, nPnts, nBins, nSubjects] = size(data);
    grandMean = nan(nChan, nPnts, nBins);
    grandSEM  = std(data, 0, 4) / sqrt(nSubjects);

    for b = 1:nBins
        if weighted && ~any(isnan(trialCount(b, :)))
            w = trialCount(b, :) / sum(trialCount(b, :));
        else
            w = ones(1, nSubjects) / nSubjects;
        end
        grandMean(:, :, b) = sum(data(:, :, b, :) .* reshape(w, 1, 1, 1, nSubjects), 4);
    end
end

function validateCompatibility(subjects, sourceFiles)
%VALIDATECOMPATIBILITY  Make sure every subject can actually be combined:
%   same number of channels, same number of time samples, and the same
%   set of bin labels (any order). Throws a specific, friendly error
%   naming exactly which subject and which mismatch, rather than letting
%   a silent size mismatch or a wrong bin lineup happen later.
    reference     = subjects{1};
    referenceName = displayNameFor(sourceFiles{1});
    referenceLabels = sort(string({reference.bindesc.label}));

    for i = 2:numel(subjects)
        subject     = subjects{i};
        subjectName = displayNameFor(sourceFiles{i});

        if size(subject.data, 1) ~= size(reference.data, 1)
            throw(MException('Alakazam:GrandAverage', sprintf([ ...
                '"%s" has %d channels, but "%s" has %d. Every subject in a ' ...
                'grand average needs the same number of channels.'], ...
                subjectName, size(subject.data, 1), referenceName, size(reference.data, 1))));
        end

        if size(subject.data, 2) ~= size(reference.data, 2)
            throw(MException('Alakazam:GrandAverage', sprintf([ ...
                '"%s" has %d time samples per epoch, but "%s" has %d. Every ' ...
                'subject needs the same epoch length (the same Epoch ' ...
                'start/stop when DefineBins ran).'], ...
                subjectName, size(subject.data, 2), referenceName, size(reference.data, 2))));
        end

        subjectLabels = sort(string({subject.bindesc.label}));
        if ~isequal(subjectLabels, referenceLabels)
            throw(MException('Alakazam:GrandAverage', sprintf([ ...
                '"%s" has bins %s, but "%s" has bins %s. Every subject needs ' ...
                'the same set of bin labels -- make sure they all ran the ' ...
                'same (or a compatible) DefineBins script.'], ...
                subjectName, strjoin(subjectLabels, ', '), ...
                referenceName, strjoin(referenceLabels, ', '))));
        end
    end
end

function name = displayNameFor(file)
    [~, name, ~] = fileparts(file);
end
