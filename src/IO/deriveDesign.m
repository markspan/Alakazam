function design = deriveDesign(recordings)
%DERIVEDESIGN  What study design the workspace's own records amount to.
%
%   DESIGN = DERIVEDESIGN(RECORDINGS) reads the design out of what has
%   already been recorded rather than asking anyone to state it: bin levels
%   come from each Average's bindesc, group and session levels from
%   WorkSpace.Groups. Nothing here is authored, so the design cannot
%   disagree with the data it describes; renaming a bin or regrouping a
%   recording moves the design with it.
%
%   RECORDINGS is a struct array, one element per Averaged dataset:
%     .name     the recording's own name (a root node's name)
%     .person   the real person it belongs to (WorkSpace.personFor, which
%               falls back to .name, so unlinked recordings are their own
%               person)
%     .group    between-subjects group, '' when unassigned
%     .session  session label, '' when unassigned
%     .bins     cellstr of that dataset's ORDINARY bin labels
%
%   Returns a struct describing the design:
%     .factors   struct array (name, type, levels, source, note)
%     .cells     struct array (group, session, nPersons, nRecordings,
%                persons) -- one per combination of the factors that
%                actually partition recordings
%     .persons   struct array (name, group, sessions, recordings)
%     .warnings  cellstr, things worth seeing before running statistics
%     .nRecordings, .nPersons
%
%   WHICH FACTORS PARTITION WHAT. The three recorded factors sit at
%   different levels, and treating them alike would produce meaningless
%   counts:
%     * GROUP partitions PERSONS. One person is in one group.
%     * SESSION partitions a person's RECORDINGS. A person may appear in
%       several sessions.
%     * BIN is within a recording: every Average carries every bin, so bin
%       does not split anyone. It is reported as a factor, but the cell
%       counts below cross only group and session.
%   Counting bins into the cells would multiply every n by the number of
%   conditions and make an eighteen-person study look like fifty-four.
%
%   Read-only and side-effect free. Nothing in the app behaves differently
%   because this was called; see Alakazam.onShowDesign, which only displays
%   it.
%
%   See also ALAKAZAM.ONSHOWDESIGN, DESIGNSUMMARYDIALOG, WORKSPACE.EDITSUBJECTS.
    design = struct('factors', {emptyFactors()}, 'cells', {emptyCells()}, ...
        'persons', {emptyPersons()}, 'warnings', {{}}, ...
        'nRecordings', 0, 'nPersons', 0, 'nExcluded', 0, 'excluded', {{}});
    if isempty(recordings)
        design.warnings = {['No averaged datasets were found, so there is no design to read. ' ...
            'Run Average on at least one recording.']};
        return;
    end

    % Excluded recordings are set aside before anything is derived: they are
    % not in the study, so they must not appear in a level, a cell count or
    % a factor. They are still counted and named, because "four recordings
    % are excluded" is exactly the kind of thing this panel exists to say
    % out loud rather than leave to be noticed.
    included = recordings(includedMask(recordings));
    excluded = recordings(~includedMask(recordings));

    design.nRecordings = numel(included);
    design.nExcluded = numel(excluded);
    design.excluded = unique({excluded.name}, 'stable');

    if isempty(included)
        design.warnings = {sprintf(['Every one of the %d averaged recording(s) is excluded from ' ...
            'the study, so there is nothing to analyse. Tick some back in under Grouping.'], ...
            numel(excluded))};
        return;
    end

    design.persons = collectPersons(included);
    design.nPersons = numel(design.persons);
    design.factors = collectFactors(included, design.persons);
    design.cells = collectCells(included, design.persons);
    design.warnings = collectWarnings(included, design);

    if ~isempty(excluded)
        design.warnings = [{sprintf('%d recording(s) excluded from the study: %s.', ...
            numel(design.excluded), strjoin(design.excluded, ', '))}, design.warnings];
    end
end

function mask = includedMask(recordings)
%INCLUDEDMASK  Which recordings are in the study. Absent field means
%   included: a caller that predates exclusion, or a workspace saved before
%   it existed, describes a study where everything counts.
    if ~isfield(recordings, 'included')
        mask = true(1, numel(recordings));
        return;
    end
    mask = arrayfun(@(r) isempty(r.included) || logical(r.included), recordings);
end

