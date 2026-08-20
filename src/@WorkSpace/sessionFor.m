function session = sessionFor(this, subject)
%SESSIONFOR  The session/day label SUBJECT (a raw file/root node's own
%   name) was assigned via editSubjects (e.g. "Day 1"), or '' if none.
%   Feeds collectEntriesWithField's own .session field, written out by
%   the CSV exporters as a session column.
%
%   Metadata only for now: generateQuartoReport does not yet treat
%   session as a statistical factor (that needs the report engine to
%   cross a second within-subjects factor against bin, not just record
%   which rows share it) -- see personFor's own header comment for the
%   identity half of this same feature.
    session = '';
    for i = 1:numel(this.Groups)
        if strcmp(this.Groups(i).subject, subject)
            session = this.Groups(i).session;
            return;
        end
    end
end
