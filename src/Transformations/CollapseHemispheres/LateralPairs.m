function out = LateralPairs(chanlocs, method)
%LATERALPAIRS  Match each left-hemisphere electrode to its right-hemisphere
%   mirror, for any montage.
%
%   OUT = LateralPairs(CHANLOCS) returns a struct with
%       .pairs     1xP struct array, each with .left and .right (indices into
%                  CHANLOCS) and .label ("C3/C4"), ordered left-to-right by
%                  the left member's own position in CHANLOCS
%       .midline   indices of electrodes on the midline, where there is no
%                  laterality to collapse
%       .unpaired  indices that are neither midline nor matched
%       .method    'geometry' or 'labels', whichever was used
%
%   OUT = LateralPairs(CHANLOCS, METHOD) forces 'geometry' or 'labels'
%   instead of choosing ('auto', the default).
%
%   NEVER BY CHANNEL ORDER, which is the obvious shortcut and is wrong. In
%   ANT's own standard_waveguard64_equidistant.elc the pairs are listed
%   left-then-right throughout except for 3RD/3LD, which appear inverted;
%   anything pairing adjacent rows would silently swap contralateral for
%   ipsilateral on that one pair, in a montage where nothing about the
%   labels would let a reader notice.
%
%   GEOMETRY IS PREFERRED because it is the only montage-agnostic rule. It
%   mirrors each electrode through the mid-sagittal plane and takes the
%   nearest electrode to that image: EEGLAB's convention has +X toward the
%   nose, +Y toward the LEFT ear and +Z up, so the mirror of (x, y, z) is
%   (x, -y, z). Matching is greedy from the closest pair outward, so one
%   near-degenerate electrode cannot cascade into a chain of wrong matches.
%
%   LABELS ARE THE FALLBACK for a dataset whose locations have not been
%   filled in yet, and two conventions are tried, in this order:
%
%     1. An L/R letter in the same position, as equidistant montages use
%        (1L/1R, 2LB/2RB, 10L/10R). Implemented by swapping the first L or
%        R and requiring the result to be a label this montage actually has.
%     2. The 10-20 odd/left, even/right numbering (F3/F4, PO7/PO8, P9/P10),
%        by incrementing an odd trailing number and, again, requiring the
%        partner to exist.
%
%   Requiring the partner to exist is what makes both rules safe to try on
%   a montage they were not meant for: a 10-20 label has no L/R to swap, and
%   an equidistant label has no partner under odd/even numbering, so each
%   rule finds nothing rather than something wrong.
%
%   A label ending in z or Z (Cz, POz, 0Z) is midline under either rule.
%
%   See also COLLAPSEHEMISPHERES, TRANSTOOLS.TEMPLATESCALPLOCS.
    if nargin < 2 || isempty(method)
        method = 'auto';
    end
    method = lower(char(string(method)));

    labels = labelList(chanlocs);
    n = numel(labels);
    out = struct('pairs', emptyPairs(), 'midline', [], 'unpaired', [], ...
        'method', 'labels');
    if n == 0
        return;
    end

    switch method
        case 'geometry'
            useGeometry = true;
        case 'labels'
            useGeometry = false;
        case 'auto'
            % Two positioned electrodes is the minimum that can describe a
            % pair at all; below that there is nothing for geometry to do.
            useGeometry = sum(hasPosition(chanlocs)) >= 2;
        otherwise
            throw(MException('Alakazam:LateralPairs', ...
                ['I''m afraid "%s" is not a pairing method. Use "geometry", ' ...
                 '"labels" or "auto".'], method));
    end

    if useGeometry
        [pairs, midline, unpaired] = pairByGeometry(chanlocs, labels);
        out.method = 'geometry';
    else
        [pairs, midline, unpaired] = pairByLabel(labels);
        out.method = 'labels';
    end
    out.pairs    = pairs;
    out.midline  = midline(:)';
    out.unpaired = unpaired(:)';
end

