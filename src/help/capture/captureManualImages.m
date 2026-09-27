function captureManualImages(varargin)
%CAPTUREMANUALIMAGES  Regenerate the user manual's screenshots from the running app.
%   captureManualImages() opens Alakazam on each dataset the manual uses,
%   builds every input the pictures need, opens each transformation's dialog
%   or result view, and writes the pictures to manual/images. What each
%   picture shows, and on which data, is listed in manualShots.
%
%   NOTHING REAL IS TOUCHED. Each dataset's raw file is copied into a scratch
%   workspace of its own (under tempdir, or 'Scratch'), with its own cache,
%   so no workspace or cache of the user's changes. Results are computed
%   through TransTools.invoke, the call the app itself makes for a
%   transformation, and handed to the app's own plotter, so a picture shows
%   exactly what a user would see, without a node being written anywhere.
%   The one exception is a dataset of kind 'workspace' (the Grand Average
%   and report pictures), which opens a workspace that already exists,
%   selects nodes and cancels dialogs, and changes nothing either.
%
%   A dialog is caught by a timer while the transformation waits for it,
%   exported, and closed, which the dialog reads as Cancel. Its fields show
%   the settings the manual describes because they are stored as that
%   transformation's settings first, which is where every dialog seeds
%   itself from.
%
%   Name-value options:
%     'Only'      cellstr of picture names to retake (default: all)
%     'Datasets'  cellstr of dataset keys to limit to (default: all)
%     'Output'    folder to write to (default: manual/images)
%     'Scratch'   folder for the scratch workspaces (default: tempdir)
%
%   Run it from the repository root, with the datasets in DATA.md in place:
%       addpath('src/help/capture'); captureManualImages();
%
%   See also MANUALSHOTS, TRANSTOOLS.INVOKE, EXPORTAPP.
    parsed = inputParser();
    parsed.addParameter('Only', {}, @(v) iscellstr(v) || isstring(v));
    parsed.addParameter('Datasets', {}, @(v) iscellstr(v) || isstring(v));
    parsed.addParameter('Output', '', @(v) ischar(v) || isstring(v));
    parsed.addParameter('Scratch', '', @(v) ischar(v) || isstring(v));
    parsed.parse(varargin{:});
    opts = parsed.Results;

    repo = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
    out = char(opts.Output);
    if isempty(out)
        out = fullfile(repo, 'manual', 'images');
    end
    if ~isfolder(out); mkdir(out); end
    scratch = char(opts.Scratch);
    if isempty(scratch)
        scratch = fullfile(tempdir, 'alakazam-manual-capture');
    end

    [datasets, shots] = manualShots(repo);
    keep = true(1, numel(shots));
    if ~isempty(opts.Only); keep = keep & ismember({shots.name}, cellstr(opts.Only)); end
    if ~isempty(opts.Datasets); keep = keep & ismember({shots.dataset}, cellstr(opts.Datasets)); end
    shots = shots(keep);

    failed = {};
    for key = unique({shots.dataset}, 'stable')
        ds = datasets.(key{1});
        try
            ctx = openDataset(repo, ds, fullfile(scratch, key{1}));
        catch err
            fprintf('CAPTURE dataset %s could not be opened: %s\n', key{1}, err.message);
            failed = [failed, {shots(strcmp({shots.dataset}, key{1})).name}]; %#ok<AGROW>
            continue;
        end
        for s = shots(strcmp({shots.dataset}, key{1}))
            t0 = tic;
            try
                runShot(ctx, s, out);
                fprintf('CAPTURE %-34s done (%.0f s)\n', s.name, toc(t0));
            catch err
                fprintf('CAPTURE %-34s FAILED: %s\n', s.name, getReport(err, 'basic', 'hyperlinks', 'off'));
                failed{end + 1} = s.name; %#ok<AGROW>
            end
            closeTabs(ctx.app);
            closeStrays(ctx.app);
        end
    end
    if isempty(failed)
        fprintf('CAPTURE all %d picture(s) written to %s\n', numel(shots), out);
    else
        fprintf('CAPTURE %d of %d failed: %s\n', numel(failed), numel(shots), strjoin(failed, ', '));
    end
