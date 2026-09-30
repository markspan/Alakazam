classdef Table < DialogFields.Field
%TABLE  An editable table of rows, with Add and Remove.
%
%   DialogFields.Table(COLUMNS, ROWS, Name, Value)
%     COLUMNS  a cell array of column descriptions, each a struct with
%                .name     the field each row stores it in
%                .label    the heading (default: the name)
%                .type     'numeric', 'text', 'logical', or a cellstr of
%                          choices, shown as a drop-down (default 'text')
%                .default  the value a new row starts with
%     ROWS     the stored rows: a cell array of scalar structs, a struct
%              array (what a JSON round trip hands back for rows of one
%              shape), or {} for none
%   and
%     'MinRows'  OK is refused with fewer rows (default 0)
%     'MaxRows'  Add stops here (default Inf)
%     'Height'   the table's height in pixels (default 150)
%
%   Value: a 1 x N CELL ARRAY OF SCALAR STRUCTS, one per row, each with
%   every column's field. That is the shape that survives a template's JSON
%   round trip in both directions (DEVELOPER.md, "Options must survive
%   JSON"), so a transformation normalises one shape on replay, not three.
%
%   See also DIALOGFIELDS.FIELD.

    properties (SetAccess = private)
        Columns        % 1 x nCol struct array: name, label, type, default
        Rows           % the rows at first, as a cell of structs
        MinRows double = 0
        MaxRows double = Inf
        TableHeight double = 150
    end

    properties (Access = private)
        Grid
        SelectedRows double = []
    end

    methods
        function this = Table(columns, rows, varargin)
            rest = this.takeCommonOptions(varargin);
            p = inputParser;
            p.addParameter('MinRows', 0);
            p.addParameter('MaxRows', Inf);
            p.addParameter('Height', 150);
            p.parse(rest{:});
            this.MinRows = p.Results.MinRows;
            this.MaxRows = p.Results.MaxRows;
            this.TableHeight = p.Results.Height;
            this.Columns = normaliseColumns(columns);
            if nargin < 2
                rows = {};
            end
            this.Rows = normaliseRows(rows);
        end

        function h = height(this)
            h = this.TableHeight + 30;
        end

        function w = width(~)
            w = 560;
        end

        function tf = spansBothColumns(~)
            tf = true;
        end

        function build(this, parent, onChange)
            grid = uigridlayout(parent, [2 3], 'RowHeight', {'1x', 24}, ...
                'ColumnWidth', {90, 90, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 4);
            this.Grid = this.registerControl(uitable(grid, ...
                'Data', this.cellsOf(this.Rows), ...
                'ColumnName', {this.Columns.label}, ...
                'ColumnEditable', true(1, numel(this.Columns)), ...
                'ColumnFormat', arrayfun(@columnFormat, this.Columns, 'UniformOutput', false), ...
                'RowName', {}, ...
                'CellEditCallback', @(~, ~) onChange(), ...
                'CellSelectionCallback', @(~, event) this.remember(event)));
            this.Grid.Layout.Row = 1;
            this.Grid.Layout.Column = [1 3];
            add = this.registerControl(uibutton(grid, 'Text', 'Add row', ...
                'ButtonPushedFcn', @(~, ~) this.addRow(onChange)));
            add.Layout.Row = 2;
            add.Layout.Column = 1;
            remove = this.registerControl(uibutton(grid, 'Text', 'Remove row', ...
                'ButtonPushedFcn', @(~, ~) this.removeRows(onChange)));
            remove.Layout.Row = 2;
            remove.Layout.Column = 2;
        end

        function v = value(this)
            data = this.Grid.Data;
            if isempty(data)
                v = {};
                return;
            end
            v = cell(1, size(data, 1));
            for r = 1:size(data, 1)
                row = struct();
                for c = 1:numel(this.Columns)
                    row.(this.Columns(c).name) = cellValue(data{r, c}, this.Columns(c).type);
                end
                v{r} = row;
            end
        end

        function problem = validate(this)
            problem = '';
            n = size(this.Grid.Data, 1);
            if n < this.MinRows
                problem = sprintf('Would you add at least %d row(s)? There are %d.', this.MinRows, n);
            end
        end
    end

    methods (Access = private)
        function data = cellsOf(this, rows)
        %CELLSOF  Rows as the table's cell array, one column per field.
            data = cell(numel(rows), numel(this.Columns));
            for r = 1:numel(rows)
                for c = 1:numel(this.Columns)
                    col = this.Columns(c);
                    if isfield(rows{r}, col.name)
                        data{r, c} = cellValue(rows{r}.(col.name), col.type);
                    else
                        data{r, c} = cellValue(col.default, col.type);
                    end
                end
            end
        end

        function remember(this, event)
            if isempty(event.Indices)
                this.SelectedRows = [];
            else
                this.SelectedRows = unique(event.Indices(:, 1)).';
            end
        end

        function addRow(this, onChange)
            if size(this.Grid.Data, 1) >= this.MaxRows
                return;
            end
            fresh = cellfun(@(d, t) cellValue(d, t), {this.Columns.default}, ...
                {this.Columns.type}, 'UniformOutput', false);
            this.Grid.Data = [this.Grid.Data; fresh];
            onChange();
        end

        function removeRows(this, onChange)
        %REMOVEROWS  The selected rows, or the last one when none is selected.
            n = size(this.Grid.Data, 1);
            if n == 0
                return;
            end
            gone = this.SelectedRows(this.SelectedRows <= n);
            if isempty(gone)
                gone = n;
            end
            this.Grid.Data(gone, :) = [];
            this.SelectedRows = [];
            onChange();
        end
    end
end

% ======================================================================= %
function columns = normaliseColumns(columns)
%NORMALISECOLUMNS  Column descriptions as one struct array with every field.
    if isstruct(columns)
        columns = num2cell(columns);
    end
    out = struct('name', {}, 'label', {}, 'type', {}, 'default', {});
    for k = 1:numel(columns)
        c = columns{k};
        name = char(string(c.name));
        entry.name = name;
        entry.label = char(string(fieldOr(c, 'label', name)));
        entry.type = fieldOr(c, 'type', 'text');
        entry.default = fieldOr(c, 'default', defaultFor(entry.type));
        out(end + 1) = entry; %#ok<AGROW>
    end
    columns = out;
end

function rows = normaliseRows(rows)
%NORMALISEROWS  Stored rows as a cell of scalar structs, whichever of the
%   shapes a JSON round trip produced.
    if isempty(rows)
        rows = {};
    elseif isstruct(rows)
        rows = reshape(num2cell(rows), 1, []);
    else
        rows = reshape(rows, 1, []);
    end
end

function f = columnFormat(column)
    if iscell(column.type)
        f = reshape(cellstr(string(column.type)), 1, []);
    elseif strcmpi(column.type, 'numeric')
        f = 'numeric';
    elseif strcmpi(column.type, 'logical')
        f = 'logical';
    else
        f = 'char';
    end
end

function v = cellValue(v, type)
%CELLVALUE  A value in the form its column holds.
    if iscell(type)
        v = char(string(v));
        if isempty(v)
            v = char(string(type{1}));
        end
    elseif strcmpi(type, 'numeric')
        if ischar(v) || isstring(v)
            v = str2double(v);
        end
        if isempty(v)
            v = NaN;
        end
        v = double(v(1));
    elseif strcmpi(type, 'logical')
        v = ~isempty(v) && logical(v(1));
    else
        v = char(string(v));
    end
end

function d = defaultFor(type)
    if iscell(type)
        d = char(string(type{1}));
    elseif strcmpi(type, 'numeric')
        d = 0;
    elseif strcmpi(type, 'logical')
        d = false;
    else
        d = '';
    end
end

function v = fieldOr(s, name, fallback)
    if isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = fallback;
    end
end
