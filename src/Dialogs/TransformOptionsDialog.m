function settings = TransformOptionsDialog(varargin)
%TRANSFORMOPTIONSDIALOG  The generated settings dialog: a column of labelled
%   fields, OK and Cancel, built from one call.
%
%       settings = TransformOptionsDialog( ...
%           'Description', 'Set the parameters for Baseline', ...
%           'title', 'Baseline options', ...
%           'separator', 'Location:', ...
%           {'Start'; 'Start'}, stored.Start, ...
%           {'Stop'; 'Stop'}, stored.Stop);
%
%   The arguments mirror uiextras.settingsdlg's, which this replaced (a
%   classic Java/AWT dialog, see migration.md): 'title' and 'Description'
%   set the header, 'separator' inserts a section heading, and every other
%   argument is a {label; fieldname} pair (or a bare fieldname) followed by
%   the field's default. OK returns a struct with one field per fieldname.
%
%   WHAT A DEFAULT CAN BE. A plain value makes the field its kind implies,
%   as it always has: a cellstr a drop-down (its first entry chosen), a
%   scalar logical a checkbox, a scalar number a numeric box, anything else
%   a text box, and multiSelectField(...) a multi-select list. A field
%   object from the +DialogFields package makes that field instead:
%
%     DialogFields.Choice     a drop-down whose shown items and stored
%                             values differ ('Spherical spline' -> 'spherical')
%     DialogFields.Number     a numeric box with limits, or whole numbers only
%     DialogFields.Channels   the dataset's channels by label, with All,
%                             None and Scalp EEG
%     DialogFields.Bins       the dataset's bins by label, with All, None and
%                             Differences
%     DialogFields.Table      an editable table of rows, with Add and Remove
%     DialogFields.TextArea   a block of text, checked before the dialog
%                             closes (a script, a list of statements)
%     DialogFields.Plot       a preview redrawn from the current values
%
%   and any field takes 'EnabledWhen', @(values) ..., which greys it out
%   while the other fields' values say it does not apply. These are what
%   used to push a transformation into writing a dialog of its own; with
%   them the generated one goes further before that escape hatch is needed,
%   and a new kind of field is a class in the package, not a change here.
%
%   OK CHECKS FIRST. Each enabled field may refuse its value (a required
%   channel list left empty, a script that does not parse, too few rows),
%   and the dialog then says why and stays open, so a mistake is reported
%   before a node exists rather than after.
%
%   Cancelling (or closing the window) returns SETTINGS = [] (empty). This
%   deliberately does NOT match settingsdlg's own contract, which returned
%   the defaults on Cancel, indistinguishable from pressing OK: clicking
%   Cancel on Baseline's options used to run Baseline with its defaults and
%   add a node nobody asked for. Every call site MUST check
%   `if isempty(settings) ... end` and abort.
%
%   See also DIALOGFIELDS.FIELD, DIALOGFIELDS.FROMDEFAULT, MULTISELECTFIELD,
%   SETTINGSDIALOG (the application's own settings, schema-driven).

    [accentColor, bgColor] = dialogChromeColors();
    [dlgTitle, description, specs] = parseArgs(varargin);

    % [] until OK is pressed and every field has accepted its value; Cancel
    % (button or window close) leaves it [], the caller's signal to abort.
    settings = [];

    LABELLINE = 22;   % the heading line above a field that spans the row
    nRows = numel(specs);
    rowHeight = cell(1, max(nRows, 1));
    rowHeight{1} = 28;
    figWidth = 420;
    for k = 1:nRows
        spec = specs{k};
        if strcmp(spec.kind, 'separator')
            rowHeight{k} = 22;
            continue;
        end
        rowHeight{k} = spec.field.height();
        if spec.field.spansBothColumns()
            rowHeight{k} = rowHeight{k} + LABELLINE;
        end
        figWidth = max(figWidth, spec.field.width());
    end

    headerHeight = 40;
    % The description gets the lines its text needs at this width. It used
    % to get two whatever it said, so a longer one stopped mid-sentence.
    descHeight = 0;
    if strlength(string(description)) > 0
        descHeight = 12 + 17 * descriptionLines(description, figWidth);
    end
    fieldsHeight = sum(cell2mat(rowHeight)) + (numel(rowHeight) - 1) * 8 + 16;
    buttonHeight = 46;
    screen = get(groot, 'ScreenSize');
    % A dialog taller than the screen scrolls its fields rather than hiding
    % OK below the bottom edge.
    fieldsView = min(fieldsHeight, max(200, 0.85 * screen(4) - headerHeight - descHeight - buttonHeight));
    figHeight = headerHeight + descHeight + fieldsView + buttonHeight;

    fig = uifigure('Name', dlgTitle, 'Position', fitOnScreen([400 300 figWidth figHeight]), ...
        'Color', bgColor, 'Resize', 'off');

    outerRows = {headerHeight};
    if descHeight > 0
        outerRows{end + 1} = descHeight;
    end
    outerRows{end + 1} = '1x';
    outerRows{end + 1} = buttonHeight;
    outer = uigridlayout(fig, [numel(outerRows), 1], 'RowHeight', outerRows, ...
        'Padding', [0 0 0 0], 'RowSpacing', 0);

    rowIdx = 1;
    header = uilabel(outer, 'Text', ['  ', dlgTitle], 'FontSize', 14, ...
        'FontWeight', 'bold', 'FontColor', [1 1 1], 'BackgroundColor', accentColor, ...
        'VerticalAlignment', 'center');
    header.Layout.Row = rowIdx;
    rowIdx = rowIdx + 1;

    if descHeight > 0
        descPanel = uigridlayout(outer, [1 1], 'Padding', [16 4 16 4]);
        descPanel.Layout.Row = rowIdx;
        uilabel(descPanel, 'Text', char(description), 'WordWrap', 'on');
        rowIdx = rowIdx + 1;
    end

    fieldsGrid = uigridlayout(outer, [max(nRows, 1), 2], 'ColumnWidth', {160, '1x'}, ...
        'RowHeight', rowHeight, 'Padding', [16 8 16 8], 'RowSpacing', 8, 'Scrollable', 'on');
    fieldsGrid.Layout.Row = rowIdx;
    rowIdx = rowIdx + 1;

    for k = 1:nRows
        spec = specs{k};
        if strcmp(spec.kind, 'separator')
            sepLabel = uilabel(fieldsGrid, 'Text', spec.label, 'FontWeight', 'bold');
            sepLabel.Layout.Row = k;
            sepLabel.Layout.Column = [1, 2];
            continue;
        end

        if spec.field.spansBothColumns()
            cell_ = uigridlayout(fieldsGrid, [2 1], 'RowHeight', {LABELLINE - 4, '1x'}, ...
                'Padding', [0 0 0 0], 'RowSpacing', 4);
            cell_.Layout.Row = k;
            cell_.Layout.Column = [1, 2];
            uilabel(cell_, 'Text', spec.label);
            holder = uigridlayout(cell_, [1 1], 'Padding', [0 0 0 0]);
            holder.Layout.Row = 2;
        else
            label = uilabel(fieldsGrid, 'Text', spec.label, 'VerticalAlignment', 'center');
            label.Layout.Row = k;
            label.Layout.Column = 1;
            holder = uigridlayout(fieldsGrid, [1 1], 'Padding', [0 0 0 0]);
            holder.Layout.Row = k;
            holder.Layout.Column = 2;
        end
        spec.field.build(holder, @onChange);
    end

    buttonRow = uigridlayout(outer, [1, 3], 'ColumnWidth', {'1x', 90, 90}, ...
        'Padding', [16 6 16 10], 'ColumnSpacing', 8);
    buttonRow.Layout.Row = rowIdx;
    cancelBtn = uibutton(buttonRow, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) onCancel());
    cancelBtn.Layout.Column = 2;
    okBtn = uibutton(buttonRow, 'Text', 'OK', 'BackgroundColor', accentColor, ...
        'FontColor', [1 1 1], 'ButtonPushedFcn', @(~, ~) onOK());
    okBtn.Layout.Column = 3;

    fig.CloseRequestFcn = @(~, ~) onCancel();
    onChange();   % the first enabling pass, and the first preview

    uiwait(fig);

    % ------------------------------------------------------------------- %
    function onChange()
    %ONCHANGE  Re-apply every field's EnabledWhen and redraw the previews,
    %   from the values as they are now. A predicate or a preview that
    %   fails leaves its field enabled rather than taking the dialog down.
        values = currentValues();
        for kk = 1:numel(specs)
            s = specs{kk};
            if strcmp(s.kind, 'separator')
                continue;
            end
            if ~isempty(s.field.EnabledWhen)
                try
                    s.field.setEnabled(logical(s.field.EnabledWhen(values)));
                catch
                    s.field.setEnabled(true);
                end
            end
            s.field.refresh(values);
        end
    end

    function values = currentValues()
        values = struct();
        for kk = 1:numel(specs)
            s = specs{kk};
            if strcmp(s.kind, 'field') && s.field.hasValue()
                values.(s.name) = s.field.value();
            end
        end
    end

    function onOK()
        values = currentValues();
        for kk = 1:numel(specs)
            s = specs{kk};
            if ~strcmp(s.kind, 'field') || ~isEnabled(s.field, values)
                continue;
            end
            problem = s.field.validate();
            if ~isempty(problem)
                uialert(fig, problem, sprintf('%s: please check', stripColon(s.label)));
                return;
            end
        end
        settings = values;
        delete(fig);
    end

    function onCancel()
        % settings is still [] (only onOK sets it), so closing is all there is.
        delete(fig);
    end
