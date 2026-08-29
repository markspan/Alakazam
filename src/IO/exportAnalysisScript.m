function [code, sidecars] = exportAnalysisScript(subjects, grandAverages, options)
%EXPORTANALYSISSCRIPT  The analysis in an Alakazam workspace, as a runnable
%   MATLAB script.
%
%   CODE = EXPORTANALYSISSCRIPT(SUBJECTS, GRANDAVERAGES, OPTIONS) returns
%   the text of a script that reads each raw recording, applies the same
%   transformations with the same options that were used interactively, and
%   builds the same grand averages. SIDECARS are files that belong beside
%   it (each DefineBins bin script, in its own form); the caller writes them
%   into the same folder as the script.
%
%   SUBJECTS is a struct array, one element per raw recording:
%     .name      the recording's display name
%     .rawFile   its raw file path
%     .loader    'set' | 'bva' | 'mat' | 'erp', which reader to emit
%     .steps     a collectBranchTree list: (transformId, params, parent),
%                parent being a 1-based index into the same list, or -1
%   GRANDAVERAGES is a struct array, one element per grand average:
%     .name      its display name
%     .weighted  logical
%     .subjects  cellstr of the recording names it was built from ({} when
%                that could not be resolved, which then means "all")
%   OPTIONS carries .rawDirectory and .outputDirectory for the header.
%
%   WHAT THE SCRIPT CALLS, AND WHY. It calls Alakazam's own transformation
%   functions (Filter, DefineBins, Average, ...) with the recorded options,
%   exactly as the app itself replays a step (see
%   Alakazam.applyStepToTarget, which does the same feval). It deliberately
%   does NOT attempt to emit equivalent EEGLAB or ERPLAB calls: those would
%   be a re-implementation rather than a record, and any place the two
%   differed would make the script quietly disagree with the results it
%   claims to reproduce. The script needs Alakazam's src/ on the path, which
%   it adds itself.
%
%   WHAT MAKES THE OUTPUT WORTH READING. Four things, each because the
%   obvious alternative produces a script nobody would keep:
%
%     * Recordings processed identically are emitted ONCE, as a loop.
%       "Apply to All" is how a study is normally run, so this usually
%       collapses the whole thing; grouping is by exact equality, so a
%       subject that genuinely differs keeps its own block instead of being
%       silently given someone else's settings.
%     * Every step's options are hoisted into named variables in one block
%       at the top. Inline, a threshold appears once per subject block and
%       has to be changed in every one; hoisted, the top of the script is
%       the settings and the body is the pipeline.
%     * Each recording runs inside try/catch, and failures are collected and
%       reported at the end. A batch that dies on subject 3 of 40 and
%       discards the other 37 is not a batch.
%     * Sections (%%) so the MATLAB editor can fold and run them, and the
%       structure is visible in the editor's own outline.
%
%   See also MATLABLITERAL, RAWCODE, ALAKAZAM.ONEXPORTANALYSISSCRIPT.
    if nargin < 3
        options = struct();
    end
    if isempty(subjects)
        throw(MException('Alakazam:exportAnalysisScript', ...
            ['I''m afraid there is no analysis to export yet: this workspace has no ' ...
             'processed recordings. Would you run at least one transformation first?']));
    end

    [subjects, sidecars] = extractBinScripts(subjects);
    groups  = groupByPipeline(subjects);
    optbook = buildOptionBook(subjects);

    % The body is built at one level of indentation (it used to be wrapped
    % in a function) and then shifted out to column 0, which is where a
    % script's own code belongs. Done as one shift at the end rather than by
    % threading a base indent through every emitter: the relative structure
    % inside loops, try blocks and multi-line literals is already correct,
    % and only the outermost level changes.
    body = [ ...
        setupLines(subjects, options), ...
        binScriptLines(sidecars), ...
        optionLines(optbook), ...
        pipelineLines(subjects, groups, optbook), ...
        grandAverageLines(grandAverages), ...
        summaryLines(subjects)];

    % The helpers stay as they are: MATLAB allows local functions in a
    % script only after all executable code, and they are already written at
    % column 0.
    lines = [ ...
        headerLines(subjects, grandAverages, groups, options), ...
        outdent(body), ...
        helperLines()];
    code = strjoin(lines, newline);
end

function lines = outdent(lines)
%OUTDENT  Remove one four-space level from each line that has one. A line
%   already at column 0 (a %% section header, a blank) is left alone.
    for i = 1:numel(lines)
        if startsWith(lines{i}, '    ')
            lines{i} = lines{i}(5:end);
        end
    end
end

