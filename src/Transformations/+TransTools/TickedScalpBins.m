function selected = TickedScalpBins(fig, eeg, nBinsTotal)
%TICKEDSCALPBINS  Which of EEG's NBINSTOTAL bins to draw: the ones
%   currently ticked on in this dataset's own AverageView tab, if one
%   happens to be open as a sibling in the same tabgroup. Falls back to
%   every bin if no such tab is open, its bin count no longer matches, or
%   every bin is unticked. Shared by ScalpDistributionView and Brain3DView
%   -- both draw a ScalpDistribution-family result (see
%   TransTools.ResolveScalpDistribution) and should agree on which bins
%   that means, whichever one happens to be open.
%
%   Looked up by EEG.ScalpSourceFile (the parent Average dataset's own
%   file, stashed by ResolveScalpDistribution before
%   Alakazam.persistResultNode overwrites EEG.File with this result's own
%   new cache path), not EEG.File itself -- by the time either view is
%   constructed, EEG.File no longer identifies the parent, only this
%   persisted result.
%
%   See also RESOLVESCALPDISTRIBUTION, SCALPDISTRIBUTIONVIEW, BRAIN3DVIEW.
    selected = true(1, nBinsTotal);
    if ~isfield(eeg, 'ScalpSourceFile')
        return;
    end
    tabGroup = fig.Parent;
    if isempty(tabGroup) || ~isprop(tabGroup, 'Children')
        return;
    end
    siblingTab = findobj(tabGroup.Children, 'flat', 'Tag', eeg.ScalpSourceFile);
    if isempty(siblingTab)
        return;
    end
    parentView = getappdata(siblingTab(1), 'AverageView');
    if isempty(parentView) || ~isvalid(parentView)
        return;
    end
    ownSeries = cellfun(@(s) strcmp(s.file, eeg.ScalpSourceFile), parentView.Series);
    if sum(ownSeries) ~= nBinsTotal
        return;
    end
    ticked = parentView.Visible(ownSeries);
    if any(ticked)
        selected = ticked;
    end
end
