function problem = erpOverlayProblem(plotLabels, plotTimes, labels, times)
%ERPOVERLAYPROBLEM  Why one ERP cannot be drawn over another, or '' if it can.
%   PROBLEM = erpOverlayProblem(PLOTLABELS, PLOTTIMES, LABELS, TIMES) compares
%   the plot's channel labels and time axis (ms) with those of the dataset to
%   be overlaid, and returns a sentence for the user saying what stands in
%   the way, or '' when the two can share the axes.
%
%   BY CHANNEL NAME AND TIME, NOT BY SHAPE. Two averages worth comparing
%   routinely differ in shape: a re-referenced set has lost its reference, a
%   resampled one has fewer samples, an interpolated one a different channel
%   order. AverageView draws every line against its own time axis and finds
%   each channel by its label, so all an overlay needs is at least one
%   channel in common and time ranges that overlap. The size test this
%   replaces refused a resampled average outright, and let two montages of
%   equal size but different order through, where the lines would have been
%   drawn for different electrodes.
%
%   See also AVERAGEVIEW, ALAKAZAM.ONOVERLAYERP.
    problem = '';

    shared = intersect(normalise(plotLabels), normalise(labels));
    if isempty(shared)
        problem = sprintf(['It has no channel in common with the plot (the plot has %s; ' ...
            'this dataset has %s).'], listed(plotLabels), listed(labels));
        return;
    end

    if isempty(plotTimes) || isempty(times)
        problem = 'It has no time axis to draw against the plot''s.';
        return;
    end
    lo = max(min(plotTimes), min(times));
    hi = min(max(plotTimes), max(times));
    if hi <= lo
        problem = sprintf(['It covers %g to %g ms, which does not overlap the plot''s ' ...
            '%g to %g ms.'], min(times), max(times), min(plotTimes), max(plotTimes));
    end
end

% ======================================================================= %
function out = normalise(labels)
    out = lower(strtrim(cellstr(string(labels))));
end

function text = listed(labels)
%LISTED  The first few labels, enough to see what a montage is.
    labels = cellstr(string(labels));
    if numel(labels) > 4
        text = [strjoin(labels(1:4), ', ') sprintf(' and %d more', numel(labels) - 4)];
    else
        text = strjoin(labels, ', ');
    end
end
