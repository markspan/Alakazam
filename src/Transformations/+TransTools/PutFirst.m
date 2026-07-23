function list = PutFirst(list, value)
%PUTFIRST  Move VALUE to the front of the cellstr LIST, if present.
%   Case-insensitive; keeps LIST's own spelling of the match and drops no
%   entries. A no-op when VALUE is not in LIST. Used to pre-select a stored
%   choice in a dropdown (TransformOptionsDialog / settingsdlg take the first
%   cell as the initial selection).
    idx = find(strcmpi(list, char(string(value))), 1);
    if ~isempty(idx)
        list = [list(idx), list(setdiff(1:numel(list), idx, 'stable'))];
    end
end
