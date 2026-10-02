function label = grandAverageLabel(file)
%GRANDAVERAGELABEL  How a grand average is shown in its tree: its name, with
%   a note when datasets it was made from have been deleted.
%
%   LABEL = GRANDAVERAGELABEL(FILE) is the grand average's own name, or that
%   name followed by "(sources deleted)" when none of its recorded sources
%   exists any more, or "(3 of 10 sources deleted)" when some are gone. It
%   keeps the numbers it was computed with, which nothing can recompute, so
%   it says so rather than passing for a current result; ERP & Report no
%   longer draws it (grandAveragesForReport). Recalculate it on datasets
%   that exist and the note goes.
%
%   See also GRANDAVERAGERECORD, MARKGRANDAVERAGESOURCES.
    record = grandAverageRecord(file);
    label = record.name;
    nMissing = nnz(record.missing);
    if nMissing == 0
        return;
    end
    if nMissing == numel(record.sources)
        label = sprintf('%s (sources deleted)', label);
    else
        label = sprintf('%s (%d of %d sources deleted)', label, nMissing, numel(record.sources));
    end
end