% ======================================================================= %
%  Bin scripts: moved out of the code into their own files
% ======================================================================= %
function [subjects, sidecars] = extractBinScripts(subjects)
%EXTRACTBINSCRIPTS  Move every DefineBins bin script out of the generated
%   code and into its own .binscript file beside it.
%
%   A bin script is source text in its own right: the analyst wrote it, it
%   has its own syntax and its own comments, and Alakazam can load one
%   directly. Inlining it as an escaped sprintf string (near a kilobyte of
%   it) makes the generated script unreadable and the bin script itself
%   uneditable, which is exactly backwards.
%
%   Identical scripts share one file, since every subject in a study
%   normally runs the same bins.
%
%   The compiled .bins field is dropped at the same time, for the reason
%   Alakazam.templateParams gives at length: it is a cache derived wholly
%   from .script, DefineBins re-parses it whenever it is absent, and
%   carrying the compiled form risks type-shape mismatches that re-parsing
%   avoids by construction.
    sidecars = struct('name', {}, 'content', {}, 'variable', {});
    for s = 1:numel(subjects)
        steps = subjects(s).steps;
        for k = 1:numel(steps)
            params = steps(k).params;
            if ~isstruct(params) || ~isfield(params, 'script')
                continue;
            end
            script = params.script;
            if ~(ischar(script) || isstring(script)) || isempty(char(script))
                continue;
            end
            script = char(script);

            match = find(arrayfun(@(x) strcmp(x.content, script), sidecars), 1);
            if isempty(match)
                match = numel(sidecars) + 1;
                sidecars(match) = struct( ...
                    'name', sprintf('bins%d.binscript', match), ...
                    'content', script, ...
                    'variable', sprintf('binScript%d', match));
            end

            params.script = rawCode(sidecars(match).variable);
            if isfield(params, 'bins')
                params = rmfield(params, 'bins');
            end
            steps(k).params = params;
        end
        subjects(s).steps = steps;
    end
end

% ======================================================================= %
%  Grouping and the options book
% ======================================================================= %
function groups = groupByPipeline(subjects)
%GROUPBYPIPELINE  Group subject indices by identical pipeline: the same
%   reader, the same steps in the same shape, and the same options at every
%   step. Order is preserved, so the script reads in workspace order.
%
%   isequaln, not isequal: an option legitimately holding NaN (an unset
%   width or fraction, which several Measure windows carry) would otherwise
%   compare unequal to itself and split a group that is in fact identical.
%
%   The reader is deliberately NOT part of the key. Every recording is read
%   back from the cache in the same way, so a workspace mixing .set and
%   BrainVision recordings still groups into one loop as long as the
%   processing matches, which is the thing that actually has to agree.
    groups = struct('indices', {});
    for s = 1:numel(subjects)
        placed = false;
        for g = 1:numel(groups)
            other = subjects(groups(g).indices(1));
            if isequaln(subjects(s).steps, other.steps)
                groups(g).indices(end + 1) = s;
                placed = true;
                break;
            end
        end
        if ~placed
            groups(end + 1) = struct('indices', s); %#ok<AGROW>
        end
    end
end

function book = buildOptionBook(subjects)
%BUILDOPTIONBOOK  One named variable per DISTINCT options value, shared
%   wherever that same value is used again.
%
%   The point is editability. Inline, a rejection threshold appears once per
%   step per block and changing it means finding every copy; hoisted, it
%   appears once, at the top, under a name, and the pipeline below reads as
%   a sequence of calls rather than a wall of literals. Distinct values for
%   the same transformation get numbered names, so a chain that filters
%   twice still says which filter is which.
    book = struct('transformId', {}, 'params', {}, 'variable', {}, ...
        'usedBy', {}, 'shared', {});
    for s = 1:numel(subjects)
        steps = subjects(s).steps;
        for k = 1:numel(steps)
            if isEmptyOptions(steps(k).params)
                continue;   % nothing worth naming; emitted inline
            end
            existing = findOption(book, steps(k).transformId, steps(k).params);
            if ~isempty(existing)
                if ~any(strcmp(book(existing).usedBy, subjects(s).name))
                    book(existing).usedBy{end + 1} = char(subjects(s).name);
                end
                continue;
            end
            book(end + 1) = struct('transformId', steps(k).transformId, ...
                'params', steps(k).params, 'variable', '', ...
                'usedBy', {{char(subjects(s).name)}}, 'shared', false); %#ok<AGROW>
        end
    end

    % Mark the entries whose transformation has more than one variant: those
    % are the ones that need distinguishing, and where naming the users
    % earns its line.
    for i = 1:numel(book)
        book(i).shared = sum(strcmp({book.transformId}, book(i).transformId)) > 1;
    end
    book = nameOptions(book);
end

