function row = eyeTrackingRow(EEG, row)
%EYETRACKINGROW  How well the eye track was joined, as one provenance row.
%   ROW = eyeTrackingRow(EEG, BLANK) fills BLANK, a blank row in the
%   caller's own provenance shape, from what EyeTracking recorded in
%   EEG.etc.alz.eyeTracking, and returns [] when no eye track was joined
%   onto this dataset. EEG.etc travels down every branch, so an averaged or
%   deconvolved node still carries the record of the join made on its
%   continuous ancestor.
%
%   The numbers go in columns, not in the prose: n and n_total are the
%   shared triggers and the EEG's numbered ones, pct the share matched,
%   pct_within_one and mean_offset_ms how closely they lined up, and
%   threshold the limit the join was held to. The report tabulates them, and
%   what a report tabulates must not have to be read back out of a sentence.
%
%   See also DATAQUALITYMETRICS, DECONVOLUTIONQUALITY, EYETRACKING.
    info = [];
    if isfield(EEG, 'etc') && isstruct(EEG.etc) && isfield(EEG.etc, 'alz') ...
            && isstruct(EEG.etc.alz) && isfield(EEG.etc.alz, 'eyeTracking')
        info = EEG.etc.alz.eyeTracking;
    end
    if isempty(info) || ~isstruct(info) || ~isfield(info, 'quality')
        row = [];
        return;
    end
    q = info.quality;
    row.step = 'EyeTracking';
    row.item = 'shared triggers';
    row.n = q.nShared;
    row.n_total = q.nTriggers;
    row.pct = q.pctMatched;
    row.pct_within_one = q.pctWithinOne;
    row.mean_offset_ms = q.meanAbsMs;
    if isfield(info, 'limits') && isfield(info.limits, 'minPctWithinOne')
        row.threshold = info.limits.minPctWithinOne;
    end
    [~, name, ext] = fileparts(char(string(info.file)));
    row.detail = sprintf('anchored on %d and %d; worst offset %d sample(s); %s%s (%s)', ...
        info.startEvent, info.endEvent, q.maxAbsSamples, name, ext, info.how);
end
