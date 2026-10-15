function [keep, cancelled] = chooseAnalysisBranches(this, files, what, ask)
%CHOOSEANALYSISBRANCHES  Ask which analysis a report is of, when the
%   recordings hold more than one.
%
%   [KEEP, CANCELLED] = chooseAnalysisBranches(THIS, FILES, WHAT) looks at
%   how each of FILES, a report's datasets, was made (datasetBranches).
%   Branches that start at the same recording and each end in one of these
%   datasets are taken to be alternative analyses: a report that took them
%   all would count that recording once per analysis, as if they were more
%   measurements of the same thing. So, when any recording has datasets
%   made in more than one way, it asks which analyses to report, any number
%   of them, each named by what sets it apart and the number of recordings
%   it holds. Two Measure nodes under one average, measuring different
%   windows, are offered the same way; choosing both reports both.
%
%   KEEP marks the FILES of the analyses chosen; all of them when there was
%   nothing to ask, so a workspace with one analysis is reported as before.
%   CANCELLED is true when the question was cancelled, KEEP is then all
%   false, and the report is not made.
%
%   WHAT names one of the datasets in the question ('Measure result',
%   'average'). ASK, for the tests, replaces the question: called as
%   ASK(ITEMS, DESCRIPTION), it returns the ITEMS chosen, or [] to cancel.
%
%   See also DATASETBRANCHES, ANALYSISBRANCHES, ONEXPORTMEASUREMENTS,
%   ONEXPORTSPECTRAL, ONEXPORTDATAQUALITY.
    if nargin < 4
        ask = @askWhich;
    end
    files = reshape(cellstr(string(files)), 1, []);
    keep = true(1, numel(files));
    cancelled = false;
    if numel(files) < 2
        return;
    end
    [branch, names, recordings] = datasetBranches(this.Workspace.Tree, files);
    if numel(names) < 2 || ~hasAlternatives(branch, recordings)
        return;
    end

    items = cell(1, numel(names));
    for b = 1:numel(names)
        count = numel(unique(recordings(branch == b)));
        unit = 'recordings';
        if count == 1
            unit = 'recording';
        end
        items{b} = sprintf('%s  (%d %s)', names{b}, count, unit);
    end
    description = sprintf(['Some recordings have more than one %s, made in different ' ...
        'ways. A report that took them all would count each such recording once for ' ...
        'every analysis, as if they were further measurements of the same thing. ' ...
        'Which analyses should it be of?'], what);
    chosen = ask(items, description);
    if isempty(chosen)
        cancelled = true;
        keep = false(1, numel(files));
        return;
    end
    keep = ismember(branch, find(ismember(items, cellstr(string(chosen)))));
end

function tf = hasAlternatives(branch, recordings)
%HASALTERNATIVES  Does any recording have datasets made in more than one way?
    tf = false;
    for r = reshape(unique(recordings), 1, [])
        if numel(unique(branch(strcmp(recordings, r{1})))) > 1
            tf = true;
            return;
        end
    end
end

function chosen = askWhich(items, description)
%ASKWHICH  The question, in the generated dialog; [] when cancelled.
    chosen = [];
    answer = TransformOptionsDialog('title', 'Which analysis?', ...
        'Description', description, ...
        {'Analyses'; 'Analyses'}, DialogFields.MultiSelect(items, {}, ...
            'Required', true, 'Noun', 'analysis'));
    if ~isempty(answer)
        chosen = answer.Analyses;
    end
end
