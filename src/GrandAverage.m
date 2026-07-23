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

    % A grand average combines like with like: ERP waveforms (Averaged .data),
    % time-frequency maps (.ersp), or coherence maps (.coherence). The kind is
    % read off the first subject; the rest must match.
    kind = grandAverageKind(subjects{1});
    for s = 2:numel(subjects)
        if ~strcmp(grandAverageKind(subjects{s}), kind)
            throw(MException('Alakazam:GrandAverage', sprintf([ ...
                '"%s" is a %s result but "%s" is a %s result. A grand average ' ...
                'combines datasets of one kind -- all ERPs, all time-frequency ' ...
                'maps, or all coherence maps -- not a mix.'], ...
                displayNameFor(sourceFiles{s}), kindName(grandAverageKind(subjects{s})), ...
                displayNameFor(sourceFiles{1}), kindName(kind))));
        end
    end

    if ~strcmp(kind, 'erp')
        EEG = combineMaps(subjects, sourceFiles, kind);
        EEG.etc.GrandAverage = struct('sources', {sourceFiles}, ...
            'weighted', false, 'nSubjects', numel(subjects), 'kind', kind);
        return;
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
    aSMEstack  = nan(nChan, nBins, nSubjects);
    for s = 1:nSubjects
        subjectLabels = {subjects{s}.bindesc.label};
        hasSME = isfield(subjects{s}, 'aSME') && ~isempty(subjects{s}.aSME) ...
            && size(subjects{s}.aSME, 1) == nChan;
        for b = 1:nBins
            match = find(strcmp(subjectLabels, referenceLabels{b}), 1);
            data(:, :, b, s) = subjects{s}.data(:, :, match);
            n = subjects{s}.bindesc(match).n;
            if isnumeric(n)
                trialCount(b, s) = n;
            end
            if hasSME && match <= size(subjects{s}.aSME, 2)
                aSMEstack(:, b, s) = subjects{s}.aSME(:, match);
            end
        end
    end

    [grandMean, grandSEM] = combineSubjects(data, trialCount, weighted);

    EEG = subjects{1};
    EEG.data  = grandMean;
    EEG.stErr = grandSEM;
    % Pool the analytic SME across subjects: for a grand average (a mean of N
    % subject means), the SME is the root of the summed squared subject SMEs,
    % divided by N. Only where every subject contributed a value.
    present  = sum(~isnan(aSMEstack), 3);
    EEG.aSME = sqrt(sum(aSMEstack .^ 2, 3, 'omitnan')) ./ nSubjects;
    EEG.aSME(present < nSubjects) = NaN;
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
        'weighted', weighted, 'nSubjects', nSubjects, 'kind', 'erp');
end

function kind = grandAverageKind(EEG)
%GRANDAVERAGEKIND  Which kind of result EEG is, for grand-averaging: a
%   time-frequency map ('tf', carries .ersp), a coherence map ('coherence',
%   carries .coherence), an ERP ('erp', an Averaged .data waveform set), or
%   'unknown'. The map kinds are checked first: a TimeFrequency/CoherenceMap
%   result keeps DataFormat "EPOCHED" but is really its map, not its trials.
    if isfield(EEG, 'ersp') && ~isempty(EEG.ersp)
        kind = 'tf';
    elseif isfield(EEG, 'coherence') && ~isempty(EEG.coherence)
        kind = 'coherence';
    elseif isfield(EEG, 'DataFormat') && strcmpi(EEG.DataFormat, 'Averaged')
        kind = 'erp';
    else
        kind = 'unknown';
    end
end

function name = kindName(kind)
    switch kind
        case 'tf';        name = 'time-frequency';
        case 'coherence'; name = 'coherence';
        case 'erp';       name = 'ERP';
        otherwise;        name = 'unrecognised';
    end
end

function EEG = combineMaps(subjects, sourceFiles, kind)
%COMBINEMAPS  Grand-average time-frequency (.ersp) or coherence (.coherence)
%   maps across subjects: an equal-weight mean of the per-subject maps, the
%   standard way to form a group-level time-frequency / coherence result
%   (compute per subject on their single trials, THEN average the maps -- the
%   maps cannot be recovered from an ERP grand average, which is why this is
%   its own path). Both arrays are channels x freq x time x bins (bins last);
%   bins are matched by label to the first subject before averaging.
    field = 'ersp';
    if strcmp(kind, 'coherence'); field = 'coherence'; end

    validateMapCompatibility(subjects, sourceFiles, field);

    referenceLabels = {subjects{1}.bindesc.label};
    nSubjects = numel(subjects);
    nBins     = numel(referenceLabels);
    sz        = size(subjects{1}.(field));            % chan x freq x time x bins
    stacked   = nan([sz, nSubjects]);

    for s = 1:nSubjects
        subjectLabels = {subjects{s}.bindesc.label};
        A = subjects{s}.(field);
        reordered = nan(sz);
        for b = 1:nBins
            match = find(strcmp(subjectLabels, referenceLabels{b}), 1);
            reordered(:, :, :, b) = A(:, :, :, match);
        end
        stacked(:, :, :, :, s) = reordered;
    end

    grand = mean(stacked, 5, 'omitnan');

    EEG = subjects{1};
    EEG.(field) = grand;
    EEG.ntrials = NaN;
    EEG.event   = struct([]); % stale per-subject trial-level info; a grand
    EEG.epoch   = struct([]); % average has none of its own
    for b = 1:nBins
        EEG.bindesc(b).label  = referenceLabels{b};
        EEG.bindesc(b).n      = sprintf('%d subjects', nSubjects);
        EEG.bindesc(b).events = [];
        EEG.bindesc(b).rt     = [];
        EEG.bindesc(b).trials = [];
    end
end

function validateMapCompatibility(subjects, sourceFiles, field)
%VALIDATEMAPCOMPATIBILITY  Every subject's map must match in channels, frequency
%   count and time count, and carry the same set of bin labels.
    reference     = subjects{1};
    referenceName = displayNameFor(sourceFiles{1});
    refSize       = size(reference.(field));
    referenceLabels = sort(string({reference.bindesc.label}));

    for i = 2:numel(subjects)
        subject     = subjects{i};
        subjectName = displayNameFor(sourceFiles{i});
        subSize     = size(subject.(field));

        if ~isequal(subSize(1:3), refSize(1:3))
            throw(MException('Alakazam:GrandAverage', sprintf([ ...
                '"%s" has a %s map of size %s (channels x freq x time), but "%s" ' ...
                'has %s. Every subject needs the same channels, frequencies and ' ...
                'time points -- run the transform with the same settings on each.'], ...
                subjectName, field, mat2str(subSize(1:3)), referenceName, mat2str(refSize(1:3)))));
        end

        subjectLabels = sort(string({subject.bindesc.label}));
        if ~isequal(subjectLabels, referenceLabels)
            throw(MException('Alakazam:GrandAverage', sprintf([ ...
                '"%s" has bins %s, but "%s" has bins %s. Every subject needs the ' ...
                'same set of bin labels.'], subjectName, strjoin(subjectLabels, ', '), ...
                referenceName, strjoin(referenceLabels, ', '))));
        end
    end
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
