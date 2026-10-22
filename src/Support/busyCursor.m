function restoreFcn = busyCursor(fig, busy)
%BUSYCURSOR  The busy cursor over the whole of FIG, or its usual cursors again.
%   BUSYCURSOR(FIG, TRUE) shows the busy cursor wherever the pointer is in
%   FIG. The window's own Pointer covers its plain components, but stops at
%   the edge of every web page in it (the ribbon and the three trees), which
%   draw their own cursors. Each page is therefore sent a 'busy' event as
%   well, which the ribbon (AlakazamRibbon.html) and the trees
%   (src/webtree/src/bridge.js) listen for; a page that does not, a report
%   for instance, keeps its own cursors. BUSYCURSOR(FIG, FALSE) puts the
%   usual cursors back everywhere.
%
%   RESTORE = BUSYCURSOR(FIG) turns it on and returns an onCleanup that
%   turns it off again, whichever way the caller returns:
%
%       restoreCursor = busyCursor(this.MainFigure); %#ok<NASGU>
%
%   Before this, only the tree a branch was dropped on showed the busy
%   cursor (its page sets one itself at the drop), and the rest of the
%   window kept the arrow while the branch was applied.
%
%   A FIG that is empty or deleted is ignored, so a cleanup that outlives
%   its window does no harm.
%
%   See also BEGINBUSY, BUSYGATE.
    if nargin < 2
        busy = true;
    end
    if nargout > 0
        restoreFcn = onCleanup(@() busyCursor(fig, false));
    end
    if isempty(fig) || ~isvalid(fig)
        return;
    end

    pointers = ["arrow", "watch"];
    fig.Pointer = pointers(busy + 1);
    pages = findall(fig, 'Type', 'uihtml');
    for k = 1:numel(pages)
        try
            sendEventToHTMLSource(pages(k), 'busy', logical(busy));
        catch
            % A MATLAB without sendEventToHTMLSource (before R2023a): the
            % page keeps its own cursors, as before.
        end
    end
    if busy && strcmp(fig.Visible, 'on')
        drawnow;   % shown now, before the work, not after it
    end
end
