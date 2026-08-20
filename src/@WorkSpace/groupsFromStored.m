function groups = groupsFromStored(~, stored)
%GROUPSFROMSTORED  Normalise a .wksp file's own decoded "Groups" JSON
%   value back into this class's struct('subject',{},'group',{}) shape.
%   jsondecode('[]') comes back as a 0x0 double, not a 0x0 struct with
%   the right fields, and this class only ever writes valid
%   subject/group pairs -- both handled here so WorkSpace.m's constructor
%   and load.m never have to special-case either shape themselves.
    groups = struct('subject', {}, 'group', {});
    if isempty(stored)
        return;
    end
    stored = reshape(stored, 1, []);
    for i = 1:numel(stored)
        entry = stored(i);
        if isfield(entry, 'subject') && isfield(entry, 'group')
            groups(end + 1) = struct('subject', char(entry.subject), 'group', char(entry.group)); %#ok<AGROW>
        end
    end
end
