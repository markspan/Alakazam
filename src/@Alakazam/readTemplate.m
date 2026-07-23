function nodes = readTemplate(~, file)
%READTEMPLATE  Parse a saved template file (see onSaveTemplate) into a flat
%   struct array of (transformId, params, parent) nodes, depth-first, where
%   PARENT is the 1-based index of a node's parent (or -1 for a root). This is
%   the branch-preserving form onApplyTemplate replays to rebuild the tree.
%
%   Reads both formats: version 2 (a "nodes" list, each carrying its parent
%   index -- the current tree form), and version 1 (a flat "steps" list, a
%   single linear chain), which is converted to the same node form with each
%   step parented on the previous one. Throws a friendly error if FILE is
%   missing, unreadable, or not a recognisable Alakazam template.
    if exist(file, "file") ~= 2
        throw(MException('Alakazam:readTemplate', 'File not found:\n\n    %s', file));
    end
    raw = jsondecode(fileread(file));
    if ~isstruct(raw) || ~isfield(raw, 'alakazamTemplate') || ~isequal(raw.alakazamTemplate, true)
        throw(MException('Alakazam:readTemplate', ...
            'This does not look like an Alakazam template file.'));
    end

    nodes = struct('transformId', {}, 'params', {}, 'parent', {});

    if isfield(raw, 'nodes')
        items = asItemList(raw.nodes);
        for k = 1:numel(items)
            it = items{k};
            nodes(k) = struct('transformId', char(it.transformId), ...
                'params', it.params, 'parent', double(it.parent));
        end
    elseif isfield(raw, 'steps')
        % version 1: a single linear chain -- step k is the child of step k-1.
        items = asItemList(raw.steps);
        for k = 1:numel(items)
            it = items{k};
            parent = k - 1;              % previous step (1-based); 0 -> root
            if parent == 0; parent = -1; end
            nodes(k) = struct('transformId', char(it.transformId), ...
                'params', it.params, 'parent', parent);
        end
    else
        throw(MException('Alakazam:readTemplate', ...
            'This template file has no steps to apply.'));
    end
end

function items = asItemList(raw)
%ASITEMLIST  Normalise jsondecode's output (a cell array of objects, a struct
%   array if they happened to unify, or a single struct) to a cell array.
    if iscell(raw)
        items = raw;
    elseif isstruct(raw)
        items = num2cell(raw);
    else
        items = {};
    end
end
