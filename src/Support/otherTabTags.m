function tags = otherTabTags(tabs, keepTag)
%OTHERTABTAGS  The Tags of every tab except the one being kept, in tab
%   order, as a string array.
%
%   TAGS = otherTabTags(TABS, KEEPTAG). Empty when there is nothing else to
%   close.
%
%   AN ABSENT KEEPTAG RETURNS NOTHING, which is the important case. The
%   obvious reading of "everything except this one" would close every tab
%   when "this one" cannot be found, turning a stale tag into the loss of
%   every open plot. Doing nothing is the safe failure: the worst outcome
%   is a menu item that appears not to work, which is visible and
%   harmless, rather than one that quietly does far more than it offered.
%
%   Separated from Alakazam.closeOtherTabs so the choice of what to close
%   can be tested without a running application, the same split as
%   undockTabContent.
%
%   See also ALAKAZAM.CLOSEOTHERTABS, ALAKAZAM.CLOSETAB.
    tags = string.empty(1, 0);
    if isempty(tabs)
        return;
    end

    allTags = arrayfun(@(t) string(t.Tag), tabs(:)');
    if ~any(allTags == string(keepTag))
        return;
    end

    tags = allTags(allTags ~= string(keepTag));
end