end

% ======================================================================= %
function ctx = openDataset(repo, ds, folder)
%OPENDATASET  Alakazam open on the dataset: a scratch workspace holding a
%   copy of its raw file(s), or, for kind 'workspace', one that exists.
    cd(repo);
    if strcmp(ds.kind, 'workspace')
        wksp = fullfile(repo, ds.workspace);
        cacheDir = tempdir;
    else
        if isfolder(folder); rmdir(folder, 's'); end
        for d = {'raw', 'cache', 'exports'}
            mkdir(fullfile(folder, d{1}));
        end
        for f = reshape(cellstr(ds.files), 1, [])
            copyfile(fullfile(repo, f{1}), fullfile(folder, 'raw'));
        end
        slash = @(p) [strrep(p, '\', '/') '/'];
        spec = struct('RawDirectory', slash(fullfile(folder, 'raw')), ...
            'CacheDirectory', slash(fullfile(folder, 'cache')), ...
            'ExportsDirectory', slash(fullfile(folder, 'exports')), ...
            'TransformSettings', struct(), 'Groups', []);
        wksp = fullfile(folder, 'capture.wksp');
        fid = fopen(wksp, 'w'); fprintf(fid, '%s', jsonencode(spec)); fclose(fid);
        cacheDir = fullfile(folder, 'cache');
    end
    app = startAlakazam(wksp);
    app.MainFigure.Position = [1 41 1920 1040];
    settle(15);
    nodes = app.Workspace.Tree.allNodes();
    root = [];
    if ~isempty(nodes); root = nodes(find([nodes.IsRoot], 1)); end
    ctx = struct('app', app, 'repo', repo, 'ds', ds, 'root', root, ...
        'stages', containers.Map(), 'cacheDir', cacheDir);
    if ~isempty(ds.template) && ~isempty(root)
        % A dataset whose pictures need a real tree: apply a template to the
        % recording the way the context menu does.
        app.Workspace.Tree.SelectedNodes = root;
        app.onSelectionChanged(root, app.Workspace.Tree);
        settle(5);
        app.onApplyTemplate(fullfile(repo, ds.template));
        delete(findall(groot, 'Type', 'figure', 'Name', 'Template applied'));
        closeTabs(app);
        settle(5);
    end
end

% ======================================================================= %
function EEG = stage(ctx, name)
%STAGE  The dataset at a named stage of the dataset's chain, computed once:
%   its parent stage, then the stage's transformation through
%   TransTools.invoke, exactly as the app replays a stored step.
    if isKey(ctx.stages, name)
        EEG = ctx.stages(name);
        return;
    end
    if strcmp(name, 'raw')
        EEG = ctx.app.loadNodeEEG(ctx.root.UserData, 'open this dataset');
        ctx.stages(name) = EEG;
        return;
    end
    def = ctx.ds.stages(strcmp({ctx.ds.stages.name}, name));
    if isempty(def)
        error('captureManualImages:noStage', 'Dataset %s has no stage "%s".', ctx.ds.key, name);
    end
    parent = stage(ctx, def.parent);
    params = resolveParams(ctx.repo, def.params);
    t0 = tic;
    [EEG, ~] = TransTools.invoke(def.transform, parent, params);
    EEG.Call = def.transform;
    EEG.params = params;
    EEG.id = def.transform;
    fprintf('CAPTURE   stage %s.%s (%s) in %.0f s\n', ctx.ds.key, name, def.transform, toc(t0));
    ctx.stages(name) = EEG;
end

function params = resolveParams(repo, params)
%RESOLVEPARAMS  A stage's options, or those of a template node when the
%   stage names one (struct with .template and .node), so the manual's
%   pictures use the settings the shipped templates use.
    if isstruct(params) && isscalar(params) && isfield(params, 'template')
        raw = jsondecode(fileread(fullfile(repo, params.template)));
        if isfield(raw, 'nodes'); items = raw.nodes; else; items = raw.steps; end
        if isstruct(items); items = num2cell(items); end
        params = items{params.node}.params;
        if isstruct(params) && isfield(params, 'bins') && isfield(params, 'script')
            params = rmfield(params, 'bins');   % as the app's templateParams does
        end
    end
end

% ======================================================================= %
function runShot(ctx, s, out)
    app = ctx.app;
    switch s.kind
        case 'dialog'
            input = stage(ctx, s.input);
            if ~isempty(s.seed)
                TransformSettings.set(s.transform, resolveParams(ctx.repo, s.seed));
            end
            captureDialog(@() feval(s.transform, input), fullfile(out, [s.name '.png']), s);
        case 'view'
            EEG = stage(ctx, s.input);
            EEG.File = fullfile(ctx.cacheDir, [s.name '.mat']);
            app.Workspace.EEG = EEG;
            app.Plotter.plotCurrent();
            settle(8);
            configureView(ctx, viewOf(app), s);
            captureFigure(app, fullfile(out, [s.name '.jpg']), 'plot');
        case 'window'
            selectNode(ctx, s);
            if ~isempty(s.ribbonTab)
                d = app.Ribbon.Component.Data;
                d.activeTab = s.ribbonTab;
                app.Ribbon.Component.Data = d;
                settle(4);
            end
            if ~isempty(s.channel) || ~isempty(s.bin) || ~isempty(s.only)
                configureView(ctx, viewOf(app), s);
            end
            ext = '.jpg';
            if strcmp(s.crop, 'ribbon'); ext = '.png'; end
            captureFigure(app, fullfile(out, [s.name ext]), s.crop);
            if ~isempty(s.ribbonTab)
                d = app.Ribbon.Component.Data;
                d.activeTab = 'home';
                app.Ribbon.Component.Data = d;
            end
        case 'appdialog'
            selectNode(ctx, s);
            captureDialog(@() app.onRibbonAction(s.action), fullfile(out, [s.name '.png']), s);
        case 'method'
            selectNode(ctx, s);
            captureDialog(@() app.(s.action)(), fullfile(out, [s.name '.png']), s);
        case 'call'
            % A dialog opened on a stage's result, with no tree node
            % involved: ACTION is a function of (EEG, app) that opens it.
            input = stage(ctx, s.input);
            captureDialog(@() s.action(input, app), fullfile(out, [s.name '.png']), s);
        % No kind for a uialert: exportapp leaves it out of the picture, so
        % such a shot silently saved the bare main window (the Rejection
        % breakdown did, a copy of the ERP image beside it in the manual).
        % Show what an alert says in the manual's text instead.
        otherwise
            error('captureManualImages:kind', 'Unknown shot kind "%s".', s.kind);
    end
end

function selectNode(ctx, s)
%SELECTNODE  Click the node a picture needs, by name, in the tree it names.
    if isempty(s.select); return; end
    tree = ctx.app.Workspace.(s.tree);
    nodes = tree.allNodes();
    hit = find(strcmp({nodes.Name}, s.select), 1);
    if isempty(hit)
        error('captureManualImages:node', 'No node "%s" in %s.', s.select, s.tree);
    end
    tree.SelectedNodes = nodes(hit);
    ctx.app.onSelectionChanged(nodes(hit), tree);
    settle(10);
end

% ======================================================================= %
function configureView(ctx, view, s)
%CONFIGUREVIEW  Put a result view in the state the picture shows, through
%   the view's own controls: the channel and bin (applyFocus, as moving
%   between tabs does), the sort, the series shown, the time, the projection.
    if isempty(view); return; end
    if ~isempty(s.overlay) && ismethod(view, 'addDataset')
        other = stage(ctx, s.overlay);
        other.File = fullfile(ctx.cacheDir, [s.overlay '.mat']);
        view.addDataset(other);
        settle(4);
    end
    if (~isempty(s.channel) || ~isempty(s.bin)) && ismethod(view, 'applyFocus')
        view.applyFocus(struct('Channel', char(s.channel), 'Bin', char(s.bin)));
        settle(4);
    end
    if ~isempty(s.sort) && isprop(view, 'SortDropdown')
        dropdown = view.SortDropdown;
        hit = find(startsWith(dropdown.Items, s.sort), 1);
        if isempty(hit)
            warning('captureManualImages:sort', 'No sort "%s": %s', s.sort, strjoin(dropdown.Items, ' | '));
        else
            dropdown.Value = dropdown.ItemsData(hit);
            dropdown.ValueChangedFcn(dropdown, []);
        end
    end
    if ~isempty(s.only) && isprop(view, 'CheckboxGrid')
        for pass = 1:60
            boxes = findall(view.CheckboxGrid, 'Type', 'uicheckbox');
            changed = false;
            for k = 1:numel(boxes)
                keep = any(contains(boxes(k).Text, cellstr(s.only)));
                if boxes(k).Value ~= keep
                    boxes(k).Value = keep;
                    boxes(k).ValueChangedFcn(boxes(k), []);
                    changed = true;
                    break;   % a toggle rebuilds the boxes: find them again
                end
            end
            if ~changed; break; end
            drawnow;
        end
    end
    if isprop(view, 'Strip') && ~isempty(view.Strip)
        strip = view.Strip;
        if ~isempty(s.bin) && ~isempty(strip.BinDropdown)
            dd = strip.BinDropdown;
            hit = find(strcmp(dd.Items, s.bin), 1);
            if ~isempty(hit)
                if isempty(dd.ItemsData); dd.Value = dd.Items{hit}; else; dd.Value = dd.ItemsData(hit); end
                dd.ValueChangedFcn(dd, []);
                settle(3);
            end
        end
        if ~isempty(s.time)
            strip.Slider.Value = s.time;
            strip.Slider.ValueChangedFcn(strip.Slider, struct('Value', s.time));
        end
    end
    if ~isempty(s.projection)
        for dd = reshape(findall(ctx.app.PlotsTabGroup.SelectedTab, 'Type', 'uidropdown'), 1, [])
            hit = find(contains(dd.Items, s.projection), 1);
            if ~isempty(hit)
                if isempty(dd.ItemsData); dd.Value = dd.Items{hit}; else; dd.Value = dd.ItemsData(hit); end
                if ~isempty(dd.ValueChangedFcn); dd.ValueChangedFcn(dd, []); end
                break;
            end
        end
    end
    if ~isempty(s.bin) && isprop(view, 'CurrentBin') && isprop(view, 'EEG') ...
            && ismethod(view, 'onKey') && isfield(view.EEG, 'bindesc')
        % A spectral view takes the channel from the focus but not the bin,
        % so step to the bin with its own arrow key, as a user would.
        labels = cellfun(@(l) char(string(l)), {view.EEG.bindesc.label}, 'UniformOutput', false);
        target = find(strcmp(labels, s.bin), 1);
        for step = 1:numel(labels)
            if isempty(target) || view.CurrentBin == target; break; end
            if view.CurrentBin < target; key = 'rightarrow'; else; key = 'leftarrow'; end
            view.onKey(struct('Key', key));
        end
        settle(3);
    end
    if ~isempty(s.xlim)
        % A spectrum's x range, for a result whose interesting part is a
        % small corner of a wide axis (0 to 100 Hz of a 1000 Hz Nyquist).
        % Set on the view's first axes directly: the picture needs the
        % range, and no view control takes one as a number.
        plotAxes = findall(ctx.app.PlotsTabGroup.SelectedTab, 'Type', 'axes');
        if ~isempty(plotAxes)
            xlim(plotAxes(end), s.xlim);
        end
    end
    settle(6);
end

function view = viewOf(app)
    view = [];
    tab = app.PlotsTabGroup.SelectedTab;
    if isempty(tab); return; end
    stored = getappdata(tab);
    for name = reshape(fieldnames(stored), 1, [])
        candidate = stored.(name{1});
        if isa(candidate, 'AlakazamView') && isscalar(candidate) && isvalid(candidate)
            view = candidate;
            return;
        end
    end
end

% ======================================================================= %
function captureFigure(app, file, crop)
%CAPTUREFIGURE  The main window, whole, or cropped to the plot area (below
%   the tab titles) or to the ribbon.
    tmp = [tempname '.png'];
    exportapp(app.MainFigure, tmp);
    img = imread(tmp);
    delete(tmp);
    fig = app.MainFigure.Position;
    scale = size(img, 2) / fig(3);
    switch crop
        case 'plot'
            pos = getpixelposition(app.PlotsTabGroup, true);
            pos(4) = pos(4) - 25;            % the tab titles
            img = cropTo(img, pos, fig(4), scale);
        case 'ribbon'
            pos = getpixelposition(app.Ribbon.Grid, true);
            img = cropTo(img, pos, fig(4), scale);
    end
    [~, ~, ext] = fileparts(file);
    if strcmpi(ext, '.jpg')
        imwrite(img, file, 'Quality', 90);
    else
        imwrite(img, file);
    end
end

function img = cropTo(img, pos, figHeight, scale)
    top = max(1, round((figHeight - (pos(2) + pos(4))) * scale) + 1);
    bottom = min(size(img, 1), round((figHeight - pos(2) + 1) * scale));
    left = max(1, round((pos(1) - 1) * scale) + 1);
    right = min(size(img, 2), round((pos(1) + pos(3) - 1) * scale));
    img = img(top:bottom, left:right, :);
end

% ======================================================================= %
function captureDialog(openFcn, file, s)
%CAPTUREDIALOG  Run OPENFCN, which opens a dialog (modal or not); catch the
%   first new window that has buttons, let it finish drawing, optionally
%   switch it to a tab, export it and close it. Closing is Cancel to every
%   dialog here. A progress window has no buttons, so it is passed over.
    known = findall(groot, 'Type', 'figure');
    ticks = 0;
    caught = false;
    poller = timer('ExecutionMode', 'fixedSpacing', 'Period', 1, 'TimerFcn', @(~, ~) poll());
    start(poller);
    try
        openFcn();
    catch err
        if ~caught
            stop(poller); delete(poller);
            rethrow(err);
        end
    end
    waited = 0;
    while ~caught && waited < 30      % a window that does not block its caller
        pause(1); waited = waited + 1;
    end
    stop(poller); delete(poller);
    if ~caught
        error('captureManualImages:noDialog', 'No dialog appeared.');
    end

    function poll()
        if caught; return; end
        figs = findall(groot, 'Type', 'figure');
        fresh = figs(~ismember(figs, known) & strcmp({figs.Visible}', 'on'));
        fresh = fresh(arrayfun(@(f) ~isempty(findall(f, 'Type', 'uibutton')) || ...
            ~isempty(findall(f, 'Type', 'uihtml')), fresh));
        if isempty(fresh); return; end
        ticks = ticks + 1;
        if ticks < s.settle; return; end
        fig = fresh(1);
        if ~isempty(s.dialogTab)
            tabs = findall(fig, 'Type', 'uitab');
            hit = tabs(strcmp({tabs.Title}, s.dialogTab));
            if ~isempty(hit)
                hit(1).Parent.SelectedTab = hit(1);
                drawnow; pause(1);
            end
        end
        exportapp(fig, file);
        caught = true;
        close(fig);
    end
end

% ======================================================================= %
function closeTabs(app)
    tabs = app.PlotsTabGroup.Children;
    for k = numel(tabs):-1:1
        try
            app.closeTab(tabs(k).Tag);
        catch
            delete(tabs(k));
        end
    end
    drawnow;
end

function closeStrays(app)
%CLOSESTRAYS  Any window a picture left open (a result figure, a message).
    figs = findall(groot, 'Type', 'figure');
    for f = reshape(figs, 1, [])
        if f ~= app.MainFigure && isvalid(f)
            delete(f);
        end
    end
end

function settle(seconds)
    drawnow;
    pause(seconds);
    drawnow;
end