% ======================================================================= %
function [pairs, midline, unpaired] = pairByGeometry(chanlocs, labels)
    n = numel(labels);
    pos = nan(n, 3);
    ok = hasPosition(chanlocs);
    for i = find(ok)
        pos(i, :) = [double(chanlocs(i).X), double(chanlocs(i).Y), double(chanlocs(i).Z)];
    end

    % A relative tolerance, because a montage may be in mm, cm or on a unit
    % sphere and nothing in chanlocs says which.
    scale = max(sqrt(sum(pos .^ 2, 2)), [], 'omitnan');
    if isempty(scale) || ~isfinite(scale) || scale == 0
        scale = 1;
    end
    midlineTol = 0.02 * scale;
    matchTol   = 0.08 * scale;

    midline  = find(ok & abs(pos(:, 2))' <= midlineTol);
    left     = find(ok & pos(:, 2)' >  midlineTol);
    right    = find(ok & pos(:, 2)' < -midlineTol);

    % Every left-right distance at once, then take matches closest-first:
    % a greedy sweep in index order would let one ambiguous electrode claim
    % a partner that fits another far better.
    d = inf(numel(left), numel(right));
    for a = 1:numel(left)
        mirror = pos(left(a), :) .* [1, -1, 1];
        for b = 1:numel(right)
            d(a, b) = norm(mirror - pos(right(b), :));
        end
    end

    pairs = emptyPairs();
    while true
        [dMin, k] = min(d(:));
        if isempty(dMin) || ~isfinite(dMin) || dMin > matchTol
            break;
        end
        [a, b] = ind2sub(size(d), k);
        pairs(end + 1) = onePair(left(a), right(b), labels); %#ok<AGROW>
        d(a, :) = inf;
        d(:, b) = inf;
    end
    pairs = sortPairs(pairs);

    used = [pairs.left, pairs.right];
    unpaired = setdiff(1:n, [midline, used]);
end

% ======================================================================= %
function [pairs, midline, unpaired] = pairByLabel(labels)
    n = numel(labels);
    upper_ = upper(labels);
    midline = find(endsWith(upper_, 'Z'));

    pairs = emptyPairs();
    taken = false(1, n);
    taken(midline) = true;

    % Rule 1, the L/R swap, then rule 2, odd/even. Both ask "does the
    % partner this rule predicts actually exist here", so a rule that does
    % not fit the montage simply matches nothing.
    for rule = {@swapPartner, @oddEvenPartner}
        for i = 1:n
            if taken(i)
                continue;
            end
            want = rule{1}(upper_{i});
            if isempty(want)
                continue;
            end
            j = find(strcmp(upper_, want) & ~taken);
            if isempty(j) || j(1) == i
                continue;
            end
            pairs(end + 1) = onePair(i, j(1), labels); %#ok<AGROW>
            taken([i, j(1)]) = true;
        end
    end
    pairs = sortPairs(pairs);
    unpaired = find(~taken);
end

function want = swapPartner(label)
%SWAPPARTNER  The label with its first L or R flipped ("2LB" -> "2RB"), or
%   empty when it has neither. Only an L is flipped forward, so a pair is
%   proposed once rather than from both ends.
    want = '';
    k = find(label == 'L', 1);
    if isempty(k)
        return;
    end
    want = label;
    want(k) = 'R';
end

function want = oddEvenPartner(label)
%ODDEVENPARTNER  The 10-20 partner of an ODD-numbered label ("F3" -> "F4",
%   "P9" -> "P10"), or empty for an even or unnumbered one. Only odd labels
%   propose, for the same reason swapPartner only flips L.
    want = '';
    tok = regexp(label, '^([A-Z]+)(\d+)$', 'tokens', 'once');
    if isempty(tok)
        return;
    end
    num = str2double(tok{2});
    if ~isfinite(num) || mod(num, 2) == 0
        return;
    end
    want = sprintf('%s%d', tok{1}, num + 1);
end

% ======================================================================= %
function p = onePair(leftIdx, rightIdx, labels)
    p = struct('left', leftIdx, 'right', rightIdx, ...
        'label', sprintf('%s/%s', labels{leftIdx}, labels{rightIdx}));
end

function pairs = emptyPairs()
    pairs = struct('left', {}, 'right', {}, 'label', {});
end

function pairs = sortPairs(pairs)
%SORTPAIRS  By the left member's position in the channel list, so the report
%   and the dialog list pairs in montage order rather than in whatever order
%   the matching happened to find them.
    if isempty(pairs)
        return;
    end
    [~, order] = sort([pairs.left]);
    pairs = pairs(order);
end

function tf = hasPosition(chanlocs)
    tf = false(1, numel(chanlocs));
    for i = 1:numel(chanlocs)
        tf(i) = isfield(chanlocs, 'X') && isfield(chanlocs, 'Y') && isfield(chanlocs, 'Z') ...
            && ~isempty(chanlocs(i).X) && ~isempty(chanlocs(i).Y) && ~isempty(chanlocs(i).Z) ...
            && all(isfinite(double([chanlocs(i).X, chanlocs(i).Y, chanlocs(i).Z])));
    end
end

function labels = labelList(chanlocs)
    labels = {};
    if isempty(chanlocs) || ~isstruct(chanlocs) || ~isfield(chanlocs, 'labels')
        return;
    end
    labels = arrayfun(@(c) strtrim(char(string(c.labels))), chanlocs(:)', ...
        'UniformOutput', false);
end
