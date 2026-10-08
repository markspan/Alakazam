function [subjects, grandAverages] = collectFieldTripSubjects(this, report)
%COLLECTFIELDTRIPSUBJECTS  Every processed recording in the Data & Analyses
%   tree, as exportFieldTripScript takes them: its name and raw file, its
%   steps, and what each step's input and result tell a FieldTrip script
%   (fieldtripStepContext).
%
%   SUBJECTS = collectFieldTripSubjects(THIS, REPORT) walks the root
%   recordings as onExportAnalysisScript does, and also reads each step's
%   result, since the decisions a FieldTrip script reads back (which trials
%   DefineBins cut, which were rejected) are in the results. REPORT, if
%   given, is called with a line of progress per recording. A recording
%   nothing has been run on is left out.
%
%   GRANDAVERAGES lists the Grand Averages tree's grand averages as
%   exportFieldTripScript takes them: .name, .weighted, and .members, one
%   row per source average, [recording, step] into SUBJECTS (NaN for a
%   source that is not one of their steps, which the script then cannot
%   carry). Each source is matched by its cache file, exactly.
%
%   Its own method, apart from onExportFieldTripScript and its save dialog,
%   so that the collecting can be tested on a workspace on disk
%   (ExportFieldTripScriptTest).
%
%   See also ONEXPORTFIELDTRIPSCRIPT, EXPORTFIELDTRIPSCRIPT, COLLECTBRANCHTREE.
    if nargin < 2 || isempty(report)
        report = @(~) [];
    end
    subjects = struct('name', {}, 'rawFile', {}, 'steps', {}, 'contexts', {}, 'files', {});
    grandAverages = struct('name', {}, 'weighted', {}, 'members', {});
    nodes = this.Workspace.Tree.allNodes();
    if isempty(nodes)
        return;
    end
    roots = nodes([nodes.IsRoot]);
    for r = 1:numel(roots)
        report(sprintf('Reading %s (%d of %d)...', roots(r).Name, r, numel(roots)));
        subject = collectSubject(this, roots(r));
        if ~isempty(subject)
            subjects(end + 1) = subject; %#ok<AGROW>
        end
    end
    grandAverages = collectGrandAverages(this, subjects);
end

function gas = collectGrandAverages(this, subjects)
%COLLECTGRANDAVERAGES  Each grand average, its weighting, and the steps of
%   SUBJECTS its sources are, read from the node's etc.GrandAverage record.
    gas = struct('name', {}, 'weighted', {}, 'members', {});
    if ~isprop(this.Workspace, 'GrandAveragesTree') && ~isfield(this.Workspace, 'GrandAveragesTree')
        return;
    end
    nodes = this.Workspace.GrandAveragesTree.allNodes();
    for i = 1:numel(nodes)
        file = nodes(i).UserData;
        if isempty(file) || exist(file, 'file') ~= 2
            continue;
        end
        proxy = eegProxyFromCacheMeta(readEegCacheMeta(file));
        record = TransTools.FieldOr(TransTools.FieldOr(proxy, 'etc', struct()), 'GrandAverage', struct());
        sources = cellstr(string(TransTools.FieldOr(record, 'sources', {})));
        members = nan(numel(sources), 2);
        for m = 1:numel(sources)
            for s = 1:numel(subjects)
                k = find(strcmpi(subjects(s).files, sources{m}), 1);
                if ~isempty(k)
                    members(m, :) = [s k];
                    break;
                end
            end
        end
        gas(end + 1) = struct('name', nodes(i).Name, ...
            'weighted', logical(TransTools.FieldOr(record, 'weighted', false)), 'members', members); %#ok<AGROW>
    end
end

% ----------------------------------------------------------------------- %
function subject = collectSubject(this, rootNode)
%COLLECTSUBJECT  One recording's steps, with what each step's input and
%   result tell a FieldTrip script (fieldtripStepContext), or [] when
%   nothing has been run on it.
    subject = [];
    steps = struct('transformId', {}, 'params', {}, 'parent', {});
    files = {};
    [folder, stem] = fileparts(rootNode.UserData);
    childDir = fullfile(folder, stem);
    if exist(childDir, 'dir') ~= 7
        return;
    end
    for child = reshape(dir(fullfile(childDir, '*.mat')), 1, [])
        [branch, branchFiles] = this.collectBranchTree(fullfile(child.folder, child.name));
        offset = numel(steps);
        for b = 1:numel(branch)
            step = branch(b);
            if step.parent < 1
                step.parent = -1;
            else
                step.parent = step.parent + offset;
            end
            steps(end + 1) = step; %#ok<AGROW>
        end
        files = [files, branchFiles]; %#ok<AGROW>
    end
    if isempty(steps)
        return;
    end

    raw = this.loadNodeEEG(rootNode.UserData, 'export this recording');
    if isempty(raw)
        throw(MException('Alakazam:onExportFieldTripScript', ...
            'the recording %s could not be read', rootNode.Name));
    end
    rawFile = TransTools.FieldOr(TransTools.FieldOr(TransTools.FieldOr(raw, 'etc', struct()), ...
        'alz', struct()), 'rawFile', '');
    if isempty(rawFile)
        rawFile = fullfile(TransTools.FieldOr(raw, 'filepath', ''), TransTools.FieldOr(raw, 'filename', ''));
    end

    % Each result, read once; a step's input is its parent's result.
    loaded = cell(1, numel(steps));
    contexts = struct('srate', {}, 'labels', {}, 'format', {}, 'decision', {});
    for k = 1:numel(steps)
        loaded{k} = this.loadNodeEEG(files{k}, 'export this analysis');
        if isempty(loaded{k})
            throw(MException('Alakazam:onExportFieldTripScript', ...
                'a step of %s could not be read', rootNode.Name));
        end
        if steps(k).parent < 1
            input = raw;
        else
            input = loaded{steps(k).parent};
        end
        contexts(k) = fieldtripStepContext(steps(k).transformId, input, loaded{k});
        % A result no later step reads is let go: memory follows the
        % branch being walked, not the whole tree.
        for p = 1:k - 1
            if ~isempty(loaded{p}) && ~any([steps(k + 1:end).parent] == p)
                loaded{p} = [];
            end
        end
    end
    subject = struct('name', rootNode.Name, 'rawFile', char(rawFile), 'steps', steps, ...
        'contexts', contexts, 'files', {files});
end