function book = nameOptions(book)
%NAMEOPTIONS  Give every option set a variable name that says what it is.
%
%   One variant of a transformation is simply opt_<Transform>. Where there
%   are several, a bare opt_X, opt_X_2, opt_X_3 tells the reader nothing
%   about which recordings ran which, and the whole reason a second variant
%   exists is that some recording was treated differently: that recording's
%   name is the useful label, so the variant becomes
%   opt_ArtefactDetect_sub03.
%
%   Names are used only when they actually distinguish. Two different filter
%   settings within ONE recording's own chain share a user list, so naming
%   both after that recording would be worse than useless; those fall back
%   to a number. The variant used by the MOST recordings keeps the plain
%   name, since it is the norm the others depart from.
    transformIds = unique({book.transformId}, 'stable');
    for t = 1:numel(transformIds)
        idx = find(strcmp({book.transformId}, transformIds{t}));
        base = sprintf('opt_%s', matlab.lang.makeValidName(transformIds{t}));

        if isscalar(idx)
            book(idx).variable = base;
            continue;
        end

        counts = arrayfun(@(i) numel(book(i).usedBy), idx);
        [~, majority] = max(counts);          % ties resolve to the first
        book(idx(majority)).variable = base;
        majorityUsers = book(idx(majority)).usedBy;

        for j = 1:numel(idx)
            if j == majority
                continue;
            end
            suffix = distinguishingSuffix(book(idx(j)).usedBy, majorityUsers);
            if isempty(suffix)
                name = base;                   % numbered below
            else
                name = sprintf('%s_%s', base, suffix);
            end
            book(idx(j)).variable = uniqueVariable(name, {book.variable});
        end
    end
end

function suffix = distinguishingSuffix(users, majorityUsers)
%DISTINGUISHINGSUFFIX  A name built from the recordings using this variant,
%   or '' when names cannot distinguish it.
%
%   Empty when the users overlap the majority's (the same recording running
%   a transformation twice with different settings, where its name labels
%   both), or when there are enough of them that the name would be longer
%   than it is informative.
    suffix = '';
    if isempty(users) || ~isempty(intersect(users, majorityUsers)) || numel(users) > 2
        return;
    end
    parts = cellfun(@(u) identifierPart(u), users, 'UniformOutput', false);
    parts = parts(~cellfun(@isempty, parts));
    if isempty(parts)
        return;
    end
    suffix = strjoin(parts, '_');
end

function part = identifierPart(text)
%IDENTIFIERPART  TEXT reduced to something usable inside an identifier.
%   Not makeValidName: that would prefix a leading digit with "x", which is
%   unnecessary here because this only ever appears after "opt_<Transform>_".
    part = regexprep(char(text), '[^A-Za-z0-9]+', '_');
    part = regexprep(part, '^_+|_+$', '');
    if numel(part) > 24
        part = part(1:24);
    end
end

function name = uniqueVariable(candidate, existing)
%UNIQUEVARIABLE  CANDIDATE, numbered if taken, and kept within MATLAB's own
%   identifier length limit so the generated script cannot fail to parse on
%   a workspace with unusually long recording names.
    used = existing(~cellfun(@isempty, existing));
    limit = namelengthmax;
    name = candidate;
    if numel(name) > limit
        name = name(1:limit);
    end
    n = 1;
    while any(strcmp(used, name))
        n = n + 1;
        tail = sprintf('_%d', n);
        stem = candidate;
        if numel(stem) + numel(tail) > limit
            stem = stem(1:limit - numel(tail));
        end
        name = [stem tail];
    end
end

function index = findOption(book, transformId, params)
    index = [];
    for i = 1:numel(book)
        if strcmp(book(i).transformId, transformId) && isequaln(book(i).params, params)
            index = i;
            return;
        end
    end
end

function tf = isEmptyOptions(params)
    tf = isempty(params) || (isstruct(params) && isscalar(params) && isempty(fieldnames(params)));
end

function text = optionExpression(book, step)
%OPTIONEXPRESSION  What to pass as a step's options: its named variable, or
%   the literal itself where there was nothing worth naming.
    index = findOption(book, step.transformId, step.params);
    if isempty(index)
        text = matlabLiteral(step.params, 8);
    else
        text = book(index).variable;
    end
end

