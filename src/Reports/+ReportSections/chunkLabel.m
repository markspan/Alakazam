function s = chunkLabel(varargin)
%CHUNKLABEL  A unique, valid Quarto/knitr chunk label built from one or
%   more MATLAB text pieces (e.g. a section kind tag, window label,
%   measure type, combo-bin label), each sanitised via labelPiece and
%   joined with hyphens. Uniqueness across the whole document follows
%   from generateQuartoReport's own main loop: each combination of
%   (section kind, window, measure type[, combo label]) is only ever
%   assembled into one chunk.
    pieces = cellfun(@ReportSections.labelPiece, varargin, 'UniformOutput', false);
    s = strjoin(pieces, '-');
end

