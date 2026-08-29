function groups = groupsFromStored(~, stored)
%GROUPSFROMSTORED  Normalise a .wksp file's own decoded "Groups" JSON
%   value back into this class's struct('subject',{},'group',{},
%   'person',{},'session',{}) shape. jsondecode('[]') comes back as a
%   0x0 double, not a 0x0 struct with the right fields -- handled here so
%   WorkSpace.m's constructor and load.m never have to special-case that
%   shape themselves.
%
%   .person/.session are read with FieldOr-style defaults, not required
%   like .subject/.group: a .wksp saved before the person/session
%   identity fields existed (see editSubjects) only ever has .subject/
%   .group, and every reader of this class's own Groups (personFor/
%   sessionFor) already treats a missing/blank .person as "same as
%   .subject" and a missing/blank .session as "none" -- so an old file
%   loads exactly as it always did, just via the wider struct shape now.
    groups = struct('subject', {}, 'group', {}, 'person', {}, 'session', {}, 'included', {});
    if isempty(stored)
        return;
    end
    stored = reshape(stored, 1, []);
    for i = 1:numel(stored)
        entry = stored(i);
        if ~isfield(entry, 'subject') || ~isfield(entry, 'group')
            continue;
        end
        person = '';
        if isfield(entry, 'person'); person = char(entry.person); end
        session = '';
        if isfield(entry, 'session'); session = char(entry.session); end
        % .included defaults to TRUE, and must: a .wksp written before
        % exclusion existed says nothing about it, and reading that silence
        % as "excluded" would empty an existing study on first open. Only an
        % explicit false excludes.
        included = true;
        if isfield(entry, 'included'); included = logical(entry.included); end
        groups(end + 1) = struct('subject', char(entry.subject), 'group', char(entry.group), ...
            'person', person, 'session', session, 'included', included); %#ok<AGROW>
    end
end
