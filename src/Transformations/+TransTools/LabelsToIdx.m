function idx = LabelsToIdx(input, wantLabels)
%LABELSTOIDX  Row indices of WANTLABELS in EEG.chanlocs (case-insensitive,
%   in dataset order; labels not present are skipped). Previously
%   reimplemented, identically, as a private local function in ReRef.m,
%   SelectData.m and Interpolate.m; consolidated here.
    if isempty(wantLabels); idx = []; return; end
    all = {input.chanlocs.labels};
    want = cellfun(@(s) char(string(s)), wantLabels, 'UniformOutput', false);
    idx = find(ismember(lower(all), lower(want)));
end