end

% ======================================================================= %
function tf = isEnabled(field, values)
%ISENABLED  Whether a field applies to the values as they are: a disabled
%   field is not asked to validate (a required channel list for a step that
%   is switched off is not required).
    tf = true;
    if ~isempty(field.EnabledWhen)
        try
            tf = logical(field.EnabledWhen(values));
        catch
            tf = true;
        end
    end
end

function s = stripColon(label)
    s = regexprep(char(label), ':\s*$', '');
end

function n = descriptionLines(text, figWidth)
%DESCRIPTIONLINES  How many lines the description wraps to at this width:
%   about 55 characters a line at the 420-pixel dialog's 388-pixel label,
%   proportionally more when a wide field widens the dialog, each paragraph
%   starting a line of its own.
    perLine = max(30, round(55 * (figWidth - 32) / 388));
    paragraphs = strsplit(char(string(text)), newline);
    n = sum(max(1, ceil(cellfun(@numel, paragraphs) / perLine)));
end

function [dlgTitle, description, specs] = parseArgs(args)
%PARSEARGS  Walks the settingsdlg-style arguments: 'title'/'description'
%   set the two header strings; 'separator' inserts a heading; anything else
%   is a {label; fieldname} (or bare fieldname) followed by its default,
%   which DialogFields.fromDefault turns into a field.
    dlgTitle = 'Adjust settings';
    description = '';
    specs = {};

    i = 1;
    while i <= numel(args)
        key = args{i};
        if i == numel(args)
            throw(MException('Alakazam:TransformOptionsDialog', ...
                'The last argument, %s, has no value after it.', describeKey(key)));
        end
        if (ischar(key) || isstring(key)) && strcmpi(key, 'title')
            dlgTitle = char(args{i + 1});
        elseif (ischar(key) || isstring(key)) && strcmpi(key, 'description')
            description = char(args{i + 1});
        elseif (ischar(key) || isstring(key)) && strcmpi(key, 'separator')
            specs{end + 1} = struct('kind', 'separator', 'label', char(args{i + 1}), ...
                'name', '', 'field', []); %#ok<AGROW>
        else
            if iscell(key)
                label = char(key{1});
                name = char(key{2});
            else
                label = char(key);
                name = char(key);
            end
            spec = struct('kind', 'field', 'label', label, 'name', name, 'field', []);
            spec.field = DialogFields.fromDefault(args{i + 1});
            specs{end + 1} = spec; %#ok<AGROW>
        end
        i = i + 2;
    end
end

function s = describeKey(key)
    if iscell(key)
        s = char(string(key{end}));
    else
        s = char(string(key));
    end
end
