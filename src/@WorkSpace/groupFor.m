function grp = groupFor(this, subject)
%GROUPFOR  The between-subjects group label assigned to SUBJECT (see
%   editSubjects), or '' if none is assigned. Exactly what
%   collectEntriesWithField attaches to each entry's own .group field for
%   the CSV exporters (exportMeasurementsCSV/exportSpectralCSV), and what
%   generateQuartoReport branches a between-subjects/mixed design on once
%   it reads the CSV's own "group" column back.
    grp = '';
    for i = 1:numel(this.Groups)
        if strcmp(this.Groups(i).subject, subject)
            grp = this.Groups(i).group;
            return;
        end
    end
end
