function tf = includedFor(this, subject)
%INCLUDEDFOR  Whether SUBJECT (a raw file / root node's own name) is part
%   of the study, as set in editSubjects. True unless it was explicitly
%   excluded.
%
%   Replaces an implicit rule. Until this existed, a recording left out of
%   the analysis was left out by leaving its Group blank: the report's own R
%   dropped every row with no group, so a blank field silently decided who
%   was in the study. That conflated two different things -- "I have not
%   assigned this one to a group" and "this one should not be analysed" --
%   and made the decision a side effect of an empty box rather than
%   something anyone chose or could see.
%
%   Exclusion now applies at the source: collectEntriesWithField leaves an
%   excluded recording out of the exported measurements entirely, so it is
%   absent from every report, statistic and grand average built from them,
%   for one stated reason rather than several implicit ones.
%
%   Defaults to true for a recording with no entry at all, and for a
%   workspace saved before exclusion existed (see groupsFromStored): a
%   study is in the analysis unless somebody says otherwise.
%
%   See also WORKSPACE.EDITSUBJECTS, WORKSPACE.GROUPFOR, DERIVEDESIGN.
    tf = true;
    for i = 1:numel(this.Groups)
        if strcmp(this.Groups(i).subject, subject)
            if isfield(this.Groups, 'included') && ~isempty(this.Groups(i).included)
                tf = logical(this.Groups(i).included);
            end
            return;
        end
    end
end
