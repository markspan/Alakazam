function specs = measureChannelSpecs(channels, allLabels, windowLabel)
%MEASURECHANNELSPECS  Parse a window's Channels field into an ordered list
%   of channel specs, one per output "channel" the measure produces:
%     .label   -- the output name: a single electrode's own label, or a
%                 pool written "{A+B+C}".
%     .members -- row indices into ALLLABELS whose (NaN-tolerant) mean
%                 forms this spec's waveform -- one index for a plain
%                 electrode, several for a pool.
%
%   CHANNELS is the raw Channels text:
%     ""                     every channel, each measured on its own
%     "Pz, Cz"               those electrodes, separately
%     "{Pz POz CPz}"         one virtual channel = mean(Pz, POz, CPz)
%     "{Pz POz CPz}, Fz"     the parietal pool AND Fz, as two outputs
%   Members inside "{ }" and bare electrodes are separated by commas and/or
%   spaces. Matching is case-insensitive; a name not in ALLLABELS throws a
%   friendly error naming it (and the window). Also tolerates the old
%   cellstr form a window may carry from before pooling existed (each
%   element a single electrode).
%
%   Shared by Measure.m (to compute) and MeasureDialog.m (to validate at
%   OK), so the two can never drift. Runs at both dialog-OK time and replay
%   time (drag / Apply to All / templates), since a saved definition can be
%   applied to a dataset whose channels differ.
    text = strtrim(specText(channels));

    if isempty(text)
        specs = repmat(struct('label', '', 'members', []), 1, numel(allLabels));
        for i = 1:numel(allLabels)
            specs(i).label = char(allLabels(i));
            specs(i).members = i;
        end
        return;
    end

    items = tokenize(text, windowLabel);
    specs = repmat(struct('label', '', 'members', []), 1, numel(items));
    for k = 1:numel(items)
        it = items{k};
        if startsWith(it, '{') && endsWith(it, '}')
            members = splitNames(it(2:end - 1));
        else
            members = {it};
        end
        idx = resolveNames(members, allLabels, windowLabel);
        specs(k).members = idx;
        if isscalar(idx)
            specs(k).label = char(allLabels(idx));
        else
            specs(k).label = ['{' char(strjoin(allLabels(idx), '+')) '}'];
        end
    end
end

function text = specText(channels)
%SPECTEXT  Whatever form CHANNELS arrives in (raw char text, a string, an
%   old cellstr of single electrodes, or empty) as one char text string.
    if isempty(channels)
        text = '';
    elseif iscell(channels)
        text = strjoin(channels, ', ');
    elseif isstring(channels)
        text = char(strjoin(channels, ', '));
    else
        text = char(channels);
    end
end

function items = tokenize(text, windowLabel)
%TOKENIZE  Split TEXT into top-level items -- bare electrode names and
%   whole "{ ... }" pools -- honouring braces (a comma or space inside a
%   pool separates its members, not the top-level items).
    items = {};
    n = numel(text);
    i = 1;
    cur = '';
    while i <= n
        ch = text(i);
        if ch == '{'
            rel = find(text(i:end) == '}', 1);
            if isempty(rel)
                throw(MException('Alakazam:Measure', ...
                    'Window "%s": a channel pool is missing its closing "}".', windowLabel));
            end
            if ~isempty(strtrim(cur)); items{end + 1} = strtrim(cur); cur = ''; end %#ok<AGROW>
            items{end + 1} = strtrim(text(i : i + rel - 1)); %#ok<AGROW>
            i = i + rel;
        elseif ch == ',' || ch == ' '
            if ~isempty(strtrim(cur)); items{end + 1} = strtrim(cur); cur = ''; end %#ok<AGROW>
            i = i + 1;
        else
            cur = [cur ch]; %#ok<AGROW>
            i = i + 1;
        end
    end
    if ~isempty(strtrim(cur)); items{end + 1} = strtrim(cur); end
end

function names = splitNames(inner)
%SPLITNAMES  The member names inside a pool's braces, comma/space split.
    parts = strtrim(strsplit(inner, {',', ' '}));
    names = parts(~cellfun(@isempty, parts));
end

function idx = resolveNames(names, allLabels, windowLabel)
%RESOLVENAMES  NAMES resolved to row indices into ALLLABELS (case-
%   insensitive), throwing with every unknown name at once.
    idx = zeros(1, numel(names));
    missing = {};
    for i = 1:numel(names)
        hit = find(strcmpi(allLabels, names{i}), 1);
        if isempty(hit)
            missing{end + 1} = names{i}; %#ok<AGROW>
        else
            idx(i) = hit;
        end
    end
    if ~isempty(missing)
        throw(MException('Alakazam:Measure', ...
            'Window "%s" names channel(s) not in this dataset: %s.', ...
            windowLabel, strjoin(missing, ', ')));
    end
end