% ======================================================================= %
%  Header and setup
% ======================================================================= %
function lines = headerLines(subjects, grandAverages, groups, options)
    stamp = char(string(datetime('now'), 'yyyy-MM-dd HH:mm'));
    looped = sum(arrayfun(@(g) numel(g.indices) > 1, groups));
    % A script, not a function: its variables are left in the workspace, so
    % an average or a measurement can be inspected after the run, and any
    % section can be re-run on its own from the editor. The helpers at the
    % foot are local functions, which a script may have provided they come
    % after all of its executable code.
    lines = { ...
        '%% Alakazam analysis' ...
        '%  Reproduce an analysis exported from Alakazam.' ...
        '%' ...
        sprintf('%%   Generated %s, from %d recording(s) and %d grand average(s).', ...
            stamp, numel(subjects), numel(grandAverages)) ...
        '%' ...
        '%   Calls Alakazam''s own transformations with the options recorded when' ...
        '%   each step was run, so it reproduces the analysis rather than' ...
        '%   approximating it in another toolbox. Needs Alakazam''s src/ on the' ...
        '%   MATLAB path (added below) and EEGLAB available, as the app does.' ...
        '%' ...
        '%   The Options section is the one to edit: every step below refers to it.' ...
        '%   Each recording runs independently, so one bad file does not stop the' ...
        '%   rest; anything that failed is listed at the end.' ...
        };
    if looped > 0
        lines{end + 1} = '%';
        lines{end + 1} = sprintf(['%%   %d group(s) of recordings were processed identically and are ' ...
            'run in a loop.'], looped);
    end
    lines{end + 1} = '';
    if isfield(options, 'rawDirectory') && ~isempty(options.rawDirectory)
        lines{end + 1} = sprintf('%%   Raw data:  %s', options.rawDirectory);
    end
    if isfield(options, 'outputDirectory') && ~isempty(options.outputDirectory)
        lines{end + 1} = sprintf('%%   Output to: %s', options.outputDirectory);
    end
    lines{end + 1} = '';
end

function lines = setupLines(subjects, options)
    rawDir   = getOr(options, 'rawDirectory', '');
    cacheDir = getOr(options, 'cacheDirectory', '');
    outDir   = getOr(options, 'outputDirectory', pwd);
    needed = uniqueTransformIds(subjects);
    lines = { ...
        '%% Setup' ...
        '    % scriptDir is where this file and its .binscript files live; the' ...
        '    % Alakazam checkout is assumed to be its parent. Adjust if moved.' ...
        '    scriptDir = fileparts(mfilename(''fullpath''));' ...
        '    alakazamRoot = fileparts(scriptDir);' ...
        '    if exist(fullfile(alakazamRoot, ''src''), ''dir'') == 7' ...
        '        addpath(genpath(fullfile(alakazamRoot, ''src'')));' ...
        '    end' ...
        '' ...
        '    % Each recording is read from the workspace cache, where it sits as it' ...
        '    % stood just after import: smaller and faster than re-reading the' ...
        '    % original file, and needing no format reader. To start from the raw' ...
        '    % recordings instead, replace the load line in the pipeline below with' ...
        '    % the reader for their format:' ...
        '    %     EEG = pop_loadset(''sub01.set'', rawDir);              % EEGLAB' ...
        '    %     EEG = pop_loadbv(rawDir, ''sub01.vhdr'');              % BrainVision' ...
        '    %     loaded = load(fullfile(rawDir, ''sub01.erp''), ''-mat''); % ERPLAB erpset' ...
        '    %     EEG = erpsetToAveraged(loaded.ERP);' ...
        sprintf('    cacheDir = %s;', matlabLiteral(char(cacheDir))) ...
        sprintf('    rawDir   = %s;', matlabLiteral(char(rawDir))) ...
        sprintf('    outDir   = %s;', matlabLiteral(char(outDir))) ...
        '    if ~isempty(outDir) && exist(outDir, ''dir'') ~= 7' ...
        '        mkdir(outDir);' ...
        '    end' ...
        '' ...
        '    % Checked up front, with a clear message, rather than failing on the' ...
        '    % first call halfway through a long batch.' ...
        sprintf('    requireFunctions(%s);', matlabLiteral(needed, 4)) ...
        '' ...
        '    failures = struct(''name'', {}, ''message'', {});' ...
        };
    % Only the collectors this analysis actually fills: an always-empty
    % "measures" would leave the reader wondering what happened to it.
    used = collectorsUsed(subjects);
    for c = 1:numel(used)
        lines{end + 1} = sprintf('    %s = struct(''name'', {}, ''EEG'', {});', used{c}); %#ok<AGROW>
    end
    lines{end + 1} = '';
end

function names = collectorsUsed(subjects)
%COLLECTORSUSED  The result vectors this analysis needs, in a stable order.
    names = {};
    for s = 1:numel(subjects)
        for k = 1:numel(subjects(s).steps)
            collector = collectorFor(subjects(s).steps(k).transformId);
            if ~isempty(collector) && ~any(strcmp(names, collector))
                names{end + 1} = collector; %#ok<AGROW>
            end
        end
    end
end

function ids = uniqueTransformIds(subjects)
    ids = {};
    for s = 1:numel(subjects)
        ids = [ids, {subjects(s).steps.transformId}]; %#ok<AGROW>
    end
    ids = unique(ids, 'stable');
