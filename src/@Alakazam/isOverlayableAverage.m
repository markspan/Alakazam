function tf = isOverlayableAverage(~, targetEEG, sourceEEG)
%ISOVERLAYABLEAVERAGE  True when dropping SOURCEEEG onto TARGETEEG means
%   "overlay the two averages" rather than "replay this step there".
%   Used by evaluateDroppedBranch to decide whether dropping one
%   dataset onto another should overlay their average plots rather than
%   re-apply a transformation.
%
%   Both must be drawn by the same view that overlays averages
%   (AlakazamPlotter.viewClassFor): as ERP waveforms (AverageView) or as
%   spectra (FourierView, an averaged spectrum), so a scalp map or a
%   time-frequency result is never taken for one, and an ERP is never
%   overlaid on a spectrum. Whether
%   the two can then share the axes (a channel and a time range in common)
%   is not decided here: overlayAverage asks datasetOverlayProblem and tells the
%   user when they cannot, instead of quietly replaying Average onto an
%   average, which could only fail. It used to require equal array sizes,
%   which refused a resampled average and let two montages of equal size
%   in different orders through.
%
%   Being drawn as an ERP is not enough on its own: a downstream analysis
%   step that merely REQUIRES Averaged input (Measure, for one) leaves
%   EEG.data untouched, so its own result looks exactly like "a second
%   average" too -- dropping THAT onto an existing average must still run
%   the transformation (add Measure to this subject too), not silently
%   overlay plots and skip it. Which calls actually PRODUCE an average from
%   non-averaged input is producesSubjectAverage's answer, shared with the
%   grand-average, design and data-quality collectors that each need the
%   same one; anything else reaching here with Averaged-shaped data is
%   annotating or measuring an existing average, not making one.
    if isfield(sourceEEG, 'Call')
        sourceIsFreshAverage = producesSubjectAverage(sourceEEG.Call);
    else
        sourceIsFreshAverage = true;    % no call at all: a grand average
    end
    targetView = AlakazamPlotter.viewClassFor(targetEEG);
    tf = sourceIsFreshAverage && ...
         any(strcmp(targetView, {'AverageView', 'FourierView'})) && ...
         strcmp(AlakazamPlotter.viewClassFor(sourceEEG), targetView);
end
