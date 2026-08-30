function ops = EventEditorDialog(EEG)
%EVENTEDITORDIALOG  Build a list of event-table corrections, with a live
%   preview of what they do.
%   OPS = EventEditorDialog(EEG) returns the recorded operations, or [] if
%   the analyst cancelled.
%
%   THE RECORDED OPERATIONS ARE ON SCREEN, not hidden behind the result.
%   This dialog edits a list of corrections and shows the table those
%   corrections produce, rather than editing the table and deriving a list
%   afterwards. That is deliberate and it is the whole design: what gets
%   stored, replayed onto other subjects and written into the exported
%   script is the list, so the list is what the analyst should be looking
%   at while deciding whether it is right.
%
%   It also makes the awkward case honest. A rename or a latency shift
%   carries to another recording; a hand edit to one row does not, because
%   row 47 of another file is a different event. Both are allowed, both are
%   recorded, and the ones that will not transfer are marked as such here
%   rather than discovered on replay.
%
%   See also EVENTEDITOR, APPLYEVENTOPS.
    ops = [];
    recorded = emptyOps();

    srate = fieldOr(EEG, 'srate', NaN);
    pnts  = fieldOr(EEG, 'pnts', NaN);
    original = EEG.event;

    fig = uifigure('Name', 'Event editor', 'Position', centred(1040, 660));
    outer = uigridlayout(fig, [2 1], 'RowHeight', {'1x', 46}, ...
        'Padding', [10 10 10 10], 'RowSpacing', 8);

    body = uigridlayout(outer, [1 2], 'ColumnWidth', {'1.35x', '1x'}, ...
        'Padding', [0 0 0 0], 'ColumnSpacing', 12);
    body.Layout.Row = 1;

    % ---- left: the resulting table --------------------------------------
    left = uigridlayout(body, [3 1], 'RowHeight', {'fit', '1x', 'fit'}, ...
        'Padding', [0 0 0 0], 'RowSpacing', 6);
    left.Layout.Column = 1;

    summaryLabel = uilabel(left, 'Text', '', 'FontWeight', 'bold');
    summaryLabel.Layout.Row = 1;

    tbl = uitable(left, 'ColumnName', {'#', 'Type', 'Latency (ms)', 'Latency (samples)'}, ...
        'ColumnEditable', [false true true false], ...
        'ColumnWidth', {46, 'auto', 110, 130}, ...
        'CellEditCallback', @(src, evt) onCellEdited(evt));
    tbl.Layout.Row = 2;

    noteLabel = uilabel(left, 'Text', '', 'FontColor', [0.69 0.24 0.22], ...
        'WordWrap', 'on');
    noteLabel.Layout.Row = 3;

    % ---- right: the corrections ------------------------------------------
    right = uigridlayout(body, [7 1], ...
        'RowHeight', {'fit', 'fit', 'fit', 'fit', 'fit', '1x', 'fit'}, ...
        'Padding', [0 0 0 0], 'RowSpacing', 8);
    right.Layout.Column = 2;

    heading = uilabel(right, 'Text', 'Corrections', 'FontWeight', 'bold', ...
        'FontSize', 14);
    heading.Layout.Row = 1;

    % Rename
    renameRow = uigridlayout(right, [1 5], ...
        'ColumnWidth', {58, '1x', 20, '1x', 74}, 'Padding', [0 0 0 0], ...
        'ColumnSpacing', 5);
    renameRow.Layout.Row = 2;
    uilabel(renameRow, 'Text', 'Rename');
    renameFrom = uidropdown(renameRow, 'Items', typeList(original), 'Editable', 'on');
    uilabel(renameRow, 'Text', 'to', 'HorizontalAlignment', 'center');
    renameTo = uieditfield(renameRow, 'text');
    uibutton(renameRow, 'Text', 'Add', 'ButtonPushedFcn', @(~,~) addRename());

    % Delete / keep
    dropRow = uigridlayout(right, [1 4], ...
        'ColumnWidth', {58, '1x', 74, 74}, 'Padding', [0 0 0 0], 'ColumnSpacing', 5);
    dropRow.Layout.Row = 3;
    uilabel(dropRow, 'Text', 'Types');
    dropTypes = uidropdown(dropRow, 'Items', typeList(original), 'Editable', 'on');
    uibutton(dropRow, 'Text', 'Delete', 'ButtonPushedFcn', @(~,~) addDrop(false));
    uibutton(dropRow, 'Text', 'Keep only', 'ButtonPushedFcn', @(~,~) addDrop(true));

    % Shift
    shiftRow = uigridlayout(right, [1 5], ...
        'ColumnWidth', {58, '1x', 76, 30, 74}, 'Padding', [0 0 0 0], ...
        'ColumnSpacing', 5);
    shiftRow.Layout.Row = 4;
    uilabel(shiftRow, 'Text', 'Shift');
    shiftTypes = uidropdown(shiftRow, 'Items', [{'(all types)'}, typeList(original)], ...
        'Editable', 'on');
    shiftMs = uieditfield(shiftRow, 'numeric', 'Value', 0);
    uilabel(shiftRow, 'Text', 'ms');
    uibutton(shiftRow, 'Text', 'Add', 'ButtonPushedFcn', @(~,~) addShift());

    hint = uilabel(right, 'Text', ['A correction below is applied to every dataset ' ...
        'this step is replayed on. A hand edit in the table is tied to this ' ...
        'recording only.'], ...
        'WordWrap', 'on', 'FontColor', [0.36 0.42 0.48]);
    hint.Layout.Row = 5;

    opsList = uilistbox(right, 'Items', {}, 'Multiselect', 'off');
    opsList.Layout.Row = 6;

    listButtons = uigridlayout(right, [1 3], 'ColumnWidth', {90, 90, '1x'}, ...
        'Padding', [0 0 0 0], 'ColumnSpacing', 6);
    listButtons.Layout.Row = 7;
    uibutton(listButtons, 'Text', 'Remove', 'ButtonPushedFcn', @(~,~) removeSelected());
    uibutton(listButtons, 'Text', 'Clear', 'ButtonPushedFcn', @(~,~) clearAll());

    % ---- bottom -----------------------------------------------------------
    buttons = uigridlayout(outer, [1 4], 'ColumnWidth', {150, '1x', 90, 90}, ...
        'Padding', [0 4 0 0]);
    buttons.Layout.Row = 2;
    uibutton(buttons, 'Text', 'Export table...', 'ButtonPushedFcn', @(~,~) onExport());
    cancelBtn = uibutton(buttons, 'Text', 'Cancel', 'ButtonPushedFcn', @(~,~) onCancel());
    cancelBtn.Layout.Column = 3;
    okBtn = uibutton(buttons, 'Text', 'OK', 'ButtonPushedFcn', @(~,~) onOK());
    okBtn.Layout.Column = 4;
    fig.CloseRequestFcn = @(~,~) onCancel();

    refresh();
    uiwait(fig);

    % ===================================================================== %
    function refresh()
    %REFRESH  Re-apply every recorded correction to the ORIGINAL events and
    %   show the result. Recomputing from the original each time, rather
    %   than editing in place, is what lets a correction be removed from the
    %   middle of the list and have the preview simply be right.
        [preview, notes] = applyEventOps(original, recorded, srate, pnts);
        tbl.Data = tableRows(preview, srate);
        summaryLabel.Text = sprintf('%d events, %d types (was %d events, %d types)', ...
            numel(preview), numel(typeList(preview)), ...
            numel(original), numel(typeList(original)));
        if isempty(notes)
            noteLabel.Text = '';
        else
            noteLabel.Text = strjoin(notes, '  ');
        end
        opsList.Items = describeOps(recorded);
    end

    function addRename()
        from = strtrim(renameFrom.Value);
        to = strtrim(renameTo.Value);
        if isempty(from) || isempty(to); return; end
        recorded(end + 1) = makeOp('renameType', 'from', from, 'to', to);
        renameTo.Value = '';
        refresh();
    end

    function addDrop(keepInstead)
        t = strtrim(dropTypes.Value);
        if isempty(t); return; end
        if keepInstead
            recorded(end + 1) = makeOp('keepTypes', 'types', {t});
        else
            recorded(end + 1) = makeOp('deleteType', 'types', {t});
        end
        refresh();
    end

    function addShift()
        ms = shiftMs.Value;
        if ~isfinite(ms) || ms == 0; return; end
        t = strtrim(shiftTypes.Value);
        if strcmp(t, '(all types)')
            types = {};
        else
            types = {t};
        end
        recorded(end + 1) = makeOp('shiftLatency', 'types', types, 'ms', ms);
        refresh();
    end

    function onCellEdited(evt)
    %ONCELLEDITED  A hand edit, recorded with the fingerprint that makes it
    %   safe to replay: what the event looked like at the moment it was
    %   changed. See applyEventOps/setValue.
        row = evt.Indices(1);
        col = evt.Indices(2);
        [preview, ~] = applyEventOps(original, recorded, srate, pnts);
        if row > numel(preview); refresh(); return; end
        was = preview(row);

        switch col
            case 2      % Type
                value = strtrim(char(string(evt.NewData)));
                if isempty(value); refresh(); return; end
                field = 'type';
            case 3      % Latency, in ms
                ms = str2double(string(evt.NewData));
                if isnan(ms) || ~isfinite(srate); refresh(); return; end
                value = ms * srate / 1000;
                field = 'latency';
            otherwise
                return;
        end

        recorded(end + 1) = makeOp('setValue', 'index', row, 'field', field, ...
            'value', value, 'wasType', char(string(was.type)), ...
            'wasLatency', double(was.latency));
        refresh();
    end

    function removeSelected()
        if isempty(opsList.Value) || isempty(recorded); return; end
        idx = find(strcmp(opsList.Items, opsList.Value), 1);
        if isempty(idx); return; end
        recorded(idx) = [];
        refresh();
    end

    function clearAll()
        recorded = emptyOps();
        refresh();
    end

    function onExport()
    %ONEXPORT  Write the previewed table as CSV. The edited table, not the
    %   original: the reason to export is usually to check the correction.
        [file, path] = uiputfile('*.csv', 'Export event table', 'events.csv');
        if isequal(file, 0); return; end
        [preview, ~] = applyEventOps(original, recorded, srate, pnts);
        writeEventCsv(fullfile(path, file), preview, srate);
    end

    function onOK()
        ops = recorded;
        uiresume(fig);
        delete(fig);
    end

    function onCancel()
        ops = [];
        uiresume(fig);
        delete(fig);
    end