% ======================================================================= %
function persons = collectPersons(recordings)
%COLLECTPERSONS  One row per real person, with the recordings behind them.
%   .group is the group of their recordings; a person whose recordings
%   disagree keeps the first and is reported in the warnings, since which
%   one is right is not something this can decide.
    persons = emptyPersons();
    names = unique({recordings.person}, 'stable');
    for i = 1:numel(names)
        mine = recordings(strcmp({recordings.person}, names{i}));
        groups = unique(nonBlank({mine.group}), 'stable');
        if isempty(groups)
            group = '';
        else
            group = groups{1};
        end
        persons(end + 1) = struct( ...
            'name', names{i}, ...
            'group', group, ...
            'groupsSeen', {groups}, ...
            'sessions', {unique(nonBlank({mine.session}), 'stable')}, ...
            'recordings', {{mine.name}}); %#ok<AGROW>
    end
end

function factors = collectFactors(recordings, persons)
%COLLECTFACTORS  The factors the records actually support. A factor with
%   fewer than two levels is still listed, with a note, because "you have
%   one group" is exactly the kind of thing worth seeing before a report
%   quietly declines to run a between-subjects test.
    factors = emptyFactors();

    binLevels = unique([recordings.bins], 'stable');
    factors(end + 1) = struct('name', 'bin', 'type', 'within', ...
        'levels', {binLevels}, 'source', 'each Average''s own bindesc', ...
        'note', binNote(recordings, binLevels)); %#ok<AGROW>

    sessionLevels = unique(nonBlank({recordings.session}), 'stable');
    factors(end + 1) = struct('name', 'session', 'type', 'within', ...
        'levels', {sessionLevels}, 'source', 'Edit Subjects', ...
        'note', levelNote(sessionLevels, ['no session labels assigned, so session is ' ...
            'not a factor here'])); %#ok<AGROW>

    groupLevels = unique(nonBlank({persons.group}), 'stable');
    factors(end + 1) = struct('name', 'group', 'type', 'between', ...
        'levels', {groupLevels}, 'source', 'Edit Subjects', ...
        'note', levelNote(groupLevels, ['no groups assigned, so every report is ' ...
            'within-subject'])); %#ok<AGROW>
end

function note = binNote(recordings, binLevels)
%BINNOTE  Whether every recording carries the same bins. A dataset with a
%   different set is not a design problem in itself, but it is the reason a
%   later grand average or report will refuse to combine them, and it is
%   better seen here.
    note = '';
    if isempty(binLevels)
        note = 'no bins found; these datasets were averaged without DefineBins';
        return;
    end
    for i = 1:numel(recordings)
        if ~isequal(sort(recordings(i).bins), sort(binLevels))
            note = 'not every recording has the same bins';
            return;
        end
    end
end

function note = levelNote(levels, whenEmpty)
    if isempty(levels)
        note = whenEmpty;
    elseif isscalar(levels)
        note = 'only one level, so nothing to compare';
    else
        note = '';
    end
end

% ======================================================================= %
function cells = collectCells(recordings, persons)
%COLLECTCELLS  One row per combination of the factors that partition
%   recordings: group (through the person) crossed with session. Counted in
%   PERSONS as well as recordings, because a between-subjects test's own n
%   is the number of people, not the number of files.
    cells = emptyCells();
    groupLevels = levelsOrPlaceholder(unique(nonBlank({persons.group}), 'stable'), '(no group)');
    sessionLevels = levelsOrPlaceholder(unique(nonBlank({recordings.session}), 'stable'), '(no session)');

    groupOf = containers.Map({persons.name}, {persons.group});

    for g = 1:numel(groupLevels)
        for s = 1:numel(sessionLevels)
            mine = recordings(arrayfun(@(r) ...
                matchesLevel(groupOf(r.person), groupLevels{g}, '(no group)') && ...
                matchesLevel(r.session, sessionLevels{s}, '(no session)'), recordings));
            cells(end + 1) = struct( ...
                'group', groupLevels{g}, ...
                'session', sessionLevels{s}, ...
                'nPersons', numel(unique({mine.person})), ...
                'nRecordings', numel(mine), ...
                'persons', {unique({mine.person}, 'stable')}, ...
                'recordings', {{mine.name}}); %#ok<AGROW>
        end
    end
end

function tf = matchesLevel(value, level, placeholder)
%MATCHESLEVEL  Whether VALUE belongs to LEVEL, where the placeholder level
%   stands for "this field was left blank".
    if strcmp(level, placeholder)
        tf = isempty(strtrim(char(value)));
    else
        tf = strcmp(char(value), level);
    end
end