end

function lines = binScriptLines(sidecars)
%BINSCRIPTLINES  Read each bin script back from its own file. Kept beside
%   the .m rather than inlined, so it stays readable and editable as a bin
%   script; scriptDir resolves it wherever the pair is moved to.
    if isempty(sidecars)
        lines = {};
        return;
    end
    lines = { ...
        '%% Bin scripts' ...
        '    % Kept as their own files beside this one, in the form they were' ...
        '    % written. Edit the .binscript, not a string in here.' ...
        };
    for i = 1:numel(sidecars)
        lines{end + 1} = sprintf('    %s = fileread(fullfile(scriptDir, %s));', ...
            sidecars(i).variable, matlabLiteral(sidecars(i).name)); %#ok<AGROW>
    end
    lines{end + 1} = '';
end

function lines = optionLines(book)
    if isempty(book)
        lines = {};
        return;
    end
    lines = { ...
        '%% Options' ...
        '    % Every step below refers to these, so a threshold or a window is' ...
        '    % changed here once rather than at each place it is used.' ...
        };
    for i = 1:numel(book)
        % Where one transformation has more than one set of options, the
        % names alone (opt_X, opt_X_2) do not say which recordings ran
        % which, and working it out means reading the whole pipeline. That
        % difference is usually the single most interesting thing in the
        % script, so it is spelled out here.
        if ~isempty(book(i).usedBy) && book(i).shared
            lines{end + 1} = sprintf('    %% used by: %s', ...
                describeUsers(book(i).usedBy)); %#ok<AGROW>
        end
        lines = [lines, optionAssignment(book(i))]; %#ok<AGROW>
    end
    lines{end + 1} = '';
end

function lines = optionAssignment(entry)
%OPTIONASSIGNMENT  One option set, with the fields that are at their
%   default marked.
%
%   Marked, not omitted. Omitting would make the script's meaning depend on
%   the app's defaults when it runs, so changing a default later would
%   silently change what an old script does; a comment says the same thing
%   and changes nothing. Text after a "..." continuation is ignored by
%   MATLAB, which is what makes a per-field comment possible inside a
%   struct() call at all.
%
%   Falls back to the plain one-line form when no defaults are known for
%   this transformation, so a script gains nothing but noise from the
%   transformations whose defaults cannot be read (see transformDefaults).
    defaults = transformDefaults(entry.transformId);
    params = entry.params;
    if isempty(fieldnames(defaults)) || ~isstruct(params) || ~isscalar(params) ...
            || isempty(fieldnames(params))
        lines = {sprintf('    %s = %s;', entry.variable, matlabLiteral(params, 4))};
        return;
    end

    names = fieldnames(params);
    atDefault = false(1, numel(names));
    for i = 1:numel(names)
        atDefault(i) = isfield(defaults, names{i}) ...
            && isequaln(defaults.(names{i}), params.(names{i}));
    end
    if ~any(atDefault)
        lines = {sprintf('    %s = %s;', entry.variable, matlabLiteral(params, 4))};
        return;
    end

    lines = {sprintf('    %s = struct( ...', entry.variable)};
    for i = 1:numel(names)
        value = params.(names{i});
        literal = matlabLiteral(value, 8);
        if iscell(value)
            % struct() reads a bare cell as "one element per cell", so a
            % genuinely cell-valued field needs the extra braces. Same rule
            % matlabLiteral's own struct writer applies.
            literal = ['{' literal '}'];
        end
        if i < numel(names)
            tail = ', ...';
        else
            tail = ' ...';
        end
        comment = '';
        if atDefault(i)
            comment = '   % default';
        end
        lines{end + 1} = sprintf('        ''%s'', %s%s%s', ...
            names{i}, literal, tail, comment); %#ok<AGROW>
    end
    lines{end + 1} = '    );';
end

function text = describeUsers(names)
%DESCRIBEUSERS  The recordings using one option set, abbreviated once the
%   list is long enough that reading it in full tells you nothing.
    if numel(names) > 6
        text = sprintf('%s and %d others', strjoin(names(1:3), ', '), numel(names) - 3);
    else
        text = strjoin(names, ', ');
    end
end

% ======================================================================= %
%  The pipeline itself
% ======================================================================= %
function lines = pipelineLines(subjects, groups, book)
    lines = {};
    for g = 1:numel(groups)
        members = groups(g).indices;
        if numel(members) > 1
            lines = [lines, loopedGroupLines(subjects, members, book)]; %#ok<AGROW>
        else
            lines = [lines, oneSubjectLines(subjects(members(1)), members(1), book)]; %#ok<AGROW>
        end
    end
