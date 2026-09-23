function tf = isOverlayableAverage(~, targetEEG, sourceEEG)
%ISOVERLAYABLEAVERAGE  True when two datasets are averages of equal shape.
%   Used by evaluateDroppedBranch to decide whether dropping one
%   dataset onto another should overlay their average plots rather than
%   re-apply a transformation.
%
%   DataFormat == "Averaged" + matching shape alone is not enough: a
%   downstream analysis step that merely REQUIRES Averaged input (Measure,
%   for one) leaves EEG.data untouched, so its own result looks exactly
%   like "a second average of the same shape" too -- dropping THAT onto an
%   existing average must still run the transformation (add Measure to
%   this subject too), not silently overlay plots and skip it. Which calls
%   actually PRODUCE an average from non-averaged input is
%   producesSubjectAverage's answer, shared with the grand-average,
%   design and data-quality collectors that each need the same one;
%   anything else reaching here with Averaged-shaped data is
%   annotating or measuring an existing average, not making one.
    if isfield(sourceEEG, 'Call')
        sourceIsFreshAverage = producesSubjectAverage(sourceEEG.Call);
    else
        sourceIsFreshAverage = true;    % no call at all: a grand average
    end
    tf = sourceIsFreshAverage && ...
         strcmpi(targetEEG.DataFormat, "AVERAGED") && ...
         strcmpi(sourceEEG.DataFormat, "AVERAGED") && ...
         isequal(size(targetEEG.data), size(sourceEEG.data));
end
