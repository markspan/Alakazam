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
%   Cancelling (or closing the window) returns SETTINGS built from the
%   ORIGINAL default values, unchanged -- the same contract settingsdlg's
%   single-output form has (none of its callers ever check for an empty
%   result), so no call site needs its own cancel handling.
%
%   See also ALAKAZAMSETTINGS, SETTINGSDIALOG (the app's own global-
%   settings dialog -- schema-driven from AlakazamSettings, a different
%   use case from this one-off, call-site-parameterized dialog).

    accentColor = [0.290 0.498 0.788]; % matches AlakazamRibbon.html's .alz-tab-home (#4a7fc9)
    bgColor     = [0.9608 0.9608 0.9608]; % uifigure's own default Color

    [dlgTitle, description, fieldSpecs] = parseArgs(varargin);

    % Original defaults, kept verbatim -- what's returned if the dialog is
    % cancelled/closed instead of confirmed with OK.
    settings = struct();
    for k = 1:numel(fieldSpecs)
        if strcmp(fieldSpecs(k).kind, 'field')
            settings.(fieldSpecs(k).name) = defaultValueOf(fieldSpecs(k).default);
        end
    end

    nRows = numel(fieldSpecs);
    rowHeight = repmat({28}, 1, nRows);
    for k = 1:nRows
        if strcmp(fieldSpecs(k).kind, 'separator')
            rowHeight{k} = 22;
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
        if iscell(default)
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
            if iscell(fs.default)
                settings.(fs.name) = char(ctrl.Value);
            else
                settings.(fs.name) = ctrl.Value;
            end
        end
        delete(fig);
    end

    function onCancel()
        delete(fig);
    end
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

function v = defaultValueOf(default)
%DEFAULTVALUEOF  The value a field's DEFAULT represents when the dialog is
%   cancelled: a dropdown's default is a cell array with the current
%   choice first (the same convention settingsdlg itself uses), so that
%   becomes the plain string; everything else is used as-is.
    if iscell(default)
        v = char(default{1});
    else
        v = default;
    end
end