end

% ======================================================================= %
function s = emptyOps()
%EMPTYOPS  Must carry every field any makeOp assigns: appending a struct
%   with more fields than the array was declared with is a hard "dissimilar
%   structures" error, and it fires on the first correction added rather
%   than at startup.
    s = struct('op', {}, 'from', {}, 'to', {}, 'types', {}, 'ms', {}, ...
        'index', {}, 'field', {}, 'value', {}, 'wasType', {}, 'wasLatency', {});
end

function op = makeOp(name, varargin)
%MAKEOP  One operation with every field present, unused ones empty, so the
%   struct array stays homogeneous.
    op = struct('op', name, 'from', '', 'to', '', 'types', {{}}, 'ms', 0, ...
        'index', 0, 'field', '', 'value', [], 'wasType', '', 'wasLatency', 0);
    for k = 1:2:numel(varargin)
        op.(varargin{k}) = varargin{k + 1};
    end
end

function items = describeOps(ops)
%DESCRIBEOPS  Each correction in the words an analyst would use, with the
%   ones that will not survive replay saying so.
    items = cell(1, numel(ops));
    for k = 1:numel(ops)
        o = ops(k);
        switch o.op
            case 'renameType'
                items{k} = sprintf('%d.  rename "%s" to "%s"', k, o.from, o.to);
            case 'deleteType'
                items{k} = sprintf('%d.  delete type "%s"', k, strjoin(o.types, ', '));
            case 'keepTypes'
                items{k} = sprintf('%d.  keep only "%s"', k, strjoin(o.types, ', '));
            case 'shiftLatency'
                if isempty(o.types)
                    what = 'all events';
                else
                    what = sprintf('"%s"', strjoin(o.types, ', '));
                end
                items{k} = sprintf('%d.  shift %s by %+g ms', k, what, o.ms);
            case 'setValue'
                items{k} = sprintf('%d.  event %d: %s = %s   (this recording only)', ...
                    k, o.index, o.field, char(string(o.value)));
            otherwise
                items{k} = sprintf('%d.  %s', k, o.op);
        end
    end
