function [files, labels] = findGrandAverageCandidates(this)
%FINDGRANDAVERAGECANDIDATES  Every Averaged dataset in the cache
%   directory that is not itself a grand average -- the pool of
%   subjects a grand average can be built from.
    files  = {};
    labels = {};
    found = dir(fullfile(this.Workspace.CacheDirectory, '**', '*.mat'));
    for i = 1:numel(found)
        file = fullfile(found(i).folder, found(i).name);
        loaded = load(file, "EEG");
        candidate = loaded.EEG;
        if ~isfield(candidate, "DataFormat") || ~strcmpi(candidate.DataFormat, "Averaged")
            continue;
        end
        if isfield(candidate, "etc") && isfield(candidate.etc, "GrandAverage")
            continue; % do not grand-average a grand average
        end
        files{end + 1}  = file; %#ok<AGROW>
        labels{end + 1} = sprintf('%s (%s)', candidate.id, ...
            strjoin({candidate.bindesc.label}, ', ')); %#ok<AGROW>
    end
end
