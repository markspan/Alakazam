function [code, sidecars] = exportFieldTripScript(subjects, options)
%EXPORTFIELDTRIPSCRIPT  An Alakazam analysis written out as a FieldTrip script.
%
%   [CODE, SIDECARS] = exportFieldTripScript(SUBJECTS, OPTIONS) returns the
%   text of a MATLAB script that reads each raw recording with FieldTrip and
%   repeats the analysis step by step in FieldTrip's own functions, and the
%   files that belong beside it, which the script reads back: one table of
%   trials per recording that has them (<name>_trials.tsv, text) and one
%   ICA decomposition per ICA step (<name>_ica_<step>.mat, a struct whose
%   fields writeExportSidecars saves).
%
%   SUBJECTS is a struct array, one element per raw recording:
%     .name      its display name
%     .rawFile   its raw file, which FieldTrip reads (ft_preprocessing)
%     .steps     (transformId, params, parent), as collectBranchTree gives
%     .contexts  one per step, from fieldtripStepContext
%   OPTIONS may carry .mode, 'reproduce' (the default) or 'rerun' (below),
%   .title, used in the script's first line, and
%   .grandAverages (.name, .weighted, .members: one [recording, step] row
%   per source average, as collectFieldTripSubjects gives), written after
%   the recordings with ft_timelockgrandaverage: 'across', a plain mean,
%   for an equal grand average, and 'within', weighted by each recording's
%   trials, for a weighted one, except that a combination bin, which has no
%   trials of its own, is averaged equally in both, as Alakazam does.
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
%   TWO MODES. 'reproduce' reads back every choice FieldTrip cannot make
%   the way Alakazam made it, so the script gives Alakazam's numbers.
%   'rerun' lets FieldTrip make the choices it has a method for, with the
%   settings closest to Alakazam's: an ICA step becomes FieldTrip's own
%   decomposition, with the components matched to Alakazam's by topography
%   (see FIELDTRIPTRANSFORMCALL). Its results then come close to Alakazam's
%   without being them, which is the point: whether a result survives
%   another toolbox's run of the same method. Manual choices and the trials
%   DefineBins cut are Alakazam's in both modes, and the header says so.
%
%   RECORDINGS RUN THE SAME WAY SHARE A LOOP. Each recording's steps are
%   written in terms of NAME, STEM (the stem of its files beside the script)
%   and RAWFILE, so recordings whose steps come out the same, word for word,
%   are written once, as a loop over a list of them, as exportAnalysisScript
%   does. Their own numbers (trials kept, components removed) are in the
%   header, where each recording has its own rows.
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

    mode = char(string(TransTools.FieldOr(options, 'mode', 'reproduce')));
    if ~ismember(mode, {'reproduce', 'rerun'})
        throw(MException('Alakazam:exportFieldTripScript', ...
            'I''m afraid ''%s'' is not a mode I know: ''reproduce'' or ''rerun''.', mode));
    end
    sidecars = struct('name', {}, 'content', {});
    bodies = cell(1, numel(subjects));
    table = {};
    for s = 1:numel(subjects)
        [bodies{s}, rows, files] = subjectBlock(subjects(s), mode);
        table = [table, rows]; %#ok<AGROW>
        sidecars = [sidecars, files]; %#ok<AGROW>
    end
    blocks = {};
    placed = false(1, numel(subjects));
    for s = 1:numel(subjects)
        if placed(s)
            continue;
        end
        same = find(~placed & cellfun(@(b) isequal(b, bodies{s}), bodies));
        placed(same) = true;
        blocks = [blocks, recordingBlock(subjects(same), bodies{s})]; %#ok<AGROW>
    end
    gas = TransTools.FieldOr(options, 'grandAverages', struct('name', {}, 'weighted', {}, 'members', {}));
    gaLines = {};
    for g = 1:numel(gas)
        [lines, row] = grandAverageBlock(gas(g), subjects);
        gaLines = [gaLines, lines]; %#ok<AGROW>
        table{end + 1} = row; %#ok<AGROW>
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
        '%'}, modeLines(mode), {'%'}, table, ...
        {'%', '% Needs FieldTrip on the MATLAB path; the files it reads (tables of trials,', ...
        '% ICA decompositions) must stay beside this file. Each recording''s result is', ...
        '% kept in RESULTS, under its name.', ''}];
    setup = {'here = fileparts(mfilename(''fullpath''));', 'ft_defaults;', 'results = struct();'};
    if ~isempty(gas)
        setup{end + 1} = 'grand = struct();';
    end
    setup{end + 1} = '';
    code = strjoin([header, setup, blocks, gaLines, helperLines(blocks)], newline);
