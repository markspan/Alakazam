function subjects = collectFieldTripSubjects(this, report)
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
%   Its own method, apart from onExportFieldTripScript and its save dialog,
%   so that the collecting can be tested on a workspace on disk
%   (ExportFieldTripScriptTest).
%
%   See also ONEXPORTFIELDTRIPSCRIPT, EXPORTFIELDTRIPSCRIPT, COLLECTBRANCHTREE.
    if nargin < 2 || isempty(report)
        report = @(~) [];
    end
    subjects = struct('name', {}, 'rawFile', {}, 'steps', {}, 'contexts', {});
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
        'contexts', contexts);
end
