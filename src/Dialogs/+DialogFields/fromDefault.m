function field = fromDefault(default)
%FROMDEFAULT  The field a TransformOptionsDialog default stands for.
%
%   FIELD = DialogFields.fromDefault(DEFAULT) returns DEFAULT itself when it
%   is already a field, and otherwise infers the kind from the value, as the
%   generated dialog always has:
%     a DialogFields.Field           that field
%     a multiSelectField(...)        a MultiSelect
%     a cell array of strings        a Choice, the first entry chosen
%     a scalar logical               a Checkbox
%     a scalar number                a Number
%     anything else                  a Text
%   so every dialog written before fields were objects reads as it did.
%
%   See also TRANSFORMOPTIONSDIALOG, DIALOGFIELDS.FIELD.
    if isa(default, 'DialogFields.Field')
        field = default;
    elseif isstruct(default) && isscalar(default) && isfield(default, 'AlzMultiSelect') ...
            && default.AlzMultiSelect
        field = DialogFields.MultiSelect(default.Items, default.Selected);
    elseif iscell(default)
        field = DialogFields.Choice(default, default{1});
    elseif islogical(default) && isscalar(default)
        field = DialogFields.Checkbox(default);
    elseif isnumeric(default) && isscalar(default)
        field = DialogFields.Number(default);
    else
        field = DialogFields.Text(default);
    end
end
