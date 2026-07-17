function onListEvents(this)
%ONLISTEVENTS  Context-menu callback: list unique event types and
%   their occurrence counts for the selected dataset in a message
%   box. The menu item is disabled for epoched/averaged data (its
%   eligibility is baked into the node at creation time -- see
%   WorkSpaceTree.optsFor), so this only ever runs for continuous
%   data; root nodes are allowed here (unlike Rename/Delete), since a root
%   node is normally the raw continuous import -- the most common
%   case for wanting to see what events it contains.
    node = this.Workspace.ActiveTree.SelectedNodes;
    if isempty(node)
        return; % nothing selected
    end

    EEG = this.loadNodeEEG(node.UserData, 'list events for this dataset');
    if isempty(EEG)
        return;
    end
    titleText = sprintf('Events in "%s"', node.Name);

    if ~isfield(EEG, "event") || isempty(EEG.event)
        % LEGACY-JAVA-GUI: msgbox is a classic Java/AWT dialog, not
        % a uifigure -- see migration.md's "old-style Java-based
        % graphics" checklist.
        msgbox("This dataset has no events.", titleText);
        return;
    end

    % Event types may be numeric or char/string across loaders;
    % string() normalises both so unique() groups them correctly.
    types = strings(1, numel(EEG.event));
    for i = 1:numel(EEG.event)
        types(i) = string(EEG.event(i).type);
    end
    [uTypes, ~, ic] = unique(types);
    counts = accumarray(ic, 1);
    [counts, order] = sort(counts, "descend");
    uTypes = uTypes(order);

    lines = strings(numel(uTypes), 1);
    for i = 1:numel(uTypes)
        lines(i) = sprintf("%s: %d", uTypes(i), counts(i));
    end
    % LEGACY-JAVA-GUI: msgbox, see the note above.
    msgbox(char(strjoin(lines, newline)), titleText);
end