end

function lines = loopedGroupLines(subjects, members, book)
    template = subjects(members(1));

    fileNames = cell(1, numel(members));
    names     = cell(1, numel(members));
    for i = 1:numel(members)
        fileNames{i} = cacheNameFor(subjects(members(i)));
        names{i}     = char(subjects(members(i)).name);
    end

    % A recording's display name is almost always just its file name without
    % the extension, so carrying a second list of them is noise that can also
    % fall out of step with the first. Emitted only when a name genuinely
    % differs from its own stem.
    namesDiffer = ~all(cellfun(@(f, n) strcmp(stemOf(f), n), fileNames, names));

    % The explicit list is the record of what was actually run, and is what
    % makes this script reproduce that analysis rather than merely describe
    % it. But re-running over a whole folder is the obvious next thing to
    % want, most often to take in recordings added since, so the way to do
    % that is written down rather than left to be worked out. Only the
    % cache root is listed: the per-recording subfolders below it hold the
    % intermediate steps, not datasets to start from.
    lines = { ...
        sprintf('%%%% %d recordings, processed identically', numel(members)) ...
        sprintf('    recordings = %s;', matlabLiteral(fileNames, 4)) ...
        '' ...
        '    % To run over every recording in the cache instead of just these,' ...
        '    % replace the list above with:' ...
        '    %     found = dir(fullfile(cacheDir, ''*.mat''));' ...
        '    %     recordings = {found.name};' ...
        };
    if namesDiffer
        lines{end + 1} = sprintf('    names      = %s;', matlabLiteral(names, 4));
    end
    lines{end + 1} = '';
    lines{end + 1} = '    for r = 1:numel(recordings)';
    if namesDiffer
        lines{end + 1} = '        thisName = names{r};';
    else
        lines{end + 1} = '        [~, thisName] = fileparts(recordings{r});';
    end
    lines{end + 1} = '        fprintf(''%s (%d of %d)\n'', thisName, r, numel(recordings));';
    lines{end + 1} = '        try';
    lines{end + 1} = ['            ' loadLine(template, 'recordings{r}')];
    lines{end + 1} = '';

    lines = [lines, stepLines(template.steps, book, 'v', 12, 'thisName')];

    lines{end + 1} = '        catch err';
    lines{end + 1} = '            failures(end + 1) = struct(''name'', thisName, ''message'', err.message);';
    lines{end + 1} = '            warning(''Alakazam:analysis'', ''%s failed: %s'', thisName, err.message);';
    lines{end + 1} = '        end';
    lines{end + 1} = '    end';
    lines{end + 1} = '';
end

function lines = oneSubjectLines(subject, index, book)
    lines = { ...
        sprintf('%%%% %s', subject.name) ...
        sprintf('    thisName = %s;', matlabLiteral(char(subject.name))) ...
        '    try' ...
        ['        ' loadLine(subject)] ...
        '' ...
        };
    % The same v_ prefix the loop uses, not one derived from the recording.
    % Blocks run one after another in a single function, so each simply
    % reassigns the same variables; a per-block prefix would suggest the
    % names mattered across blocks, which they do not, and would make the
    % same pipeline read differently depending on whether its recording
    % happened to be grouped.
    lines = [lines, stepLines(subject.steps, book, 'v', 8, 'thisName')]; %#ok<*INUSD>
    lines{end + 1} = '    catch err';
    lines{end + 1} = '        failures(end + 1) = struct(''name'', thisName, ''message'', err.message);';
    lines{end + 1} = '        warning(''Alakazam:analysis'', ''%s failed: %s'', thisName, err.message);';
    lines{end + 1} = '    end';
    lines{end + 1} = '';
end

function lines = stepLines(steps, book, prefix, indent, nameExpression)
%STEPLINES  One call per step, each holding its result in its own variable
%   so a fork starts from the right dataset. collectBranchTree guarantees a
%   parent is listed before its children, so a variable is always assigned
%   before it is read.
    pad = repmat(' ', 1, indent);
    lines = {};
    varOf = cell(1, numel(steps));
    for k = 1:numel(steps)
        step = steps(k);
        if step.parent < 1
            inputVar = 'EEG';
        else
            inputVar = varOf{step.parent};
        end
        % makeValidName over the WHOLE name, not just the transformation:
        % a recording called "11_P3_corrected" would otherwise produce
        % 11_P3_corrected_Baseline, which is not a legal identifier because
        % it starts with a digit (makeValidName prefixes an x).
        outputVar = uniqueName(matlab.lang.makeValidName( ...
            sprintf('%s_%s', prefix, step.transformId)), varOf);
        varOf{k} = outputVar;

        lines{end + 1} = sprintf('%s%s = %s(%s, %s);', pad, outputVar, ...
            step.transformId, inputVar, optionExpression(book, step)); %#ok<AGROW>
        % Results worth keeping past the end of the loop are collected as
        % they are produced. Without this a Measure result is computed and
        % then thrown away when the next recording overwrites the variable,
        % which is the one step whose whole output is the numbers it
        % produces.
        collector = collectorFor(step.transformId);
        if ~isempty(collector)
            lines{end + 1} = sprintf('%s%s(end + 1) = struct(''name'', %s, ''EEG'', %s);', ...
                pad, collector, nameExpression, outputVar); %#ok<AGROW>
        end
    end
    lines{end + 1} = '';
