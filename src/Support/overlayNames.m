function [names, fullNames] = overlayNames(paths)
%OVERLAYNAMES  Short names that tell overlaid datasets apart.
%   [NAMES, FULLNAMES] = overlayNames(PATHS) takes one tree path per dataset
%   on a plot (a cellstr of node labels from the recording down to the node)
%   and returns, as string arrays, a short name for each and its full path.
%
%   WHAT IS THE SAME IS LEFT OUT. The labels every path shares at its start
%   (the same recording) and at its end (the same steps after the fork) say
%   nothing about which line is which, so a name keeps only what differs:
%   two subjects' averages read "S01" and "S02", two branches of one subject
%   "Filter 30 Hz" and "Filter 40 Hz" once renamed. A difference longer than
%   three labels is shortened to its first and last; FULLNAMES has the lot,
%   for a tooltip.
%
%   NAMES ARE NOT TRUSTED TO BE UNIQUE. Nodes are labelled with their
%   transformation's name until renamed, so two branches can have exactly
%   the same labels. Names that still coincide get [1], [2], ... in the
%   order the datasets were added, the plot's own first.
%
%   See also AVERAGEVIEW.
    n = numel(paths);
    paths = cellfun(@(p) cellstr(string(p)), paths, 'UniformOutput', false);
    fullNames = strings(1, n);
    for k = 1:n
        fullNames(k) = strjoin(paths{k}, ' / ');
    end
    names = fullNames;
    if n < 2
        return;
    end

    lengths = cellfun(@numel, paths);
    shortest = min(lengths);
    prefix = 0;
    while prefix < shortest && allEqual(cellfun(@(p) p{prefix + 1}, paths, 'UniformOutput', false))
        prefix = prefix + 1;
    end
    suffix = 0;
    while suffix < shortest - prefix ...
            && allEqual(cellfun(@(p) p{end - suffix}, paths, 'UniformOutput', false))
        suffix = suffix + 1;
    end
    % Every name must keep at least one label: give back from the shared end
    % first (the node's own label is the better reminder), then the start.
    while any(lengths - prefix - suffix < 1) && suffix > 0
        suffix = suffix - 1;
    end
    while any(lengths - prefix - suffix < 1) && prefix > 0
        prefix = prefix - 1;
    end

    for k = 1:n
        middle = paths{k}(prefix + 1:end - suffix);
        if numel(middle) > 3
            middle = [middle(1), {char(8230)}, middle(end)];
        end
        names(k) = strjoin(middle, ' / ');
    end

    for name = unique(names(:)')
        same = find(names == name);
        if numel(same) > 1
            for j = 1:numel(same)
                names(same(j)) = sprintf('%s [%d]', name, j);
            end
        end
    end
end

% ======================================================================= %
function tf = allEqual(values)
    tf = all(strcmp(values, values{1}));
end
