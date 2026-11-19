function [subjects, contrast, kept] = averageWithinPerson(subjects, contrast)
%AVERAGEWITHINPERSON  One average per person, where a person was recorded more
%   than once.
%   [SUBJECTS, CONTRAST, KEPT] = ClusterStats.averageWithinPerson(SUBJECTS,
%   CONTRAST). CONTRAST.personOf, when present, names the person each of
%   SUBJECTS belongs to (WorkSpace.personFor, one entry per subject, in order).
%   Recordings of one person are averaged into one subject, so that the unit
%   the labels are permuted over is the person. KEPT is the index of each
%   person's first recording. CONTRAST.personOf and .groupOf follow, and
%   CONTRAST.recordingsPerPerson says how many recordings went into each.
%
%   WHY. A permutation test assumes its units are exchangeable and independent.
%   Two sessions of one person are neither: counted as two subjects, a stable
%   difference between people looks like replication. Twelve people with two
%   sessions each, tested as 24 recordings, gave .154 false positives at .05
%   where the same t-test on the 12 people gave .050.
%
%   Channels are matched by label and kept where every recording of the person
%   has them, in the first recording's order; bins are matched by label. The
%   noise covariance of a mean of K independent averages is the sum of theirs
%   over K^2, and it is dropped if any of them has none. The standard errors
%   are dropped: they described the single recordings.
%
%   A person in two groups cannot be averaged into either, so that is refused.
%
%   See also CLUSTERSTATS, SOURCECLUSTERSTATS, WORKSPACE.PERSONFOR.
    nSubjects = numel(subjects);
    kept = 1:nSubjects;
    if ~isfield(contrast, 'personOf') || isempty(contrast.personOf)
        return;
    end
    persons = cellstr(string(contrast.personOf));
    if numel(persons) ~= nSubjects
        throw(MException('Alakazam:ClusterStats', ...
            'contrast.personOf must have one entry per subject, I''m afraid.'));
    end
    for i = find(cellfun(@(p) isempty(strtrim(p)), persons))
        persons{i} = sprintf('recording %d', i);   % nobody said; it is its own person
    end

    [~, first, which] = unique(persons, 'stable');
    first = reshape(first, 1, []);
    which = reshape(which, 1, []);
    if numel(first) == nSubjects
        return;
    end

    merged = cell(1, numel(first));
    counts = zeros(1, numel(first));
    for p = 1:numel(first)
        members = find(which == p);
        counts(p) = numel(members);
        if isfield(contrast, 'groupOf') && ~isempty(contrast.groupOf)
            groups = unique(cellstr(string(contrast.groupOf(members))));
            if numel(groups) > 1
                throw(MException('Alakazam:ClusterStats', sprintf( ...
                    ['"%s" is in more than one group (%s), I''m afraid, so their recordings ' ...
                     'cannot be averaged into one subject. Would you check the groups in ' ...
                     'Edit Subjects?'], persons{first(p)}, strjoin(groups, ', '))));
            end
        end
        merged{p} = averageRecordings(subjects(members), persons{first(p)});
    end

    subjects = merged;
    kept = first;
    contrast.personOf = persons(first);
    contrast.recordingsPerPerson = counts;
    if isfield(contrast, 'groupOf') && ~isempty(contrast.groupOf)
        contrast.groupOf = contrast.groupOf(first);
    end
end

function EEG = averageRecordings(recordings, person)
%AVERAGERECORDINGS  The mean of one person's Averaged datasets.
    EEG = recordings{1};
    if isscalar(recordings)
        return;
    end
    labels = {EEG.chanlocs.labels};
    bins = {EEG.bindesc.label};
    for k = 2:numel(recordings)
        labels = labels(ismember(lower(labels), lower({recordings{k}.chanlocs.labels})));
        bins = bins(ismember(bins, {recordings{k}.bindesc.label}));
        if numel(recordings{k}.times) ~= numel(EEG.times) ...
                || max(abs(double(recordings{k}.times(:)) - double(EEG.times(:)))) > 1e-3
            throw(MException('Alakazam:ClusterStats', sprintf( ...
                ['The recordings of "%s" have different time axes, I''m afraid, so they cannot ' ...
                 'be averaged. Would you segment them with the same epoch?'], person)));
        end
    end

    nChan = numel(labels);
    nBins = numel(bins);
    K = numel(recordings);
    data = zeros(nChan, size(EEG.data, 2), nBins);
    noise = zeros(nChan, nChan, nBins);
    hasNoise = true;
    trials = zeros(1, nBins);
    trialsKnown = true(1, nBins);
    for k = 1:K
        r = recordings{k};
        [~, rows] = ismember(lower(labels), lower({r.chanlocs.labels}));
        [~, pages] = ismember(bins, {r.bindesc.label});
        data = data + double(r.data(rows, :, pages));
        if isfield(r, 'noiseCov') && ~isempty(r.noiseCov)
            noise = noise + double(r.noiseCov(rows, rows, pages));
        else
            hasNoise = false;
        end
        for b = 1:nBins
            n = r.bindesc(pages(b)).n;
            if isnumeric(n) && isscalar(n)
                trials(b) = trials(b) + n;
            else
                trialsKnown(b) = false;
            end
        end
    end

    [~, keepChan] = ismember(lower(labels), lower({EEG.chanlocs.labels}));
    [~, keepBin] = ismember(bins, {EEG.bindesc.label});
    EEG.chanlocs = EEG.chanlocs(keepChan);
    EEG.nbchan = nChan;
    EEG.bindesc = EEG.bindesc(keepBin);
    for b = find(trialsKnown)
        EEG.bindesc(b).n = trials(b);
    end
    EEG.data = data / K;
    EEG.id = person;
    EEG.stErr = [];
    EEG.aSME = [];
    if hasNoise
        EEG.noiseCov = noise / K ^ 2;
    else
        EEG.noiseCov = [];
        EEG.noiseCovInfo = [];
    end
end