end

function collector = collectorFor(transformId)
%COLLECTORFOR  Which vector a step's result is appended to, or '' when its
%   result is only an input to the next step.
%
%   Average feeds the grand averages. Measure's whole output is the numbers
%   it puts on the dataset (EEG.measurements), so a script that computes
%   them and lets the next recording overwrite the variable has done the
%   work and discarded the result.
    switch lower(char(transformId))
        case 'average';        collector = 'averages';
        case 'measure';        collector = 'measures';
        case 'spectralmeasure'; collector = 'spectralMeasures';
        otherwise;             collector = '';
    end
end

function name = uniqueName(candidate, existing)
%UNIQUENAME  Disambiguate a repeated transformation in one chain (two
%   Filter steps, say), which would otherwise assign the same variable
%   twice and make the second silently overwrite the first.
    name = candidate;
    n = 1;
    used = existing(~cellfun(@isempty, existing));
    while any(strcmp(used, name))
        n = n + 1;
        name = sprintf('%s_%d', candidate, n);
    end
end

function line = loadLine(subject, nameExpression)
%LOADLINE  Read the imported recording back from the workspace cache.
%
%   The cache holds each recording as it stood immediately after import,
%   already in Alakazam's own struct form. Reading that is both faster and
%   smaller than re-reading the original .set or BrainVision files, it needs
%   no format reader, and it is guaranteed to be present for anything the
%   workspace has processed. Re-importing would also risk starting from
%   something subtly different if the reader or the raw file ever changed.
%
%   The raw readers are still documented in the Setup section, so the script
%   can be repointed at the original recordings if the cache is not
%   available where it runs.
%
%   NAMEEXPRESSION, when given, replaces the file name literal, so one
%   builder serves both a single recording and a loop over several.
%   Returned WITHOUT indentation; the caller pads it to match the block it
%   sits in. It used to carry its own four spaces, which left it hanging out
%   of the try block it belongs to.
    if nargin < 2 || isempty(nameExpression)
        nameExpression = matlabLiteral(cacheNameFor(subject));
    end
    line = sprintf('loaded = load(fullfile(cacheDir, %s), ''EEG''); EEG = loaded.EEG;', ...
        nameExpression);
end

function name = cacheNameFor(subject)
%CACHENAMEFOR  The recording's own file in the cache root: its stem, .mat.
    if isfield(subject, 'cacheFile') && ~isempty(subject.cacheFile)
        [~, stem, ext] = fileparts(subject.cacheFile);
        name = [stem ext];
        return;
    end
    [~, stem] = fileparts(subject.rawFile);
    name = [stem '.mat'];
end

