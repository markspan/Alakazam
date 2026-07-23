function chanlocs = ChannelEditorDialog(chanlocs, elcFile)
%CHANNELEDITORDIALOG  Alakazam-styled channel location editor: edit labels,
%   types and 3-D coordinates in a table; look up standard 10-5 positions by
%   label; or load a montage file. The uifigure counterpart of EEGLAB's
%   pop_chanedit.
%
%   CHANLOCS is the dataset's channels; ELCFILE the standard-template path used
%   by "Look up 10-5 locations". Returns the edited chanlocs struct array (with
%   the spherical/polar fields re-derived from the Cartesian coordinates), or
%   [] on cancel.
    accentColor = [0.290 0.498 0.788];
    bgColor     = [0.9608 0.9608 0.9608];
    result = [];

    fig = uifigure('Name', 'Channel editor', 'Position', [100 100 560 480], 'Color', bgColor);
    root = uigridlayout(fig, [2 1], 'RowHeight', {40, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0);
    uilabel(root, 'Text', '  Channel editor', 'FontSize', 14, 'FontWeight', 'bold', ...
        'FontColor', [1 1 1], 'BackgroundColor', accentColor, 'VerticalAlignment', 'center');
    outer = uigridlayout(root, [3 1], 'RowHeight', {'fit', '1x', 44}, 'Padding', [10 10 10 10]);

    uilabel(outer, 'Text', ['Edit channel labels, types and X/Y/Z coordinates. "Look up 10-5 ' ...
        'locations" fills coordinates by matching labels to a standard template; ' ...
        '"Load montage..." reads a channel-location file.'], 'WordWrap', 'on');

    tbl = uitable(outer, 'ColumnName', {'Label', 'Type', 'X', 'Y', 'Z'}, ...
        'ColumnEditable', [true true true true true], ...
        'ColumnFormat', {'char', 'char', 'numeric', 'numeric', 'numeric'}, ...
        'Data', toTable(chanlocs));
    tbl.Layout.Row = 2;

    buttons = uigridlayout(outer, [1 5], 'ColumnWidth', {150, 130, '1x', 90, 90}, 'Padding', [0 4 0 0], 'ColumnSpacing', 6);
    buttons.Layout.Row = 3;
    uibutton(buttons, 'Text', 'Look up 10-5 locations', 'ButtonPushedFcn', @(~, ~) onLookup());
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
            template = readlocs(elcFile);
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