end

% ======================================================================= %
function lines = recordingBlock(group, body)
%RECORDINGBLOCK  BODY for one recording, or for several as a loop over them.
    rows = arrayfun(@(g) sprintf('%s, %s, %s', matlabLiteral(g.name), ...
        matlabLiteral(fileStem(g.name)), matlabLiteral(char(g.rawFile))), group, 'UniformOutput', false);
    if isscalar(group)
        lines = [{sprintf('%%%% %s', group.name), ...
            sprintf('name = %s;', matlabLiteral(group.name)), ...
            sprintf('stem = %s;', matlabLiteral(fileStem(group.name))), ...
            sprintf('rawFile = %s;', matlabLiteral(char(group.rawFile)))}, body];
        return;
    end
    lines = [{sprintf('%%%% %s (run the same way)', strjoin({group.name}, ', ')), ...
        '% Each recording''s name, the stem of its files beside this script, and its raw file.', ...
        'recordings = { ...'}, strcat({'    '}, rows, {'; ...'}), {'    };', ...
        'for r = 1:size(recordings, 1)', ...
        '    [name, stem, rawFile] = recordings{r, :};'}, ...
        strcat({'    '}, body(1:end - 1)), {'end', ''}];
    % (the body's last line is a blank, kept outside the loop)
    lines = regexprep(lines, '^\s+$', '');
end

function lines = modeLines(mode)
    if strcmp(mode, 'rerun')
        lines = {'% Mode: RE-RUN. FieldTrip makes the choices it has a method for itself, with the', ...
            '% settings closest to Alakazam''s (an ICA step is its own decomposition), so the', ...
            '% results come close to Alakazam''s without being them. Manual choices and the', ...
            '% trials are still Alakazam''s, read back.'};
    else
        lines = {'% Mode: REPRODUCE. Every choice FieldTrip cannot make is read back as Alakazam', ...
            '% made it, so the results are Alakazam''s.'};
    end
end

function [lines, rows, sidecars] = subjectBlock(subject, mode)
    steps = subject.steps;
    n = numel(steps);
    linear = all(arrayfun(@(k) steps(k).parent == k - 1 || (k == 1 && steps(k).parent < 1), 1:n));
    averaged = false(1, n);
    for k = 1:n
        p = steps(k).parent;
        averaged(k) = strcmp(steps(k).transformId, 'Average') || (p >= 1 && averaged(p));
    end
    varOf = @(k) variableName(k, linear, averaged);

    stem = fileStem(subject.name);
    tableName = sprintf('%s_trials.tsv', stem);
    defineStep = find(strcmp({steps.transformId}, 'DefineBins') & ...
        arrayfun(@(c) ~isempty(c.decision), subject.contexts), 1);
    rejectSteps = find(ismember({steps.transformId}, {'ManualReject', 'ArtefactDetect', 'AutoReject'}));

    lines = {};
    if ~isempty(defineStep)
        lines{end + 1} = ['trials = readtable(fullfile(here, [stem ''_trials.tsv'']), ' ...
            '''FileType'', ''text'', ''Delimiter'', ''\t'');'];
    end
    lines = [lines, {'cfg = [];', 'cfg.dataset = rawFile;', 'data = ft_preprocessing(cfg);', ''}];

    rows = {sprintf('%% %s', subject.name)};
    width = max(15, max(cellfun(@numel, {steps.transformId})));   % the header's columns line up
    binColumns = [];
    sidecars = struct('name', {}, 'content', {});
    for k = 1:n
        p = steps(k).parent;
        if p < 1
            in = 'data';
        else
            in = varOf(p);
        end
        names = struct('in', in, 'out', varOf(k), 'trials', 'trials', 'step', k, ...
            'binColumns', binColumns, 'icaFile', sprintf('%s_ica_%d.mat', stem, k), ...
            'icaCode', sprintf('[stem ''_ica_%d.mat'']', k), 'mode', mode);
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
        if ~isempty(step.sidecar)
            sidecars(end + 1) = struct('name', names.icaFile, 'content', step.sidecar); %#ok<AGROW>
        end
        label = upper(step.status);
        if strcmp(step.status, 'none')
            label = 'NOT TRANSLATED';
        end
        detail = '';
        if ~isempty(step.detail)
            detail = sprintf(': %s', step.detail);
        end
        rows{end + 1} = sprintf('%%   %2d %-*s %-15s %s%s', k, width, id, label, step.summary, detail); %#ok<AGROW>
        lines = [lines, {sprintf('%% Step %d. %s: %s (%s)', k, id, step.summary, lower(label))}, ...
            step.lines, {''}]; %#ok<AGROW>
    end
    % A recording's result is its last average, which is what a grand
    % average combines; with no average, its last step.
    lastAverage = find(strcmp({steps.transformId}, 'Average'), 1, 'last');
    if isempty(lastAverage)
        last = varOf(n);
    else
        last = varOf(lastAverage);
    end
    lines = [lines, {sprintf('results.(matlab.lang.makeValidName(name)) = %s;', last), ''}];

    if ~isempty(defineStep)
        sidecars = [struct('name', tableName, 'content', trialTable(subject, defineStep, rejectSteps)), ...
            sidecars];
    end
end

function [lines, row] = grandAverageBlock(ga, subjects)
%GRANDAVERAGEBLOCK  One grand average over the recordings' results, by
%   ft_timelockgrandaverage, its bins matched by label.
    members = ga.members;
    field = matlab.lang.makeValidName(ga.name);
    why = '';
    if isempty(members) || any(isnan(members(:)))
        why = 'a source average is not among the recordings this script carries';
    end
    bins = {};
    if isempty(why)
        for m = 1:size(members, 1)
            s = members(m, 1);
            k = members(m, 2);
            steps = subjects(s).steps;
            last = find(strcmp({steps.transformId}, 'Average'), 1, 'last');
            if ~isequal(k, last) || isempty(subjects(s).contexts(k).decision)
                why = sprintf('it combines an average of %s that is not its last', subjects(s).name);
                break;
            end
            bins{m} = subjects(s).contexts(k).decision.bins; %#ok<AGROW>
        end
    end
    if isempty(why)
        labels = {bins{1}.label};
        for m = 2:numel(bins)
            if ~isempty(setxor(labels, {bins{m}.label}))
                why = sprintf('%s has other bins than %s', subjects(members(m, 1)).name, ...
                    subjects(members(1, 1)).name);
                break;
            end
        end
    end
    if ~isempty(why)
        row = sprintf('%% Grand average %s: NOT TRANSLATED, %s', ga.name, why);
        lines = {sprintf('%%%% Grand average: %s', ga.name), ...
            sprintf('%% NOT TRANSLATED: %s.', capitalise(why)), ''};
        return;
    end
    names = arrayfun(@(m) subjects(members(m, 1)).name, 1:size(members, 1), 'UniformOutput', false);
    if ga.weighted
        weighting = 'weighted by each recording''s trials (FieldTrip''s ''within''), a combination bin equally';
    else
        weighting = 'every recording counted equally (FieldTrip''s ''across'')';
    end
    row = sprintf('%% Grand average %s: EXACT, %d recordings, %s', ga.name, size(members, 1), weighting);
    lines = {sprintf('%%%% Grand average: %s', ga.name), ...
        sprintf('%% %d recordings (%s), %s.', size(members, 1), strjoin(names, ', '), weighting), ...
        sprintf('grand.(%s) = cell(1, %d);', matlabLiteral(field), numel(labels))};
    for b = 1:numel(labels)
        combination = ~isempty(bins{1}(strcmp({bins{1}.label}, labels{b})).combines);
        method = 'across';
        if ga.weighted && ~combination
            method = 'within';
        end
        inputs = cell(1, size(members, 1));
        for m = 1:size(members, 1)
            index = find(strcmp({bins{m}.label}, labels{b}), 1);
            inputs{m} = sprintf('results.(%s){%d}', ...
                matlabLiteral(matlab.lang.makeValidName(names{m})), index);
        end
        lines = [lines, {sprintf('%% %s', labels{b}), 'cfg = [];', 'cfg.parameter = ''avg'';', ...
            sprintf('cfg.method = ''%s'';', method), ...
            sprintf('grand.(%s){%d} = ft_timelockgrandaverage(cfg, %s);', matlabLiteral(field), b, ...
                strjoin(inputs, ', '))}]; %#ok<AGROW>
    end
    lines{end + 1} = '';
end

function text = capitalise(text)
    if ~isempty(text)
        text(1) = upper(text(1));
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

function lines = helperLines(blocks)
%HELPERLINES  The small functions the script calls, each only if it does.
    lines = {};
    calls = @(name) any(contains(blocks, [name '(']));
    if calls('addChannel')
        lines = [lines, { ...
            '% ======================================================================= %', ...
            'function data = addChannel(data, name, labels, weights)', ...
            '%ADDCHANNEL  A channel made as a weighted sum of others, as Alakazam''s', ...
            '%   Derive Channels makes one from a let statement.', ...
            '    [~, rows] = ismember(labels, data.label);', ...
            '    for t = 1:numel(data.trial)', ...
            '        data.trial{t}(end + 1, :) = weights * data.trial{t}(rows, :);', ...
            '    end', ...
            '    data.label{end + 1} = name;', ...
            'end'}];
    end
    if calls('matchComponents')
        lines = [lines, { ...
            '% ======================================================================= %', ...
            'function remove = matchComponents(comp, templates, labels, threshold)', ...
            '%MATCHCOMPONENTS  The components of COMP whose topographies match TEMPLATES', ...
            '%   (channels x components, on LABELS): by the absolute correlation of the', ...
            '%   topographies, best pairs first, each component and template used once,', ...
            '%   and only where |r| reaches THRESHOLD. A template without a match is said.', ...
            '    [~, rows] = ismember(labels, comp.topolabel);', ...
            '    a = templates - mean(templates, 1);', ...
            '    b = comp.topo(rows, :) - mean(comp.topo(rows, :), 1);', ...
            '    r = abs((a ./ vecnorm(a))'' * (b ./ vecnorm(b)));', ...
            '    [values, order] = sort(r(:), ''descend'');', ...
            '    remove = [];', ...
            '    used = [];', ...
            '    for k = 1:numel(order)', ...
            '        [t, c] = ind2sub(size(r), order(k));', ...
            '        if values(k) >= threshold && ~ismember(t, used) && ~ismember(c, remove)', ...
            '            remove(end + 1) = c; %#ok<AGROW>', ...
            '            used(end + 1) = t; %#ok<AGROW>', ...
            '            fprintf(''Component %d matches removed component %d of Alakazam''''s (|r| = %.3f).\n'', c, t, values(k));', ...
            '        end', ...
            '    end', ...
            '    for t = setdiff(1:size(templates, 2), used)', ...
            '        warning(''Alakazam:fieldtripExport'', ''No component matches removed component %d of Alakazam''''s (best |r| = %.3f).'', t, max(r(t, :)));', ...
            '    end', ...
            'end'}];
    end
    if calls('restoreChannelOrder')
        lines = [lines, { ...
            '% ======================================================================= %', ...
            'function data = restoreChannelOrder(data, labels)', ...
            '%RESTORECHANNELORDER  The channels in the order LABELS gives.', ...
            '    [~, order] = ismember(labels, data.label);', ...
            '    data.label = data.label(order);', ...
            '    for t = 1:numel(data.trial)', ...
            '        data.trial{t} = data.trial{t}(order, :);', ...
            '    end', ...
            'end'}];
    end
end
