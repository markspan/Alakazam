function created = newTransformation(name, varargin)
%NEWTRANSFORMATION  Create a new transformation from the contract's
%   scaffold: its entry function, manifest and icon, a test class, a manual
%   section, and its place on the Recalculate list.
%
%   CREATED = newTransformation(NAME, Name, Value, ...) writes
%     src/Transformations/NAME/NAME.m     the entry function: InitGuard, a
%                                         generated dialog seeded from the
%                                         last run, replay, an input check,
%                                         and a marked place for the method
%                                         and its provenance record
%     src/Transformations/NAME/NAME.json  the manifest, which is what puts
%                                         it on the ribbon
%     src/Transformations/NAME/NAME.png   a placeholder icon, and its source
%     src/Icons/NAME.svg                  (redraw, then rasterize; below)
%     tests/NAMETest.m                    replay, shape and record tests to
%                                         extend with what the method must
%                                         get right
%   adds a reference section to the manual chapter of its ribbon section,
%   with an options table built from the fields, and adds NAME to
%   WorkSpaceTree.RecalculableTransforms when it has options to reseed.
%   CREATED lists every file written or changed. Nothing is overwritten: an
%   existing folder or test is an error.
%
%   Options:
%     'Section'      the ribbon group, e.g. '1. Preprocessing' (default);
%                    one of the five existing sections or a new one
%     'Category'     the manifest's category (default 'EEG')
%     'Description'  one sentence: the ribbon tooltip, the dialog's text
%                    and the manual section's first line
%     'Input'        'continuous', 'epoched', 'averaged' or 'any'
%                    (default): what the step refuses to run on
%     'Fields'       the dialog's fields, a struct array with .label,
%                    .name (the options field), .default (a plain value:
%                    number, logical, text, or a cellstr of choices) and,
%                    optionally, .help (the manual's "Meaning") and .kind
%                    ('channels' or 'bins' for a picker of the dataset's
%                    own, stored by label). No fields: no dialog, and the
%                    step is not recalculable.
%     'Repository'   the Alakazam checkout to write into (default: this
%                    one). Tests pass a temporary copy.
%     'Manual'       false to skip the manual section (default true)
%
%   After it runs: write the method where the entry function says, describe
%   it in its header and the manual section, redraw the icon and rasterize
%   it with
%       node src/webtree/rasterize.mjs src/Icons/NAME.svg ...
%            src/Transformations/NAME/NAME.png 24
%   and work through the rest of DEVELOPER.md's checklist (a provenance row
%   if it wraps a toolkit, Export as Code if it should be native, the
%   manual's pictures).
%
%   Example:
%       newTransformation('Smooth', 'Section', '1. Preprocessing', ...
%           'Description', 'Smooth each channel with a moving average.', ...
%           'Input', 'any', 'Fields', struct( ...
%               'label', {'Window (ms)', 'Channels'}, 'name', {'WindowMs', 'Channels'}, ...
%               'default', {20, {}}, 'kind', {'', 'channels'}, ...
%               'help', {'The width of the moving average.', 'The channels to smooth.'}));
%
%   See also TRANSFORMOPTIONSDIALOG, DIALOGFIELDS.FIELD, TRANSTOOLS.INVOKE.
    p = inputParser;
    p.addRequired('name', @(n) (ischar(n) || isstring(n)) && isvarname(char(n)));
    p.addParameter('Section', '1. Preprocessing');
    p.addParameter('Category', 'EEG');
    p.addParameter('Description', '');
    p.addParameter('Input', 'any', @(s) any(strcmpi(s, {'continuous', 'epoched', 'averaged', 'any'})));
    p.addParameter('Fields', struct('label', {}, 'name', {}, 'default', {}));
    p.addParameter('Repository', fileparts(fileparts(fileparts(mfilename('fullpath')))));
    p.addParameter('Manual', true);
    p.parse(name, varargin{:});
    o = p.Results;
    name = char(o.name);
    o.Input = lower(char(o.Input));
    o.Description = char(o.Description);
    if isempty(o.Description)
        o.Description = sprintf('%s: describe what it does in one sentence.', name);
    end
    fields = normaliseFields(o.Fields);

    root = char(o.Repository);
    folder = fullfile(root, 'src', 'Transformations', name);
    testFile = fullfile(root, 'tests', [name 'Test.m']);
    if isfolder(folder)
        throw(MException('Alakazam:newTransformation', ...
            'I''m afraid %s already exists; choose another name, or remove it first.', folder));
    end
    if isfile(testFile)
        throw(MException('Alakazam:newTransformation', ...
            'I''m afraid %s already exists; choose another name, or remove it first.', testFile));
    end

    mkdir(folder);
    created = {};
    created{end + 1} = writeText(fullfile(folder, [name '.m']), entryFunction(name, o, fields));
    created{end + 1} = writeText(fullfile(folder, [name '.json']), manifest(name, o));
    template = fullfile(fileparts(mfilename('fullpath')), 'newTransformationTemplate');
    copyfile(fullfile(template, 'placeholder.png'), fullfile(folder, [name '.png']));
    created{end + 1} = fullfile(folder, [name '.png']);
    iconSource = fullfile(root, 'src', 'Icons', [name '.svg']);
    if ~isfile(iconSource)
        copyfile(fullfile(template, 'placeholder.svg'), iconSource);
        created{end + 1} = iconSource;
    end
    created{end + 1} = writeText(testFile, testClass(name, o, fields));

    if o.Manual
        chapter = manualChapter(root, o.Section);
        if ~isempty(chapter)
            appendText(chapter, manualSection(name, o, fields));
            created{end + 1} = chapter;
        else
            warning('Alakazam:newTransformation', ['No manual chapter covers the section ' ...
                '"%s"; add a section headed "## %s {#sec-tr-%s}" where it belongs.'], ...
                o.Section, name, lower(name));
        end
    end

    if ~isempty(fields)
        treeFile = fullfile(root, 'src', 'WorkSpaceTree.m');
        if addToRecalculable(treeFile, name)
            created{end + 1} = treeFile;
        else
            warning('Alakazam:newTransformation', ['Could not find RecalculableTransforms in ' ...
                '%s; add ''%s'' to it by hand.'], treeFile, name);
        end
    end

    created = unique(created, 'stable');
    fprintf('newTransformation: created %s. Write the method in %s, then see DEVELOPER.md.\n', ...
        name, fullfile(folder, [name '.m']));
end

% ======================================================================= %
%  The files
% ======================================================================= %
function text = entryFunction(name, o, fields)
    lines = { ...
        sprintf('function [EEG, options] = %s(input, varargin)', name), ...
        sprintf('%%%% %s  %s', name, o.Description), ...
        '%', ...
        '%   Describe the method here: what it computes and how, the paper or', ...
        '%   toolbox it follows, and what a user should know before trusting it.', ...
        '%', ...
        sprintf('%%   WHAT IT RECORDS, in EEG.etc.alz.%s: the options it ran with. Add', recordName(name)), ...
        '%   whatever a methods section or the data-quality report will need.', ...
        '%', ...
        '%   Signature (Alakazam transformation contract):', ...
        sprintf('%%     [EEG, options] = %s(input)        %% interactive dialog', name), ...
        sprintf('%%     [EEG, options] = %s(input, opts)  %% replay a stored options struct', name), ...
        '%', ...
        '%   Made with newTransformation; see DEVELOPER.md, "Adding a transformation".', ...
        sprintf('[opts, interactive] = TransTools.InitGuard(nargin, ''Alakazam:%s'', varargin{:});', name), ...
        ''};
    lines = [lines, inputCheck(name, o.Input)];

    if isempty(fields)
        lines = [lines, { ...
            'if interactive', ...
            '    options = struct();   % no settings to ask for', ...
            'else', ...
            '    options = opts;', ...
            'end', ''}];
    else
        dialog = { ...
            'if interactive', ...
            sprintf('    stored = TransformSettings.get(''%s'');', name), ...
            '    if isempty(stored) || ~isstruct(stored)', ...
            '        stored = struct();', ...
            '    end', ...
            '    d = @(f, v) TransTools.FieldOr(stored, f, v);', ...
            '    options = TransformOptionsDialog( ...', ...
            sprintf('        ''title'', ''%s options'', ...', name), ...
            sprintf('        ''Description'', %s, ...', quoted(o.Description))};
        for k = 1:numel(fields)
            separator = ', ...';
            if k == numel(fields)
                separator = ');';
            end
            dialog{end + 1} = sprintf('        {%s; ''%s''}, %s%s', quoted(fields(k).label), ...
                fields(k).name, fieldDefault(fields(k)), separator); %#ok<AGROW>
        end
        dialog = [dialog, { ...
            '    if isempty(options)', ...
            '        EEG = [];   % cancelled: no node, no compute', ...
            '        return;', ...
            '    end', ...
            sprintf('    TransformSettings.set(''%s'', options);', name), ...
            'else', ...
            '    options = opts;', ...
            'end', ''}];
        lines = [lines, dialog];
    end

    lines = [lines, { ...
        'EEG = input;', ...
        '', ...
        '% ---- the method ------------------------------------------------------ %', ...
        '% Write the computation here. Start from the dataset you were given, as', ...
        '% above, so every field you do not change survives, and keep its shape', ...
        '% fields (nbchan, pnts, trials, times, chanlocs, DataFormat) consistent', ...
        '% with EEG.data. Channels and bins stored in OPTIONS are labels: resolve', ...
        '% them against this dataset (TransTools.LabelsToIdx). See DEVELOPER.md,', ...
        '% "What a transformation may do to the dataset".', ...
        '', ...
        '% ---- what it did ------------------------------------------------------ %', ...
        sprintf('EEG.etc.alz.%s = struct(''options'', options);', recordName(name)), ...
        'end'}];

    if ~strcmp(o.Input, 'any')
        lines = [lines, requireFunction(name, o.Input)];
    end
    text = strjoin(lines, newline);
end

function lines = inputCheck(name, input)
    if strcmp(input, 'any')
        lines = {};
        return;
    end
    lines = {'requireFormat(input);', ''};
end

function lines = requireFunction(name, input)
    lines = { ...
        '', ...
        '% ======================================================================= %', ...
        'function requireFormat(input)', ...
        sprintf('%%REQUIREFORMAT  %s runs on %s data; say so, rather than fail inside.', name, input), ...
        '    format = lower(char(string(TransTools.FieldOr(input, ''DataFormat'', inferDataFormat(input)))));', ...
        sprintf('    if ~strcmp(format, ''%s'')', input), ...
        sprintf('        throw(MException(''Alakazam:%s'', [''I''''m afraid %s works on %s data, '' ...', name, name, input), ...
        '            ''and this dataset is %s.''], format));', ...
        '    end', ...
        'end'};
end

function text = manifest(name, o)
    text = jsonencode(struct('Name', name, 'Description', o.Description, ...
        'Entry', [name '.m'], 'Icon', [name '.png'], 'Section', char(o.Section), ...
        'Category', char(o.Category)));
end

function text = testClass(name, o, fields)
    format = {};
    switch o.Input
        case 'continuous'
            format = {'''DataFormat''', '''CONTINUOUS'''};
        case 'averaged'
            format = {'''trials''', '1', '''DataFormat''', '''Averaged'''};
    end
    fixture = sprintf('makeTestEEG(%s)', strjoin(format, ', '));
    lines = { ...
        sprintf('classdef %sTest < matlab.unittest.TestCase', name), ...
        sprintf('%%%sTEST  Unit tests for %s.', upper(name), name), ...
        '%', ...
        '%   Made with newTransformation: the replay, the shape and the record. Add', ...
        '%   the cases that say what the method must get right, on a fixture whose', ...
        '%   answer is known.', ...
        '%', ...
        sprintf('%%   Run with: runtests(''tests/%sTest.m'').', name), ...
        '', ...
        '    methods (TestClassSetup)', ...
        '        function addSourceToPath(testCase)', ...
        '            root = fileparts(fileparts(mfilename(''fullpath'')));', ...
        sprintf('            for p = {fullfile(root, ''src'', ''Transformations'', ''%s''), ...', name), ...
        '                     fullfile(root, ''src'', ''Transformations''), ...', ...
        '                     fullfile(root, ''src'', ''Support''), ...', ...
        '                     fullfile(root, ''tests'', ''fixtures'')}', ...
        '                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));', ...
        '            end', ...
        '        end', ...
        '    end', ...
        '', ...
        '    methods (Test)', ...
        '        function aReplayGivesTheSameResult(testCase)', ...
        sprintf('            EEG = %s;', fixture), ...
        sprintf('            [first, stored] = %s(EEG, testCase.options());', name), ...
        sprintf('            second = %s(EEG, stored);', name), ...
        '            testCase.verifyEqual(second.data, first.data);', ...
        '        end', ...
        '', ...
        '        function theResultKeepsTheDatasetsShape(testCase)', ...
        '        %THERESULTKEEPSTHEDATASETSSHAPE  Change this if the method changes the', ...
        '        %   shape (a channel added, a spectrum instead of a waveform).', ...
        sprintf('            EEG = %s;', fixture), ...
        sprintf('            out = %s(EEG, testCase.options());', name), ...
        '            testCase.verifyEqual(size(out.data), size(EEG.data));', ...
        '            testCase.verifyEqual(out.DataFormat, EEG.DataFormat);', ...
        '        end', ...
        '', ...
        '        function itRecordsWhatItDid(testCase)', ...
        sprintf('            out = %s(%s, testCase.options());', name, fixture), ...
        sprintf('            testCase.verifyTrue(isfield(out.etc.alz, ''%s''));', recordName(name)), ...
        '        end', ...
        '    end', ...
        '', ...
        '    methods (Static, Access = private)', ...
        '        function opts = options()', ...
        sprintf('            opts = %s;', optionsLiteral(fields)), ...
        '        end', ...
        '    end', ...
        'end'};
    text = strjoin(lines, newline);
end

function text = manualSection(name, o, fields)
    shape = struct('continuous', 'continuous → continuous', 'epoched', 'epoched → epoched', ...
        'averaged', 'averaged → averaged', 'any', 'any time-domain format → the same');
    lines = { ...
        '', ...
        sprintf('## %s {#sec-tr-%s}', name, lower(name)), ...
        '', ...
        sprintf('*Tools > %s > %s · %s · `%s`*', char(o.Section), name, shape.(o.Input), name), ...
        '', ...
        o.Description, ''};
    if ~isempty(fields)
        lines = [lines, { ...
            '| Option | Default | Meaning |', ...
            '|--------|---------|-------------------------------------------------------|'}];
        for k = 1:numel(fields)
            lines{end + 1} = sprintf('| **%s** | %s | %s |', fields(k).label, ...
                manualDefault(fields(k)), fields(k).help); %#ok<AGROW>
        end
        lines = [lines, {'', sprintf(': %s''s options. {#tbl-%s}', name, lower(name))}];
    end
    text = strjoin(lines, newline);
end

% ======================================================================= %
%  Helpers
% ======================================================================= %
function fields = normaliseFields(fields)
%NORMALISEFIELDS  The field descriptions with every member filled in.
    if isempty(fields)
        fields = struct('label', {}, 'name', {}, 'default', {}, 'help', {}, 'kind', {});
        return;
    end
    out = struct('label', {}, 'name', {}, 'default', {}, 'help', {}, 'kind', {});
    for k = 1:numel(fields)
        f = fields(k);
        entry.label = char(f.label);
        entry.name = char(f.name);
        if ~isvarname(entry.name)
            throw(MException('Alakazam:newTransformation', ...
                'I''m afraid "%s" cannot be an options field name.', entry.name));
        end
        entry.default = f.default;
        entry.help = '';
        if isfield(f, 'help') && ~isempty(f.help)
            entry.help = char(f.help);
        end
        entry.kind = '';
        if isfield(f, 'kind') && ~isempty(f.kind)
            entry.kind = lower(char(f.kind));
        end
        out(end + 1) = entry; %#ok<AGROW>
    end
    fields = out;
end

function code = fieldDefault(field)
%FIELDDEFAULT  The dialog argument for one field: a picker of the dataset's
%   channels or bins, or the stored value with a plain default.
    switch field.kind
        case 'channels'
            code = sprintf('DialogFields.Channels(input, d(''%s'', {}))', field.name);
        case 'bins'
            code = sprintf('DialogFields.Bins(input, d(''%s'', {}))', field.name);
        otherwise
            if iscell(field.default)
                code = sprintf('TransTools.PutFirst(%s, d(''%s'', %s))', ...
                    matlabLiteral(field.default), field.name, matlabLiteral(field.default{1}));
            else
                code = sprintf('d(''%s'', %s)', field.name, matlabLiteral(field.default));
            end
    end
end

function code = optionsLiteral(fields)
%OPTIONSLITERAL  The options a replay stores, as the tests' literal.
    if isempty(fields)
        code = 'struct()';
        return;
    end
    parts = cell(1, numel(fields));
    for k = 1:numel(fields)
        value = fields(k).default;
        if any(strcmp(fields(k).kind, {'channels', 'bins'}))
            value = {};
        elseif iscell(value)
            value = value{1};
        end
        if iscell(value)
            parts{k} = sprintf('''%s'', {%s}', fields(k).name, matlabLiteral(value));
        else
            parts{k} = sprintf('''%s'', %s', fields(k).name, matlabLiteral(value));
        end
    end
    code = sprintf('struct(%s)', strjoin(parts, ', '));
end

function text = manualDefault(field)
    value = field.default;
    if any(strcmp(field.kind, {'channels', 'bins'}))
        text = 'none';
    elseif iscell(value)
        text = char(string(value{1}));
    elseif islogical(value)
        onOff = {'off', 'on'};
        text = onOff{value + 1};
    elseif isnumeric(value)
        text = strjoin(arrayfun(@(v) sprintf('%g', v), value(:)', 'UniformOutput', false), ' ');
    else
        text = char(value);
    end
end

function s = quoted(text)
    s = ['''' strrep(char(text), '''', '''''') ''''];
end

function r = recordName(name)
%RECORDNAME  The etc.alz field a step records under: its name, first
%   letter lower-case (DerivedChannels -> derivedChannels), as the others.
    r = [lower(name(1)) name(2:end)];
end

function chapter = manualChapter(root, section)
%MANUALCHAPTER  The reference chapter for a ribbon section, by its number.
    chapters = {'_07-ref-preprocessing.qmd', '_08-ref-artefacts.qmd', ...
        '_09-ref-epoching.qmd', '_10-ref-frequency.qmd', '_11-ref-plots.qmd'};
    number = str2double(regexp(char(section), '^\d+', 'match', 'once'));
    chapter = '';
    if isfinite(number) && number >= 1 && number <= numel(chapters)
        candidate = fullfile(root, 'manual', 'chapters', chapters{number});
        if isfile(candidate)
            chapter = candidate;
        end
    end
end

function added = addToRecalculable(treeFile, name)
%ADDTORECALCULABLE  Put NAME in WorkSpaceTree.RecalculableTransforms, in
%   alphabetical order (ignoring case), editing only that list.
    added = false;
    if ~isfile(treeFile)
        return;
    end
    text = fileread(treeFile);
    [first, last] = regexp(text, 'RecalculableTransforms\s*=\s*\{[^}]*\}', 'once');
    if isempty(first)
        return;
    end
    block = text(first:last);
    names = regexp(block, '''(\w+)''', 'tokens');
    names = [names{:}];
    if any(strcmp(names, name))
        added = true;
        return;
    end
    later = names(cellfun(@(n) sortsAfter(n, name), names));
    if isempty(later)
        newBlock = regexprep(block, '''(\w+)''(\s*)\}$', sprintf('''$1'', ''%s''$2}', name));
    else
        target = sprintf('''%s''', later{1});
        at = strfind(block, target);
        newBlock = [block(1:at(1) - 1), sprintf('''%s'', ', name), block(at(1):end)];
    end
    writeText(treeFile, [text(1:first - 1), newBlock, text(last + 1:end)]);
    added = true;
end

function tf = sortsAfter(a, b)
%SORTSAFTER  True when A comes after B, ignoring case, as the list is kept.
    sorted = sort(lower({a, b}));
    tf = ~strcmpi(a, b) && strcmp(sorted{2}, lower(a));
end

function path = writeText(path, text)
    fid = fopen(path, 'w', 'n', 'UTF-8');
    if fid < 0
        throw(MException('Alakazam:newTransformation', 'I''m afraid %s could not be written.', path));
    end
    closer = onCleanup(@() fclose(fid));
    fwrite(fid, text, 'char');
    if ~endsWith(text, newline)
        fwrite(fid, newline, 'char');
    end
end

function appendText(path, text)
    existing = fileread(path, 'Encoding', 'UTF-8');
    writeText(path, [strip(existing, 'right'), newline, text, newline]);
end
