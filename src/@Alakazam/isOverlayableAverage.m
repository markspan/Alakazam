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
%   this subject too), not silently overlay plots and skip it. Only
%   Average.m (sourceEEG.Call == "Average") and GrandAverage (which never
%   sets .Call at all, see saveGrandAverage.m) actually PRODUCE a fresh
%   average from non-Averaged input; anything else reaching here with
%   Averaged-shaped data is annotating/measuring an existing one, so only
%   those two are eligible for the overlay reading of a drop.
    sourceIsFreshAverage = ~isfield(sourceEEG, 'Call') || isempty(sourceEEG.Call) ...
        || strcmpi(sourceEEG.Call, 'Average');
    tf = sourceIsFreshAverage && ...
         strcmpi(targetEEG.DataFormat, "AVERAGED") && ...
         strcmpi(sourceEEG.DataFormat, "AVERAGED") && ...
         isequal(size(targetEEG.data), size(sourceEEG.data));
end
