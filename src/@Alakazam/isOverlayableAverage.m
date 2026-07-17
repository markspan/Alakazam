function tf = isOverlayableAverage(~, targetEEG, sourceEEG)
%ISOVERLAYABLEAVERAGE  True when two datasets are averages of equal shape.
%   Used by evaluateDroppedBranch to decide whether dropping one
%   dataset onto another should overlay their average plots rather than
%   re-apply a transformation.
    tf = strcmpi(targetEEG.DataFormat, "AVERAGED") && ...
         strcmpi(sourceEEG.DataFormat, "AVERAGED") && ...
         isequal(size(targetEEG.data), size(sourceEEG.data));
end