end

function rows = tableRows(events, srate)
%TABLEROWS  The event table as the grid shows it. Latency in milliseconds
%   first: samples are what the file stores, milliseconds are what an
%   analyst reasons in, and a trigger delay is only ever quoted in ms.
%
%   LATENCIES ARE FORMATTED AS TEXT, not left as numbers. A uitable renders
%   a large numeric cell in scientific notation, and latencies get large
%   quickly: half an hour at 500 Hz is 900,000 samples, which shows as
%   9.0e+05. Nobody reads a trigger time that way, and the column is
%   editable, so it also has to be something an analyst can sensibly type
%   over. sprintf here, str2double on the way back in (see onCellEdited).
%
%   BOTH COLUMNS ARE WHOLE NUMBERS. A fraction of a millisecond is below
%   what any of this can mean, and a fractional sample is not a thing an
%   analyst reads. Note that this is the DISPLAY only: a shift of 15 ms at
%   250 Hz really is 3.75 samples, and the stored latency keeps that. What
%   is rounded here is what is shown, never what is applied.
    if isempty(events)
        rows = cell(0, 4);
        return;
    end
    n = numel(events);
    rows = cell(n, 4);
    for i = 1:n
        lat = double(events(i).latency);
        rows{i, 1} = i;
        rows{i, 2} = char(string(events(i).type));
        if isfinite(srate) && srate > 0
            rows{i, 3} = sprintf('%.0f', lat / srate * 1000);
        else
            rows{i, 3} = '';
        end
        rows{i, 4} = sprintf('%.0f', lat);
    end
end

function types = typeList(events)
%TYPELIST  The distinct event types, in first-appearance order.
    if isempty(events)
        types = {};
        return;
    end
    all = arrayfun(@(e) char(string(e.type)), events, 'UniformOutput', false);
    types = unique(all, 'stable');
end

function writeEventCsv(file, events, srate)
    fid = fopen(file, 'w');
    if fid < 0
        return;
    end
    closeFile = onCleanup(@() fclose(fid));
    fprintf(fid, 'index,type,latency_ms,latency_samples\n');
    for i = 1:numel(events)
        lat = double(events(i).latency);
        if isfinite(srate) && srate > 0
            ms = lat / srate * 1000;
        else
            ms = NaN;
        end
        fprintf(fid, '%d,"%s",%.3f,%.3f\n', i, char(string(events(i).type)), ms, lat);
    end
end

function value = fieldOr(s, name, default)
    if isfield(s, name) && ~isempty(s.(name))
        value = double(s.(name));
    else
        value = default;
    end
end

function pos = centred(width, height)
    screen = get(groot, 'ScreenSize');
    pos = [(screen(3) - width) / 2, (screen(4) - height) / 2, width, height];
end