function levels = levelsOrPlaceholder(levels, placeholder)
%LEVELSORPLACEHOLDER  A single placeholder level when nothing is assigned,
%   so the cell table still has one row per real combination rather than
%   collapsing to nothing.
    if isempty(levels)
        levels = {placeholder};
    end
end

% ======================================================================= %
function warnings = collectWarnings(recordings, design)
%COLLECTWARNINGS  What is worth seeing before a report is run. Every entry
%   describes something that will otherwise be discovered as a surprising
%   result, a refused test, or a silently dropped subject.
    warnings = {};

    empties = design.cells([design.cells.nPersons] == 0);
    for i = 1:numel(empties)
        warnings{end + 1} = sprintf('No recordings in %s / %s.', ...
            empties(i).group, empties(i).session); %#ok<AGROW>
    end

    filled = design.cells([design.cells.nPersons] > 0);
    if numel(filled) > 1
        counts = [filled.nPersons];
        if max(counts) >= 3 * min(counts)
            [~, small] = min(counts);
            [~, big] = max(counts);
            warnings{end + 1} = sprintf( ...
                'Cells are markedly unbalanced: %s / %s has %d, %s / %s has %d.', ...
                filled(small).group, filled(small).session, min(counts), ...
                filled(big).group, filled(big).session, max(counts)); %#ok<AGROW>
        end
    end

    % A person cannot be in two between-subjects groups; if their
    % recordings disagree, every grouped test is reading one of them.
    for i = 1:numel(design.persons)
        if numel(design.persons(i).groupsSeen) > 1
            warnings{end + 1} = sprintf( ...
                '"%s" has recordings in more than one group (%s); only "%s" is used.', ...
                design.persons(i).name, strjoin(design.persons(i).groupsSeen, ', '), ...
                design.persons(i).group); %#ok<AGROW>
        end
    end

    % A person labelled on some recordings and not others. The group still
    % resolves, from whichever recording carries it, so nothing downstream
    % complains -- which is exactly why it is worth saying here: a group
    % filled in for day 1 and forgotten for day 2 looks like a complete
    % study right up until someone reads the Edit Subjects table.
    for i = 1:numel(design.persons)
        theirs = recordings(strcmp({recordings.person}, design.persons(i).name));
        labelled = numel(nonBlank({theirs.group}));
        if labelled > 0 && labelled < numel(theirs)
            warnings{end + 1} = sprintf( ...
                '"%s" has a group on %d of %d recordings; the rest are blank.', ...
                design.persons(i).name, labelled, numel(theirs)); %#ok<AGROW>
        end
    end

    % Repeated sessions for one person: two recordings labelled Day 1 are
    % either a duplicate import or a mislabelling, and both matter.
    for i = 1:numel(design.persons)
        theirs = recordings(strcmp({recordings.person}, design.persons(i).name));
        labels = nonBlank({theirs.session});
        if numel(labels) > numel(unique(labels))
            warnings{end + 1} = sprintf('"%s" has more than one recording in the same session.', ...
                design.persons(i).name); %#ok<AGROW>
        end
    end

    % Partly-assigned group: the report drops the unassigned ones, and
    % today it does so on the strength of a blank field.
    assigned = nonBlank({design.persons.group});
    if ~isempty(assigned) && numel(assigned) < numel(design.persons)
        warnings{end + 1} = sprintf( ...
            '%d of %d subjects have no group assigned; grouped tests leave them out.', ...
            numel(design.persons) - numel(assigned), numel(design.persons)); %#ok<AGROW>
    end

    binFactor = design.factors(strcmp({design.factors.name}, 'bin'));
    if ~isempty(binFactor) && ~isempty(binFactor(1).note)
        warnings{end + 1} = ['Bins: ' binFactor(1).note '.']; %#ok<AGROW>
    end
end

% ======================================================================= %
function values = nonBlank(values)
    values = values(~cellfun(@(v) isempty(strtrim(char(v))), values));
end

function s = emptyFactors()
    s = struct('name', {}, 'type', {}, 'levels', {}, 'source', {}, 'note', {});
end

function s = emptyCells()
%EMPTYCELLS  Must carry every field collectCells assigns: appending a
%   struct with more fields than the array was declared with is a hard
%   "dissimilar structures" error, and adding .recordings without adding it
%   here took out the whole suite at once.
    s = struct('group', {}, 'session', {}, 'nPersons', {}, 'nRecordings', {}, ...
        'persons', {}, 'recordings', {});
end

function s = emptyPersons()
    s = struct('name', {}, 'group', {}, 'groupsSeen', {}, 'sessions', {}, 'recordings', {});
end
