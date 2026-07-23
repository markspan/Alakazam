function s = multiSelectField(items, selected)
%MULTISELECTFIELD  Wrap a choice list as a multi-select field for
%   TransformOptionsDialog. Pass the return value in place of a plain
%   cellstr default: a cellstr renders as a single-choice dropdown, whereas
%   this renders as a multi-select list box.
%
%       TransformOptionsDialog(..., ...
%           {'Detectors'; 'Method'}, multiSelectField(ALL, chosen), ...);
%
%   ITEMS is the full cellstr of choices; SELECTED the subset (cellstr, char
%   or string) initially ticked -- absent/empty means none. The dialog
%   returns the chosen subset as a cellstr in the field named by the label
%   pair. Built with direct field assignment (not struct(...)) so a cellstr
%   value is stored as-is rather than triggering struct()'s cell-expansion.
    if nargin < 2 || isempty(selected)
        selected = {};
    end
    s.AlzMultiSelect = true;
    s.Items    = cellstr(string(items(:)))';
    s.Selected = cellstr(string(selected(:)))';
end
