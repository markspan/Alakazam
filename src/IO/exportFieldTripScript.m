function [code, sidecars] = exportFieldTripScript(subjects, options)
%EXPORTFIELDTRIPSCRIPT  An Alakazam analysis written out as a FieldTrip script.
%
%   [CODE, SIDECARS] = exportFieldTripScript(SUBJECTS, OPTIONS) returns the
%   text of a MATLAB script that reads each raw recording with FieldTrip and
%   repeats the analysis step by step in FieldTrip's own functions, and the
%   files that belong beside it: one table of trials per recording that has
%   them (<name>_trials.tsv), which the script reads back.
%
%   SUBJECTS is a struct array, one element per raw recording:
%     .name      its display name
%     .rawFile   its raw file, which FieldTrip reads (ft_preprocessing)
%     .steps     (transformId, params, parent), as collectBranchTree gives
%     .contexts  one per step, from fieldtripStepContext
%   OPTIONS may carry .title, used in the script's first line.
%
%   WHAT IT IS FOR. Alakazam's other export (exportAnalysisScript) writes a
%   script that calls Alakazam and EEGLAB, so it reproduces the analysis
%   exactly but needs Alakazam to run. This one needs only FieldTrip: a
%   record of the method in the toolbox many readers know, and a starting
%   point for analysing further there. Every step says how faithful it is
%   (see FIELDTRIPTRANSFORMCALL): exact, a decision read back, approximate,
%   or not translated, in the script's header and again at the step. A
%   script made only of exact steps and decisions gives Alakazam's numbers
%   (FieldTripTutorialErpTest checks that on FieldTrip's own ERP tutorial).
%
%   ONE CHAIN PER RECORDING. Each recording's steps are written in order;
%   a branch (two steps on the same parent) gets a variable of its own per
%   step. One DefineBins per recording is carried as a decision; a second
%   would need a second table of trials, and is marked instead.
%
%   See also FIELDTRIPTRANSFORMCALL, FIELDTRIPSTEPCONTEXT,
%   EXPORTANALYSISSCRIPT, ALAKAZAM.ONEXPORTFIELDTRIPSCRIPT.
    if nargin < 2 || ~isstruct(options)
        options = struct();
    end
    if isempty(subjects)
        throw(MException('Alakazam:exportFieldTripScript', ...
            ['I''m afraid there is no analysis to export yet: this workspace has no ' ...
             'processed recordings. Would you run at least one transformation first?']));
    end

    sidecars = struct('name', {}, 'content', {});
    blocks = {};
    table = {};
    helpers = false;
    for s = 1:numel(subjects)
        [lines, rows, sidecar, usesHelper] = subjectBlock(subjects(s));
        blocks = [blocks, lines]; %#ok<AGROW>
        table = [table, rows]; %#ok<AGROW>
        if ~isempty(sidecar)
            sidecars(end + 1) = sidecar; %#ok<AGROW>
        end
        helpers = helpers || usesHelper;
    end

    title = char(string(TransTools.FieldOr(options, 'title', 'An Alakazam analysis')));
    header = [ ...
        {sprintf('%%%% %s, as a FieldTrip script', title), ...
        sprintf('%% Exported from Alakazam%s on %s. It reads each raw recording with', ...
            versionText(), char(datetime('now', 'Format', 'd MMMM yyyy'))), ...
        '% FieldTrip and repeats the analysis step by step. How faithful each step is:', ...
        '%   exact           FieldTrip computes what Alakazam computed', ...
        '%   decision        Alakazam''s choice (which trials, which rejected) is read', ...
        '%                   back from the recording''s table of trials beside this file', ...
        '%   approximate     close; the step says how it differs', ...
        '%   NOT TRANSLATED  no FieldTrip counterpart: the script carries on without it', ...
        '%'}, table, ...
        {'%', '% Needs FieldTrip on the MATLAB path; the tables of trials must stay beside', ...
        '% this file. Each recording''s result is kept in RESULTS, under its name.', ''}];
    setup = {'here = fileparts(mfilename(''fullpath''));', 'ft_defaults;', 'results = struct();', ''};
    code = strjoin([header, setup, blocks, helperLines(helpers)], newline);
end

% ======================================================================= %
function [lines, rows, sidecar, usesHelper] = subjectBlock(subject)
    steps = subject.steps;
    n = numel(steps);
    linear = all(arrayfun(@(k) steps(k).parent == k - 1 || (k == 1 && steps(k).parent < 1), 1:n));
    averaged = false(1, n);
    for k = 1:n
        p = steps(k).parent;
        averaged(k) = strcmp(steps(k).transformId, 'Average') || (p >= 1 && averaged(p));
    end
    varOf = @(k) variableName(k, linear, averaged);

    tableName = sprintf('%s_trials.tsv', fileStem(subject.name));
    defineStep = find(strcmp({steps.transformId}, 'DefineBins') & ...
        arrayfun(@(c) ~isempty(c.decision), subject.contexts), 1);
    rejectSteps = find(ismember({steps.transformId}, {'ManualReject', 'ArtefactDetect', 'AutoReject'}));

    lines = {sprintf('%%%% %s', subject.name)};
    if ~isempty(defineStep)
        lines{end + 1} = sprintf(['trials = readtable(fullfile(here, %s), ''FileType'', ''text'', ' ...
            '''Delimiter'', ''\\t'');'], matlabLiteral(tableName));
    end
    lines = [lines, {'cfg = [];', sprintf('cfg.dataset = %s;', matlabLiteral(char(subject.rawFile))), ...
        'data = ft_preprocessing(cfg);', ''}];

    rows = {sprintf('%% %s', subject.name)};
    binColumns = [];
    usesHelper = false;
    for k = 1:n
        p = steps(k).parent;
        if p < 1
            in = 'data';
        else
            in = varOf(p);
        end
        names = struct('in', in, 'out', varOf(k), 'trials', 'trials', 'step', k, ...
            'binColumns', binColumns);
        id = steps(k).transformId;
        ctx = subject.contexts(k);
        if strcmp(id, 'DefineBins') && ~isempty(ctx.decision) && k ~= defineStep
            step = fieldtripTransformCall(id, steps(k).params, ctx, names, ...
                'a second DefineBins would need a second table of trials');
        elseif ismember(k, rejectSteps) && (isempty(defineStep) || k < defineStep)
            step = fieldtripTransformCall(id, steps(k).params, ctx, names, ...
                'it ran before any trials were cut');
        else
            step = fieldtripTransformCall(id, steps(k).params, ctx, names);
        end
        if k == defineStep
            binColumns = [ctx.decision.bins.index];
        end
        usesHelper = usesHelper || any(contains(step.lines, 'addChannel('));
        label = upper(step.status);
        if strcmp(step.status, 'none')
            label = 'NOT TRANSLATED';
        end
        rows{end + 1} = sprintf('%%   %2d %-15s %-15s %s', k, id, label, step.summary); %#ok<AGROW>
        lines = [lines, {sprintf('%% Step %d. %s: %s (%s)', k, id, step.summary, lower(label))}, ...
            step.lines, {''}]; %#ok<AGROW>
    end
    last = varOf(n);
    lines = [lines, {sprintf('results.(%s) = %s;', matlabLiteral(matlab.lang.makeValidName(subject.name)), last), ''}];

    sidecar = [];
    if ~isempty(defineStep)
        sidecar = struct('name', tableName, 'content', trialTable(subject, defineStep, rejectSteps));
    end
end

function name = variableName(k, linear, averaged)
    if averaged(k)
        base = 'erp';
    else
        base = 'data';
    end
    if linear
        name = base;
    else
        name = sprintf('%s%d', base, k);
    end
end

function text = trialTable(subject, defineStep, rejectSteps)
%TRIALTABLE  The trials DefineBins cut, one row each: its number, its first
%   and last sample, its offset (the samples before the anchor), a 0/1
%   column per bin, and a 0/1 column per rejecting step after it.
    d = subject.contexts(defineStep).decision;
    nTrials = numel(d.epochStart);
    columns = [{'trial', 'begsample', 'endsample', 'offset'}, ...
        arrayfun(@(b) sprintf('bin_%d', b.index), d.bins, 'UniformOutput', false)];
    values = [(1:nTrials)', d.epochStart, d.epochStart + d.pnts - 1, repmat(d.offset, nTrials, 1), ...
        double(d.membership)];
    for k = rejectSteps(rejectSteps > defineStep)
        columns{end + 1} = sprintf('rejected_%d', k); %#ok<AGROW>
        flag = zeros(nTrials, 1);
        flag(subject.contexts(k).decision.rejected) = 1;
        values(:, end + 1) = flag; %#ok<AGROW>
    end
    lines = [{strjoin(columns, char(9))}, ...
        arrayfun(@(r) strjoin(compose('%.15g', values(r, :)), char(9)), 1:nTrials, 'UniformOutput', false)];
    text = [strjoin(lines, newline), newline];
end

function stem = fileStem(name)
    stem = regexprep(char(name), '[^A-Za-z0-9_-]+', '_');
end

function text = versionText()
    text = '';
    try
        info = alakazamVersion();
        text = sprintf(' %s', char(string(info.Version)));
    catch
        % A copy without a version still exports.
    end
end

function lines = helperLines(used)
    lines = {};
    if ~used
        return;
    end
    lines = { ...
        '% ======================================================================= %', ...
        'function data = addChannel(data, name, labels, weights)', ...
        '%ADDCHANNEL  A channel made as a weighted sum of others, as Alakazam''s', ...
        '%   Derive Channels makes one from a let statement.', ...
        '    [~, rows] = ismember(labels, data.label);', ...
        '    for t = 1:numel(data.trial)', ...
        '        data.trial{t}(end + 1, :) = weights * data.trial{t}(rows, :);', ...
        '    end', ...
        '    data.label{end + 1} = name;', ...
        'end'};
end
