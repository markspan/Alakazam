function options = SelectDataDialog(chanlocs, npnts, ntrials, stored)
%SELECTDATADIALOG  Native editor for the SelectData transform: pick data to
%   keep or remove along four axes (channels, time, points, trials), the same
%   selection pop_select offers, in the app's own dialog style.
%
%   Each axis has a mode -- "(off)", "Keep" or "Remove" -- and its own input:
%   a multi-select channel list, a time range (ms), a point range (samples), or
%   a list of trial indices. An axis left "(off)" is not applied. CHANLOCS is
%   the dataset's channels, NPNTS/NTRIALS its sample and trial counts (for
%   labels/limits), STORED a previous run's options (or [] on first use).
%
%   Returns the options struct (.channels/.time/.points/.trials, each with a
%   .mode plus its values), or [] on cancel.
    labels = arrayfun(@(c) char(string(c.labels)), chanlocs, 'UniformOutput', false);
    MODES = {'(off)', 'Keep', 'Remove'};
    accentColor = [0.290 0.498 0.788];   % #4a7fc9, as TransformOptionsDialog
    bgColor     = [0.9608 0.9608 0.9608]; % uifigure's own default Color
    options = [];

    seed = struct( ...
        'channels', struct('mode', '(off)', 'labels', {{}}), ...
        'time',     struct('mode', '(off)', 'range', [0 0]), ...
        'points',   struct('mode', '(off)', 'range', [1 npnts]), ...
        'trials',   struct('mode', '(off)', 'indices', []));
    seed = mergeSeed(seed, stored);

    fig = uifigure('Name', 'SelectData', 'Position', [100 100 460 490], 'Color', bgColor);
    root = uigridlayout(fig, [2 1], 'RowHeight', {40, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0);
    uilabel(root, 'Text', '  Select data', 'FontSize', 14, 'FontWeight', 'bold', ...
        'FontColor', [1 1 1], 'BackgroundColor', accentColor, 'VerticalAlignment', 'center');
    outer = uigridlayout(root, [6 1], 'RowHeight', {'fit', '1x', 'fit', 'fit', 'fit', 44}, 'Padding', [10 10 10 10]);

    uilabel(outer, 'Text', ['Select the data to keep or remove. Set each axis to Keep or Remove ' ...
        '(or leave it off). Channels: pick from the list; Time in ms; Points in samples; ' ...
        'Trials as indices (e.g. "1:10, 15").'], 'WordWrap', 'on');

    % Channels
    chanGrid = uigridlayout(outer, [2 1], 'RowHeight', {'fit', '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 2);
    chanGrid.Layout.Row = 2;
    chanHdr = uigridlayout(chanGrid, [1 2], 'ColumnWidth', {90, 120}, 'Padding', [0 0 0 0]);
    uilabel(chanHdr, 'Text', 'Channels', 'FontWeight', 'bold');
    chanMode = uidropdown(chanHdr, 'Items', MODES, 'Value', seed.channels.mode);
    chanList = uilistbox(chanGrid, 'Items', labels, 'Multiselect', 'on', ...
        'Value', intersectLabels(labels, seed.channels.labels));

    % Time (ms)
    timeGrid = rangeRow(outer, 3, 'Time (ms)', MODES, seed.time.mode, seed.time.range(1), seed.time.range(2));
    % Points (samples)
    pointGrid = rangeRow(outer, 4, 'Points (samples)', MODES, seed.points.mode, seed.points.range(1), seed.points.range(2));
    % Trials
    trialGrid = uigridlayout(outer, [1 3], 'ColumnWidth', {150, 120, '1x'}, 'Padding', [0 0 0 0], 'ColumnSpacing', 8);
    trialGrid.Layout.Row = 5;
    uilabel(trialGrid, 'Text', 'Trials (indices)', 'FontWeight', 'bold');
    trialMode = uidropdown(trialGrid, 'Items', MODES, 'Value', seed.trials.mode);
    trialField = uieditfield(trialGrid, 'text', 'Value', indicesText(seed.trials.indices), ...
        'Placeholder', sprintf('e.g. 1:10, 15  (1-%d)', ntrials));

    buttons = uigridlayout(outer, [1 3], 'ColumnWidth', {'1x', 90, 90}, 'Padding', [0 4 0 0]);
    buttons.Layout.Row = 6;
    uilabel(buttons, 'Text', '');
    uibutton(buttons, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) onCancel());
    uibutton(buttons, 'Text', 'OK', 'BackgroundColor', accentColor, ...
        'FontColor', [1 1 1], 'ButtonPushedFcn', @(~, ~) onOK());
    fig.CloseRequestFcn = @(~, ~) onCancel();

    uiwait(fig);

    function onOK()
        out = struct();
        out.channels = struct('mode', chanMode.Value, 'labels', {asCell(chanList.Value)});
        if ~strcmp(chanMode.Value, '(off)') && isempty(out.channels.labels)
            uialert(fig, 'Select at least one channel, or set Channels to (off).', 'Check the selection'); return;
        end

        [tok, terr] = readRange(timeGrid, 'Time');
        if ~isempty(terr); uialert(fig, terr, 'Check the selection'); return; end
        out.time = struct('mode', tok.mode, 'range', tok.range);

        [pok, perr] = readRange(pointGrid, 'Points');
        if ~isempty(perr); uialert(fig, perr, 'Check the selection'); return; end
        out.points = struct('mode', pok.mode, 'range', pok.range);

        idx = parseIndices(trialField.Value);
        if ~strcmp(trialMode.Value, '(off)') && isempty(idx)
            uialert(fig, 'Enter at least one trial index, or set Trials to (off).', 'Check the selection'); return;
        end
        out.trials = struct('mode', trialMode.Value, 'indices', idx);

        options = out;
        uiresume(fig); delete(fig);
    end

    function onCancel()
        uiresume(fig); delete(fig);
    end
end

% ======================================================================= %
function g = rangeRow(parent, row, label, modes, mode, lo, hi)
    g = uigridlayout(parent, [1 5], 'ColumnWidth', {150, 120, '1x', 20, '1x'}, ...
        'Padding', [0 0 0 0], 'ColumnSpacing', 6);
    g.Layout.Row = row;
    uilabel(g, 'Text', label, 'FontWeight', 'bold');
    md = uidropdown(g, 'Items', modes, 'Value', mode, 'Tag', 'mode');
    uieditfield(g, 'numeric', 'Value', lo, 'Tag', 'lo');
    uilabel(g, 'Text', 'to', 'HorizontalAlignment', 'center');
    uieditfield(g, 'numeric', 'Value', hi, 'Tag', 'hi');
    md.UserData = g;   % not used, kept for clarity
end

function [out, err] = readRange(g, name)
    out = struct('mode', '(off)', 'range', [0 0]); err = '';
    md = findobj(g, 'Tag', 'mode'); lo = findobj(g, 'Tag', 'lo'); hi = findobj(g, 'Tag', 'hi');
    out.mode = md.Value; out.range = [lo.Value hi.Value];
    if ~strcmp(out.mode, '(off)') && ~(hi.Value > lo.Value)
        err = sprintf('%s range: the second value must be greater than the first.', name);
    end
end

function v = intersectLabels(all, want)
    v = all(ismember(all, want));
    if isempty(v) && ~isempty(all); v = {}; end
end

function c = asCell(v)
    if isempty(v); c = {}; elseif ischar(v); c = {v}; else; c = v; end
end

function idx = parseIndices(text)
%PARSEINDICES  "1:10, 15" -> [1..10 15]; tolerant of blanks. No eval.
    idx = [];
    text = strtrim(char(string(text)));
    if isempty(text); return; end
    parts = strtrim(strsplit(text, {',', ' '}));
    for i = 1:numel(parts)
        p = parts{i};
        if isempty(p); continue; end
        if contains(p, ':')
            ab = str2double(strsplit(p, ':'));
            if numel(ab) == 2 && all(~isnan(ab)); idx = [idx, ab(1):ab(2)]; end %#ok<AGROW>
        else
            v = str2double(p);
            if ~isnan(v); idx = [idx, v]; end %#ok<AGROW>
        end
    end
    idx = unique(round(idx));
end

function t = indicesText(idx)
    if isempty(idx); t = ''; else; t = strtrim(num2str(idx(:)')); end
end

function seed = mergeSeed(seed, stored)
    if ~isstruct(stored); return; end
    for key = {'channels', 'time', 'points', 'trials'}
        k = key{1};
        if isfield(stored, k) && isstruct(stored.(k))
            f = fieldnames(seed.(k));
            for j = 1:numel(f)
                if isfield(stored.(k), f{j}) && ~isempty(stored.(k).(f{j}))
                    seed.(k).(f{j}) = stored.(k).(f{j});
                end
            end
        end
    end
end
