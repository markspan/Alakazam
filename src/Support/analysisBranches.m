function [branch, names] = analysisBranches(chains, recordings)
%ANALYSISBRANCHES  The ways a set of datasets was made, each named by what
%   sets it apart from the others.
%
%   [BRANCH, NAMES] = analysisBranches(CHAINS, RECORDINGS) takes, for each
%   dataset, the steps that made it (CHAINS{k}, a struct array from the
%   recording's first step down to the dataset's own node, with .label,
%   .call and .params) and the recording it descends from (RECORDINGS{k}).
%   BRANCH(k) numbers the way dataset k was made: datasets made the same way
%   share a number, whichever recording they come from, in the order they
%   first appear. NAMES{b} names way b; every name is '' when all the
%   datasets were made the same way.
%
%   WHAT SETS A WAY APART. A step is told from another by its label and its
%   transformation. Steps every way shares say nothing and are left out, so
%   a way is named by its own steps ("AutoICA") or, when it has none, by the
%   ones it does without ("without AutoICA"). Ways whose steps are the same
%   but in another order are named by their whole chain. A name of more than
%   three steps is shortened to its first and last, as overlayNames does.
%
%   SETTINGS. Nodes keep their transformation's name until renamed, so two
%   branches of one recording can have exactly the same steps and differ
%   only in a setting: a low-pass at 30 Hz and one at 40 Hz. Such a setting
%   is found by comparing the branches WITHIN a recording, and only there:
%   across recordings a step's settings also differ for reasons that are not
%   another analysis (the components ICA removed, the channels
%   interpolated). The setting then names the step, as in
%   "Filter (lowpass.freq 30)", for every recording made that way.
%
%   See also DATASETBRANCHES, OVERLAYNAMES.
    n = numel(chains);
    branch = zeros(1, n);
    names = {};
    if n == 0
        return;
    end
    recordings = reshape(cellstr(string(recordings)), 1, []);

    % Each step by its label and transformation; a chain by its steps.
    keys = cell(1, n);
    for k = 1:n
        keys{k} = arrayfun(@(s) [char(string(s.label)) '|' char(string(s.call))], ...
            reshape(chains{k}, 1, []), 'UniformOutput', false);
    end
    chainKeys = cellfun(@(c) strjoin(c, newline), keys, 'UniformOutput', false);

    settings = settingsThatSplit(chains, recordings, chainKeys);

    % Each step as it is shown, with the settings that split it, and what
    % the way is told apart by: the transformation and that text.
    shown = cell(1, n);
    idsOf = cell(1, n);
    signatures = cell(1, n);
    for k = 1:n
        shown{k} = cell(1, numel(chains{k}));
        ids = cell(1, numel(chains{k}));
        for j = 1:numel(chains{k})
            step = chains{k}(j);
            text = char(string(step.label));
            where = sprintf('%s#%d', chainKeys{k}, j);
            if isKey(settings, where)
                fields = settings(where);
                parts = cellfun(@(f) strtrim([f ' ' valueText(fieldValue(step.params, f))]), ...
                    fields, 'UniformOutput', false);
                text = sprintf('%s (%s)', text, strjoin(parts, ', '));
            end
            shown{k}{j} = text;
            ids{j} = [char(string(step.call)) '|' text];
        end
        signatures{k} = strjoin(ids, newline);
        idsOf{k} = ids;
    end

    [~, first, branch] = unique(signatures, 'stable');
    branch = reshape(branch, 1, []);
    m = numel(first);
    names = repmat({''}, 1, m);
    if m < 2
        return;
    end

    wayIds = idsOf(first);
    wayShown = shown(first);
    common = wayIds{1};
    everyId = {};
    for b = 1:m
        common = intersect(common, wayIds{b}, 'stable');
        everyId = [everyId, wayIds{b}(~ismember(wayIds{b}, everyId))]; %#ok<AGROW>
    end
    everyShown = cellfun(@(id) extractAfter(id, '|'), everyId, 'UniformOutput', false);
    for b = 1:m
        own = ~ismember(wayIds{b}, common);
        if any(own)
            names{b} = shortened(wayShown{b}(own));
        else
            missing = ~ismember(everyId, wayIds{b});
            names{b} = ['without ' strjoin(everyShown(missing), ', ')];
        end
    end

    % The same steps in another order: the whole chain tells them apart.
    for b = 1:m
        same = find(strcmp(names, names{b}));
        if numel(same) > 1
            for s = same
                names{s} = shortened(wayShown{s});
            end
        end
    end
    for b = 1:m
        same = find(strcmp(names, names{b}));
        if numel(same) > 1
            for j = 1:numel(same)
                names{same(j)} = sprintf('%s [%d]', names{same(j)}, j);
            end
        end
    end
