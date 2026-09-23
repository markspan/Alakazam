function tf = producesSubjectAverage(call)
%PRODUCESSUBJECTAVERAGE  True for a transformation that PRODUCES a subject's
%   averaged ERP, as opposed to one that merely requires an averaged dataset
%   and passes it on.
%
%   TF = producesSubjectAverage(CALL) takes a cache sidecar's .Call (or an
%   EEG's own .Call field), which may be missing, empty, char or string.
%
%   THE DISTINCTION IS THE WHOLE POINT. Measure, ScalpDistribution and
%   Brain3D all take an averaged dataset, leave EEG.data and EEG.bindesc
%   exactly as they found them, and write a node that looks like a second
%   average of the same subject. Counting those as averages would give every
%   subject as many entries as they have downstream steps: a duplicate
%   candidate in the grand-average list, a doubled contribution to a design
%   cell, and a drop that silently overlays plots instead of running the
%   transformation it was asked to run.
%
%   WHAT COUNTS. Average.m, Deconvolve (which fits one waveform per bin and
%   returns it in Average's own shape, so everything downstream reads it
%   unchanged), and an empty call, which is how a loaded .erp file and
%   GrandAverage's own output both arrive (saveGrandAverage never sets it).
%
%   IT LIVES IN ONE FILE because four places need the same answer and had
%   four copies of it: findGrandAverageCandidates, collectDesignRecordings,
%   collectDataQualityEntries and isOverlayableAverage. A new way of
%   producing an average then has to be added here and nowhere else, which
%   is how Deconvolve came to be missing from all four at once.
%
%   See also FINDGRANDAVERAGECANDIDATES, COLLECTDESIGNRECORDINGS,
%   COLLECTDATAQUALITYENTRIES, ISOVERLAYABLEAVERAGE, AVERAGE, DECONVOLVE.
    if nargin < 1 || isempty(call)
        tf = true;      % no call recorded: a loaded .erp, or a grand average
        return;
    end
    tf = any(strcmpi(char(string(call)), {'Average', 'Deconvolve'}));
end
