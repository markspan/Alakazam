function chanlocs = ChannelEditorDialog(chanlocs, templates)
%CHANNELEDITORDIALOG  Alakazam-styled channel location editor: edit labels,
%   types and 3-D coordinates in a table; look up positions from a chosen
%   template by label; or load a montage file. The uifigure counterpart of
%   EEGLAB's pop_chanedit.
%
%   CHANLOCS is the dataset's channels. TEMPLATES is the struct array
%   AvailableElectrodeTemplates returns (.name for the dropdown,
%   .file the path "Look up locations" reads) -- NOT hard-coded to the 10-5
%   system, because a montage whose labels carry no anatomy (an equidistant
%   cap) needs a different template entirely, not a fallback. MAY BE EMPTY
%   (neither toolbox installed and src/Electrodes missing its templates),
%   in which case "Look up locations" is disabled but the rest of the
%   editor -- hand-editing the table, "Load montage..." -- still works.
%   Returns the edited chanlocs struct array (with the spherical/polar
%   fields re-derived from the Cartesian coordinates), or [] on cancel.
    [accentColor, bgColor] = dialogChromeColors();
    result = [];

    fig = uifigure('Name', 'Channel editor', 'Position', fitOnScreen([100 100 560 480]), 'Color', bgColor);
    root = uigridlayout(fig, [2 1], 'RowHeight', {40, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0);
    uilabel(root, 'Text', '  Channel editor', 'FontSize', 14, 'FontWeight', 'bold', ...
        'FontColor', [1 1 1], 'BackgroundColor', accentColor, 'VerticalAlignment', 'center');
    outer = uigridlayout(root, [4 1], 'RowHeight', {'fit', '1x', 'fit', 44}, 'Padding', [10 10 10 10]);

    uilabel(outer, 'Text', ['Edit channel labels, types and X/Y/Z coordinates. "Look up ' ...
        'locations" fills coordinates by matching labels to the selected template below; ' ...
        '"Load montage..." reads a channel-location file instead.'], 'WordWrap', 'on');

    tbl = uitable(outer, 'ColumnName', {'Label', 'Type', 'X', 'Y', 'Z'}, ...
        'ColumnEditable', [true true true true true], ...
        'ColumnFormat', {'char', 'char', 'numeric', 'numeric', 'numeric'}, ...
        'Data', toTable(chanlocs));
    tbl.Layout.Row = 2;

    templateRow = uigridlayout(outer, [1 2], 'ColumnWidth', {60, '1x'}, ...
        'Padding', [0 0 0 0], 'ColumnSpacing', 8);
    templateRow.Layout.Row = 3;
    uilabel(templateRow, 'Text', 'Template', 'VerticalAlignment', 'center');
    noTemplates = isempty(templates);
    if noTemplates
        % uidropdown needs at least one item; a placeholder that explains
        % why nothing is selectable reads better than an empty control, and
        % "Look up locations" is disabled below so this is never read.
        templatePicker = uidropdown(templateRow, ...
            'Items', {'(no template available)'}, 'ItemsData', {''}, 'Enable', 'off');
    else
        % ItemsData carries the file path directly, so the dropdown's own
        % .Value is what to hand to readlocs -- no separate index lookup,
        % and nothing to keep in sync if the template list's order changes.
        templatePicker = uidropdown(templateRow, 'Items', {templates.name}, ...
            'ItemsData', {templates.file});
    end

    buttons = uigridlayout(outer, [1 5], 'ColumnWidth', {130, 130, '1x', 90, 90}, 'Padding', [0 4 0 0], 'ColumnSpacing', 6);
    buttons.Layout.Row = 4;
    uibutton(buttons, 'Text', 'Look up locations', 'Enable', ~noTemplates, ...
        'ButtonPushedFcn', @(~, ~) onLookup());
    uibutton(buttons, 'Text', 'Load montage...', 'ButtonPushedFcn', @(~, ~) onLoad());
    uilabel(buttons, 'Text', '');
    uibutton(buttons, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) onCancel());
    uibutton(buttons, 'Text', 'OK', 'BackgroundColor', accentColor, 'FontColor', [1 1 1], ...
        'ButtonPushedFcn', @(~, ~) onOK());
    fig.CloseRequestFcn = @(~, ~) onCancel();

    uiwait(fig);
    chanlocs = result;

    function onLookup()
        try
            template = readlocs(templatePicker.Value);
        catch err
            uialert(fig, err.message, 'Could not read the template'); return;
        end
        tl = lower(string({template.labels}));
        d = tbl.Data;
        for r = 1:size(d, 1)
            m = find(tl == lower(string(d{r, 1})), 1);
            if ~isempty(m)
                d{r, 3} = template(m).X; d{r, 4} = template(m).Y; d{r, 5} = template(m).Z;
            end
            % Fill a blank Type by label (EOG/ECG/...), or 'EEG' when the label
            % resolved to a scalp position -- the lookup's type counterpart.
            if isempty(strtrim(char(string(d{r, 2}))))
                tt = channelTypeFromLabel(d{r, 1});
                if isempty(tt) && ~isempty(m); tt = 'EEG'; end
                d{r, 2} = tt;
            end
        end
        tbl.Data = d;
    end

    function onLoad()
        [file, path] = uiextras.uigetfile2( ...
            {'*.ced;*.locs;*.loc;*.elp;*.sfp;*.elc;*.xyz', 'Channel location files'}, ...
            'Load a montage file');
        if isequal(file, 0); return; end
        try
            loaded = readlocs(fullfile(path, file));
        catch err
            uialert(fig, err.message, 'Could not read the montage'); return;
        end
        tbl.Data = toTable(loaded);
    end

    function onOK()
        result = fromTable(tbl.Data);
        try
            result = convertlocs(result, 'cart2all');   % re-derive spherical/polar
        catch
            % leave Cartesian only if conversion is unavailable
        end
        uiresume(fig); delete(fig);
    end

    function onCancel()
        uiresume(fig); delete(fig);
    end
end

% ======================================================================= %
function d = toTable(chanlocs)
    n = numel(chanlocs);
    d = cell(n, 5);
    for i = 1:n
        d{i, 1} = char(string(getf(chanlocs(i), 'labels', '')));
        d{i, 2} = char(string(getf(chanlocs(i), 'type', '')));
        d{i, 3} = numOr(getf(chanlocs(i), 'X', []));
        d{i, 4} = numOr(getf(chanlocs(i), 'Y', []));
        d{i, 5} = numOr(getf(chanlocs(i), 'Z', []));
    end
end

function chanlocs = fromTable(d)
    n = size(d, 1);
    chanlocs = repmat(struct('labels', '', 'type', '', 'X', [], 'Y', [], 'Z', []), 1, n);
    for i = 1:n
        chanlocs(i).labels = char(string(d{i, 1}));
        chanlocs(i).type   = char(string(d{i, 2}));
        chanlocs(i).X = emptyIfNan(d{i, 3});
        chanlocs(i).Y = emptyIfNan(d{i, 4});
        chanlocs(i).Z = emptyIfNan(d{i, 5});
    end
end

function v = getf(s, name, default)
    if isfield(s, name); v = s.(name); else; v = default; end
end

function v = numOr(x)
    if isempty(x) || ~isnumeric(x); v = NaN; else; v = double(x); end
end

function v = emptyIfNan(x)
    if isempty(x) || (isnumeric(x) && isnan(x)); v = []; else; v = double(x); end
end
