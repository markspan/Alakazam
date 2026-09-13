function ics = componentsTicked(data)
%COMPONENTSTICKED  The component numbers ticked for removal in the selector's
%   table: a sorted row vector of ICs, or empty when nothing is ticked.
%
%   DATA is the uitable's Data cell array as built by componentTableColumns:
%   column 1 the component number, the last column the Remove tick.
%
%   READ FROM COLUMN 1, NOT FROM THE ROW POSITION. The table is sortable, so
%   row 3 is not component 3 once the analyst has sorted by Label to bring
%   all the eye components together -- which is the main reason to sort at
%   all. Taking the IC from the row's own first cell is correct either way:
%   if a sort has reordered the rows, the number travelled with its row; if
%   not, it equals the row index anyway.
%
%   See also REMOVECOMPONENTSDIALOG, COMPONENTTABLECOLUMNS.
    ics = [];
    if isempty(data)
        return;
    end
    for r = 1:size(data, 1)
        tick = data{r, end};
        if isempty(tick) || ~(islogical(tick) || isnumeric(tick)) || ~any(tick)
            continue;
        end
        ic = data{r, 1};
        if isempty(ic) || ~isnumeric(ic) || ~isfinite(ic)
            continue;
        end
        ics(end + 1) = double(ic); %#ok<AGROW>
    end
    ics = sort(unique(ics(:)'));
end
