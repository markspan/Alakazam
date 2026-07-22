function [files, labels, kinds] = findGrandAverageCandidates(this)
%FINDGRANDAVERAGECANDIDATES  Every grand-averageable dataset in the cache
%   directory that is not itself a grand average -- the pool a grand average
%   can be built from. Three kinds qualify: an Averaged ERP (.data), a
%   time-frequency map (.ersp) or a coherence map (.coherence). KINDS returns
%   each candidate's kind ('ERP' / 'TF' / 'coherence'), so the dialog can put
%   each kind in its own selection list (a grand average combines one kind).
    files  = {};
    labels = {};
    kinds  = {};
    found = dir(fullfile(this.Workspace.CacheDirectory, '**', '*.mat'));
    for i = 1:numel(found)
        file = fullfile(found(i).folder, found(i).name);
        loaded = load(file, "EEG");
        candidate = loaded.EEG;
        if isfield(candidate, "etc") && isfield(candidate.etc, "GrandAverage")
            continue; % do not grand-average a grand average
        end
        tag = candidateKind(candidate);
        if isempty(tag) || ~isfield(candidate, "bindesc") || isempty(candidate.bindesc)
            continue;
        end
        files{end + 1}  = file; %#ok<AGROW>
        labels{end + 1} = sprintf('%s (%s)', candidate.id, ...
            strjoin({candidate.bindesc.label}, ', ')); %#ok<AGROW>
        kinds{end + 1}  = tag; %#ok<AGROW>
    end
end

function tag = candidateKind(EEG)
%CANDIDATEKIND  Short label tag for a grand-average candidate, or '' if the
%   dataset is not one (mirrors GrandAverage's own kind detection).
    if isfield(EEG, "ersp") && ~isempty(EEG.ersp)
        tag = 'TF';
    elseif isfield(EEG, "coherence") && ~isempty(EEG.coherence)
        tag = 'coherence';
    elseif isfield(EEG, "DataFormat") && strcmpi(EEG.DataFormat, "Averaged")
        tag = 'ERP';
    else
        tag = '';
    end
end