% ======================================================================= %
%  Grand averages
% ======================================================================= %
function lines = grandAverageLines(grandAverages)
    if isempty(grandAverages)
        lines = { ...
            '%% Grand averages' ...
            '    % This workspace had no grand averages defined when the script was' ...
            '    % exported. GrandAverage takes a cell array of saved Average files:' ...
            '    %     GA = GrandAverage({''sub01.mat'', ''sub02.mat''}, false);' ...
            '' ...
            };
        return;
    end

    lines = { ...
        '%% Grand averages' ...
        '    % GrandAverage reads saved files rather than in-memory structs, so each' ...
        '    % subject average is written out first. Worth doing in its own right:' ...
        '    % it is what makes a re-run cheap.' ...
        '    averageFiles = cell(1, numel(averages));' ...
        '    for k = 1:numel(averages)' ...
        '        averageFiles{k} = fullfile(outDir, sprintf(''%s_average.mat'', ...' ...
        '            matlab.lang.makeValidName(averages(k).name)));' ...
        '        EEG = averages(k).EEG; %#ok<NASGU>' ...
        '        save(averageFiles{k}, ''EEG'');' ...
        '    end' ...
        '' ...
        };

    for g = 1:numel(grandAverages)
        ga = grandAverages(g);
        wanted = getOr(ga, 'subjects', {});
        lines{end + 1} = sprintf('    %% %s', ga.name); %#ok<AGROW>
        % What the grand average REPRESENTS, when it came from a design
        % cell, not only which recordings went into it. The recordings are
        % still listed literally below: this script is a record of what was
        % run, so widening it to whoever is in the cell now is the reader's
        % decision rather than something it does silently.
        cellText = getOr(ga, 'cell', '');
        if ~isempty(cellText)
            lines{end + 1} = sprintf('    %% Design cell: %s', cellText); %#ok<AGROW>
        end
        if isempty(wanted)
            lines{end + 1} = ['    % Built from every average above (the recordings behind it ' ...
                'could not be']; %#ok<AGROW>
            lines{end + 1} = '    % resolved from the saved result; edit the list if it was a subset).'; %#ok<AGROW>
            lines{end + 1} = sprintf('    ga%dFiles = averageFiles;', g); %#ok<AGROW>
        else
            lines{end + 1} = sprintf('    %% Built from %d of the recordings above.', numel(wanted)); %#ok<AGROW>
            lines{end + 1} = sprintf('    ga%dFiles = filesFor(averageFiles, {averages.name}, %s);', ...
                g, matlabLiteral(wanted, 4)); %#ok<AGROW>
        end
        lines{end + 1} = sprintf('    ga%d = GrandAverage(ga%dFiles, %s);', ...
            g, g, matlabLiteral(logical(ga.weighted))); %#ok<AGROW>
        lines{end + 1} = sprintf('    ga%d.id = %s;', g, matlabLiteral(char(ga.name))); %#ok<AGROW>
        lines{end + 1} = sprintf('    save(fullfile(outDir, %s), ''-struct'', ''ga%d'');', ...
            matlabLiteral([matlab.lang.makeValidName(char(ga.name)) '.mat']), g); %#ok<AGROW>
        lines{end + 1} = ''; %#ok<AGROW>
    end
end

function lines = summaryLines(subjects)
    lines = {'%% Summary'};
    if any(strcmp(collectorsUsed(subjects), 'measures'))
        lines = [lines, { ...
            '    % Each entry''s EEG.measurements holds that recording''s scores.' ...
            '    % exportMeasurementsCSV writes them all out as one long-format' ...
            '    % table if a statistics package is the next stop.' ...
            '    fprintf(''Measured %d recording(s).\n'', numel(measures));'}];
    end
    lines = [lines, { ...
        '    fprintf(''\nDone: %d average(s) written to %s\n'', numel(averages), outDir);' ...
        '    if ~isempty(failures)' ...
        '        fprintf(''%d recording(s) failed:\n'', numel(failures));' ...
        '        for k = 1:numel(failures)' ...
        '            fprintf(''    %s: %s\n'', failures(k).name, failures(k).message);' ...
        '        end' ...
        '    end' ...
        ''}];
end

function lines = helperLines()
%HELPERLINES  The two small helpers the generated script calls. Emitted as
%   subfunctions rather than assumed to be on the path, so the script stays
%   a single self-contained file.
    lines = { ...
        'function requireFunctions(names)' ...
        '%REQUIREFUNCTIONS  Fail early, and say what is missing, rather than' ...
        '%   halfway through a long batch on the first call that needs it.' ...
        '    missing = names(cellfun(@(n) exist(n, ''file'') ~= 2, names));' ...
        '    if ~isempty(missing)' ...
        '        error(''Alakazam:analysis'', ...' ...
        '            [''These transformations are not on the MATLAB path: %s.\n'' ...' ...
        '             ''Add Alakazam''''s src/ folder (see the Setup section above).''], ...' ...
        '            strjoin(missing, '', ''));' ...
        '    end' ...
        'end' ...
        '' ...
        'function files = filesFor(allFiles, allNames, wanted)' ...
        '%FILESFOR  The saved averages for WANTED, in the order they were' ...
        '%   listed. A recording that failed above is simply absent, so a' ...
        '%   grand average is built from whatever survived rather than' ...
        '%   erroring on a missing name.' ...
        '    files = {};' ...
        '    for i = 1:numel(wanted)' ...
        '        hit = find(strcmp(allNames, wanted{i}), 1);' ...
        '        if ~isempty(hit)' ...
        '            files{end + 1} = allFiles{hit}; %#ok<AGROW>' ...
        '        end' ...
        '    end' ...
        '    if numel(files) < 2' ...
        '        error(''Alakazam:analysis'', ...' ...
        '            ''Only %d of the %d recording(s) this grand average needs are available.'', ...' ...
        '            numel(files), numel(wanted));' ...
        '    end' ...
        'end' ...
        ''};
end

% ======================================================================= %
function stem = stemOf(fileName)
    [~, stem, ~] = fileparts(fileName);
end

function value = getOr(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        value = s.(name);
    else
        value = default;
    end
end