end

% ======================================================================= %
function settings = settingsThatSplit(chains, recordings, chainKeys)
%SETTINGSTHATSPLIT  For each step of a chain that one recording ran twice
%   with the same steps, the settings in which the two differ. Keyed by
%   '<chain key>#<step>', each a cellstr of setting paths.
    settings = containers.Map('KeyType', 'char', 'ValueType', 'any');
    for r = reshape(unique(recordings), 1, [])
        mine = find(strcmp(recordings, r{1}));
        [~, ~, group] = unique(chainKeys(mine));
        for g = reshape(unique(group), 1, [])
            twins = mine(group == g);
            if numel(twins) < 2
                continue;
            end
            for j = 1:numel(chains{twins(1)})
                params = arrayfun(@(t) chains{t}(j).params, twins, 'UniformOutput', false);
                fields = differingFields(params);
                if isempty(fields)
                    continue;
                end
                where = sprintf('%s#%d', chainKeys{twins(1)}, j);
                if isKey(settings, where)
                    fields = union(settings(where), fields, 'stable');
                end
                settings(where) = fields;
            end
        end
    end
end

function fields = differingFields(params)
%DIFFERINGFIELDS  The setting paths ('lowpass.freq') whose values are not
%   the same in every one of PARAMS; {''} when they differ but are not
%   settings structs at all.
    if ~all(cellfun(@(p) isstruct(p) && isscalar(p), params))
        if all(cellfun(@(p) isequaln(p, params{1}), params))
            fields = {};
        else
            fields = {''};
        end
        return;
    end
    leaves = cellfun(@(p) flatten(p, ''), params, 'UniformOutput', false);
    paths = {};
    for i = 1:numel(leaves)
        paths = [paths, leaves{i}(1, ~ismember(leaves{i}(1, :), paths))]; %#ok<AGROW>
    end
    fields = {};
    for p = paths
        values = cellfun(@(l) leafValue(l, p{1}), leaves, 'UniformOutput', false);
        if ~all(cellfun(@(v) isequaln(v, values{1}), values))
            fields{end + 1} = p{1}; %#ok<AGROW>
        end
    end
end

function leaves = flatten(s, prefix)
%FLATTEN  A 2 x N cell of {path; value} for every leaf of the scalar struct
%   S; a struct array, a cell or any other value is a leaf.
    leaves = cell(2, 0);
    for f = reshape(fieldnames(s), 1, [])
        path = f{1};
        if ~isempty(prefix)
            path = [prefix '.' f{1}];
        end
        value = s.(f{1});
        if isstruct(value) && isscalar(value)
            leaves = [leaves, flatten(value, path)]; %#ok<AGROW>
        else
            leaves(:, end + 1) = {path; value}; %#ok<AGROW>
        end
    end
end

function value = leafValue(leaves, path)
    at = find(strcmp(leaves(1, :), path), 1);
    if isempty(at)
        value = missing;   % a setting one branch has and the other lacks
    else
        value = leaves{2, at};
    end
end

function value = fieldValue(params, path)
%FIELDVALUE  The setting at PATH in PARAMS, or PARAMS itself for ''.
    value = params;
    if isempty(path)
        return;
    end
    for part = strsplit(path, '.')
        if ~isstruct(value) || ~isfield(value, part{1})
            value = missing;
            return;
        end
        value = value.(part{1});
    end
end

function text = valueText(value)
%VALUETEXT  A setting's value, short enough for a list.
    if isa(value, 'missing')
        text = 'none';
    elseif islogical(value) && isscalar(value)
        text = char(string(matlab.lang.OnOffSwitchState(value)));
    elseif isnumeric(value) || islogical(value)
        if isempty(value)
            text = '[]';
        elseif numel(value) <= 4
            text = strjoin(arrayfun(@(v) sprintf('%g', v), double(value(:)'), ...
                'UniformOutput', false), ' ');
        else
            text = sprintf('%d values', numel(value));
        end
    elseif ischar(value) || isstring(value)
        text = char(strjoin(string(value), ' '));
    elseif iscellstr(value) || (iscell(value) && all(cellfun(@(c) ischar(c) || isstring(c), value)))
        items = cellstr(string(value));
        if numel(items) > 3
            items = [items(1:2), {sprintf('and %d more', numel(items) - 2)}];
        end
        text = strjoin(items, ' ');
    else
        text = sprintf('another %s', class(value));
    end
    if strlength(text) > 30
        text = [extractBefore(text, 29) char(8230)];
    end
end

function name = shortened(steps)
%SHORTENED  STEPS joined, the middle of a long run left out.
    if numel(steps) > 3
        steps = [steps(1), {char(8230)}, steps(end)];
    end
    name = strjoin(steps, ' / ');
end
