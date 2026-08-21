function settings = TransformOptionsDialog(varargin)
%TRANSFORMOPTIONSDIALOG  uifigure-based replacement for uiextras.settingsdlg,
%   a classic Java/AWT dialog -- see migration.md's "old-style Java-based
%   graphics" note. Deliberately mirrors settingsdlg's own call signature
%   (title/Description/separator/{label;fieldname},default pairs) so every
%   call site only needed its function name swapped, not its argument list
%   rewritten:
%
%       settings = TransformOptionsDialog( ...
%           'Description', 'Set the parameters for Baseline', ...
%           'title', 'Baseline options', ...
%           'separator', 'Location:', ...
%           {'Start'; 'Start'}, stored.Start, ...
%           {'Stop'; 'Stop'}, stored.Stop);
%
%   Field kind is inferred from each DEFAULT value, exactly like
%   settingsdlg: a cell array of strings is a dropdown (its first element
%   the initial selection -- callers already pre-order that with their own
%   putFirst-style helper), a scalar logical is a checkbox, a numeric
%   value is a numeric edit field, anything else a text edit field.
%
%   Cancelling (or closing the window) returns SETTINGS = [] (empty).
%   This deliberately does NOT match settingsdlg's own single-output
%   contract, which silently returns the pre-fill/default values on
%   Cancel -- indistinguishable from pressing OK with nothing changed.
%   Since no caller of settingsdlg ever checked for that (there was no
%   way to, from a single output arg), clicking Cancel on e.g. Baseline's
%   options dialog used to run Baseline anyway with default values and
%   add a tree node the user never asked for. Every call site MUST check
%   `if isempty(settings) ... end` and abort (return an empty EEG,
%   handled by Alakazam.onTransformation the same way a cancelled
%   transformation always is) rather than proceeding.
%
%   See also ALAKAZAMSETTINGS, SETTINGSDIALOG (the app's own global-
%   settings dialog -- schema-driven from AlakazamSettings, a different
%   use case from this one-off, call-site-parameterized dialog).

    [accentColor, bgColor] = dialogChromeColors();

    [dlgTitle, description, fieldSpecs] = parseArgs(varargin);

    % [] until OK is actually pressed -- Cancel (button or window close)
    % leaves this as [], the caller's signal to abort. Never pre-filled
    % from the defaults (that was the bug: see this function's own
    % header comment).
    settings = [];

    nRows = numel(fieldSpecs);
    rowHeight = repmat({28}, 1, nRows);
    for k = 1:nRows
        if strcmp(fieldSpecs(k).kind, 'separator')
            rowHeight{k} = 22;
        elseif isMultiSelect(fieldSpecs(k).default)
            % A multi-select list box needs room for several rows; size it to
            % the number of choices (capped) rather than the single-line 28px.
            nItems = numel(fieldSpecs(k).default.Items);
            rowHeight{k} = min(140, max(60, 18 * nItems + 8));
        end
    end

    headerHeight = 40;
    descHeight = 0;
    if strlength(string(description)) > 0
        descHeight = 36;
    end
    fieldsHeight = sum(cell2mat(rowHeight)) + (nRows - 1) * 8 + 16;
    buttonHeight = 46;
    figHeight = headerHeight + descHeight + fieldsHeight + buttonHeight;
    figWidth = 420;

    fig = uifigure('Name', dlgTitle, 'Position', [400 300 figWidth figHeight], ...
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
        'RowHeight', rowHeight, 'Padding', [16 8 16 8], 'RowSpacing', 8);
    fieldsGrid.Layout.Row = rowIdx;
    rowIdx = rowIdx + 1;

    controls = struct();
    for k = 1:numel(fieldSpecs)
        spec = fieldSpecs(k);
        if strcmp(spec.kind, 'separator')
            sepLabel = uilabel(fieldsGrid, 'Text', spec.label, 'FontWeight', 'bold');
            sepLabel.Layout.Row = k;
            sepLabel.Layout.Column = [1, 2];
            continue;
        end

        label = uilabel(fieldsGrid, 'Text', spec.label, 'VerticalAlignment', 'center');
        label.Layout.Row = k;
        label.Layout.Column = 1;

        default = spec.default;
        if isMultiSelect(default)
            sel = intersect(default.Selected, default.Items, 'stable');
            if isempty(sel); selVal = {}; else; selVal = cellstr(sel); end
            ctrl = uilistbox(fieldsGrid, 'Items', string(default.Items), ...
                'Multiselect', 'on', 'Value', selVal);
        elseif iscell(default)
            ctrl = uidropdown(fieldsGrid, 'Items', string(default), ...
                'Value', string(default{1}));
        elseif islogical(default) && isscalar(default)
            ctrl = uicheckbox(fieldsGrid, 'Text', '', 'Value', default);
        elseif isnumeric(default) && isscalar(default)
            ctrl = uieditfield(fieldsGrid, 'numeric', 'Value', default);
        else
            ctrl = uieditfield(fieldsGrid, 'text', 'Value', char(string(default)));
        end
        ctrl.Layout.Row = k;
        ctrl.Layout.Column = 2;
        controls.(spec.name) = ctrl;
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

    uiwait(fig);

    function onOK()
        for kk = 1:numel(fieldSpecs)
            fs = fieldSpecs(kk);
            if ~strcmp(fs.kind, 'field')
                continue;
            end
            ctrl = controls.(fs.name);
            if isMultiSelect(fs.default)
                v = ctrl.Value;
                if isempty(v); settings.(fs.name) = {}; else; settings.(fs.name) = cellstr(v); end
            elseif iscell(fs.default)
                settings.(fs.name) = char(ctrl.Value);
            else
                settings.(fs.name) = ctrl.Value;
            end
        end
        delete(fig);
    end

    function onCancel()
        % settings is already [] (its initial value, never touched by
        % anything but onOK) -- nothing to do beyond closing the window.
        delete(fig);
    end
