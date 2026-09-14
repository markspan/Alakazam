function [specs, skipped] = designCellSpecs(design, recordings, weighted)
%DESIGNCELLSPECS  One grand-average spec per design cell.
%
%   [SPECS, SKIPPED] = DESIGNCELLSPECS(DESIGN, RECORDINGS, WEIGHTED) turns
%   the cells DERIVEDESIGN found into the specs Alakazam.saveGrandAverage
%   takes, so a study's grand averages follow from its design rather than
%   from picking files out of a list by hand.
%
%   SPECS is a struct array with the fields saveGrandAverage reads
%   (.name, .sources, .weighted) plus .cell, a struct('group', 'session')
%   recording which cell it came from. That last field is the point of
%   doing this at all: a grand average built by hand knows only which files
%   went into it, so nothing downstream can say what it represents, and
%   after a few months neither can anyone else.
%
%   SKIPPED is a struct array (.group, .session, .reason) of cells that
%   could not become a grand average. A cell is skipped rather than
%   attempted when it holds fewer than two recordings, since GrandAverage
%   itself requires two, and reporting that plainly here is better than
%   letting it throw halfway through a batch.
%
%   Naming follows the cell: "control, Day 1", or just "control" when
%   session is not a factor of this design. Placeholder levels from
%   deriveDesign ("(no group)", "(no session)") are dropped from the name
%   rather than printed, so a workspace with no sessions produces
%   "control" and not "control, (no session)".
%
%   See also DERIVEDESIGN, ALAKAZAM.ONGRANDAVERAGEPERCELL,
%   ALAKAZAM.SAVEGRANDAVERAGE.
    if nargin < 3 || isempty(weighted)
        weighted = false;
    end
    specs = struct('name', {}, 'sources', {}, 'weighted', {}, 'cell', {});
    skipped = struct('group', {}, 'session', {}, 'reason', {});

    if ~isstruct(design) || ~isfield(design, 'cells') || isempty(design.cells)
        return;
    end

    fileOf = containers.Map('KeyType', 'char', 'ValueType', 'char');
    for i = 1:numel(recordings)
        if isfield(recordings(i), 'file') && ~isempty(recordings(i).file)
            fileOf(recordings(i).name) = recordings(i).file;
        end
    end

    for c = 1:numel(design.cells)
        cell = design.cells(c);
        sources = {};
        for r = 1:numel(cell.recordings)
            name = cell.recordings{r};
            if isKey(fileOf, name)
                sources{end + 1} = fileOf(name); %#ok<AGROW>
            end
        end

        if numel(sources) < 2
            skipped(end + 1) = struct('group', cell.group, 'session', cell.session, ...
                'reason', sprintf('only %d recording(s); a grand average needs two', ...
                    numel(sources))); %#ok<AGROW>
            continue;
        end

        specs(end + 1) = struct( ...
            'name', cellName(cell), ...
            'sources', {sources}, ...
            'weighted', logical(weighted), ...
            'cell', struct('group', cell.group, 'session', cell.session)); %#ok<AGROW>
    end
end

% ----------------------------------------------------------------------- %
function name = cellName(cell)
%CELLNAME  A readable name for the cell, skipping the placeholder levels
%   deriveDesign uses to stand for "this field was left blank".
    parts = {};
    if ~isPlaceholder(cell.group)
        parts{end + 1} = cell.group;
    end
    if ~isPlaceholder(cell.session)
        parts{end + 1} = cell.session;
    end
    if isempty(parts)
        name = 'All subjects';
    else
        name = strjoin(parts, ', ');
    end
end

function tf = isPlaceholder(level)
    tf = isempty(strtrim(char(level))) || ...
        any(strcmp(char(level), {'(no group)', '(no session)'}));
end
