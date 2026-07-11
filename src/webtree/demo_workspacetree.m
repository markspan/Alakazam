function demo_workspacetree()
%DEMO_WORKSPACETREE  Interactive, standalone try-out of the new tree.
%   Run this directly in MATLAB (not -batch) to see WorkSpaceTree live:
%   click a node to select it, double-click, right-click for the context
%   menu (List events is enabled only on "Fourier1"/"Average1" here, to
%   show the per-node enable/disable), and drag one node onto another
%   (plain drag = reparent; hold Ctrl while dropping = "apply
%   transformation" signal, which reverts the visual move and just prints
%   the event instead).
%
%   This does NOT touch the real Alakazam app or its data -- it is a
%   throwaway demo of the WorkSpaceTree class in an empty uifigure.
%
%   Requires: src/ on the MATLAB path (run from the Alakazam repo, or
%   addpath the src/ folder first).

    here = fileparts(mfilename('fullpath'));
    addpath(fullfile(here, '..', 'src'));

    fig = uifigure('Name', 'WorkSpaceTree demo', 'Position', [100 100 420 480]);
    log = uitextarea(fig, 'Position', [10 10 400 120], 'Editable', 'off');
    treePanel = uipanel(fig, 'Position', [10 140 400 330], 'Title', 'Tree');

    tree = WorkSpaceTree(treePanel, ...
        'SelectionChangedFcn',  @(e) addLog(sprintf('Selected: %s', e.Name)), ...
        'NodeDoubleClickedFcn', @(e) addLog(sprintf('Double-clicked: %s', e.Name)), ...
        'ContextMenuActionFcn', @(e) addLog(sprintf('Context menu: %s on %s', e.Action, e.Node.Name)), ...
        'NodeDroppedFcn',       @(e) onDropped(e));

    raw   = tree.addNode('RawImport', '', 'raw', 'demo1.mat', struct('isRoot', true));
    f1    = tree.addNode('Fourier1',  raw.Id, 'freq', 'demo2.mat', struct('canListEvents', true)); %#ok<NASGU>
    avg1  = tree.addNode('Average1',  raw.Id, 'time', 'demo3.mat', struct('canListEvents', true)); %#ok<NASGU>
    raw2  = tree.addNode('RawImport2', '', 'raw', 'demo4.mat', struct('isRoot', true)); %#ok<NASGU>

    addLog('Ready. Click, double-click, right-click, or drag nodes above.');

    function addLog(msg)
        log.Value = [log.Value; {msg}];
    end

    function onDropped(e)
        if isempty(e.Target)
            targetName = '(top level)';
        else
            targetName = e.Target.Name;
        end
        addLog(sprintf('Dropped %s onto %s (reparented=%d)', e.Source.Name, targetName, e.Reparented));
    end
end