end

function tf = isMultiSelect(default)
%ISMULTISELECT  True when a field default is a multiSelectField(...) wrapper.
    tf = isstruct(default) && isscalar(default) && ...
        isfield(default, 'AlzMultiSelect') && default.AlzMultiSelect;
end

function [dlgTitle, description, fieldSpecs] = parseArgs(args)
%PARSEARGS  Walks the settingsdlg-style varargin: 'title'/'description'
%   set the two header strings; 'separator' inserts a section-heading
%   entry; anything else is a {label;fieldname} (or bare fieldname)
%   followed by its default value.
    dlgTitle = 'Adjust settings';
    description = '';
    fieldSpecs = struct('kind', {}, 'label', {}, 'name', {}, 'default', {});

    i = 1;
    while i <= numel(args)
        key = args{i};
        if (ischar(key) || isstring(key)) && strcmpi(key, 'title')
            dlgTitle = char(args{i + 1});
            i = i + 2;
        elseif (ischar(key) || isstring(key)) && strcmpi(key, 'description')
            description = char(args{i + 1});
            i = i + 2;
        elseif (ischar(key) || isstring(key)) && strcmpi(key, 'separator')
            fieldSpecs(end + 1) = struct('kind', 'separator', 'label', char(args{i + 1}), ...
                'name', '', 'default', []); %#ok<AGROW>
            i = i + 2;
        else
            if iscell(key)
                label = key{1};
                name = key{2};
            else
                label = char(key);
                name = char(key);
            end
            % args(i+1) (paren indexing into the cell array, a 1x1 cell),
            % not args{i+1} (its unwrapped contents): struct() treats a
            % bare cell-array VALUE as "expand into a struct array" (one
            % of its more surprising built-in behaviours) -- when the
            % default itself is a cell array of choices, that would try
            % to broadcast it against the other, scalar fields and
            % error. Passing the 1x1 cell keeps 'default' scalar
            % (a single field whose value happens to be a cell array).
            fieldSpecs(end + 1) = struct('kind', 'field', 'label', label, ...
                'name', name, 'default', args(i + 1)); %#ok<AGROW>
            i = i + 2;
        end
    end
end
