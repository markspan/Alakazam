classdef Brain3DView < AlakazamView
%BRAIN3DVIEW  A rotatable 3D brain surface, coloured by an averaged ERP,
%   scrubbable by time, in any of four Projection modes:
%     "Scalp topography" (default) -- the scalp-measured amplitude,
%       spherically interpolated onto a BrainNet Viewer brain surface for
%       legibility; not source-localized in any way. See DrawBrainMap.
%     "Source estimate (dSPM)" -- a real, noise-normalized
%       Tikhonov-regularized minimum-norm inverse (Dale et al. 2000).
%     "Source estimate (eLORETA)" -- exact low-resolution tomography
%       (Pascual-Marqui 2007): zero localization error for a single
%       source, but an amplitude rather than a normalized statistic.
%     "Source estimate (sLORETA)" -- standardized low-resolution
%       tomography (Pascual-Marqui 2002), standardized by its own
%       resolution matrix rather than by projected noise.
%
%       THE THREE INVERSE SCALES ARE NOT COMPARABLE TO EACH OTHER, and
%       none is in microvolts; each carries its own colorbar label from
%       TransTools.InverseSolution rather than a hard-coded one. All three
%       are computed with FieldTrip's own template BEM head model and a
%       template cortical-sheet source model, drawn directly onto that
%       cortical sheet. See TransTools.BuildSourceForwardModel/
%       InverseSolution/DrawSourceMap. IMPORTANT CAVEAT, also shown
%       in the mode dropdown's own tooltip: this uses a TEMPLATE head
%       model and TEMPLATE electrode positions, not a per-subject MRI or
%       digitised cap -- it is a genuine inverse computation, more
%       physiologically grounded than the scalp-topography mode, but is
%       still an approximation, not a validated per-subject localization.
%       No inverse colour scale is a physical unit -- none is comparable
%       to scalp mode's signed microvolts, by design, not a rendering bug
%       (this comes up often enough to repeat here as well as in the mode
%       tooltip and README).
%       Needs FieldTrip (a ~400 MB one-time download, consent-gated -- see
%       TransTools.ensureFieldTrip), fetched lazily the first time this
%       mode is selected. Switching into it the first time (or onto a
%       bin not yet computed) is noticeably slower than scalp mode --
%       leadfield/inverse computation, not just a redraw -- shown with a
%       modal busy indicator (see ensureSourceReady/beginBusy).
%
%       Every source-mode redraw titles the axes with a one-line fit
%       readout ("Fit: NN% variance explained", see fitVarianceLabel),
%       backed by TransTools.InverseSolution's own INFO.ResidualVariance.
%       This is comparable across all three methods (unlike their colour
%       scales), but it is a check on the FORWARD MODEL/registration, not
%       on anatomical accuracy -- a good fit does not mean any one
%       vertex's activity is correctly localized, only that SOME current
%       distribution close to this one explains the scalp data well.
%
%   The 3D-mesh sibling of ScalpDistributionView: same shared resolution
%   (TransTools.ResolveScalpDistribution, via the Brain3D transformation
%   instead of ScalpDistribution), same time-scrubbing uislider/Play
%   button, same single-plot-plus-bin-dropdown interface -- one head, with
%   a "Bin" dropdown when this dataset has more than one bin, since only
%   one bin's projection is ever drawn onto the mesh at a time (see
%   TransTools.DrawBrainMap for why a grid of several such meshes at once
%   was never on the table here: rebuilding an 82k-vertex mesh per tile,
%   times several tiles, every slider tick would not stay smooth -- and
%   for the projection/interpolation itself). The dropdown/time-label/
%   Play-button/slider scaffolding itself is shared with
%   ScalpDistributionView too -- see TimeScrubStrip.
%
%   Rotation is free: Axes.Interactions is set to rotateInteraction in the
%   constructor, so a plain click-and-drag orbits the head (see the
%   constructor's own comment for why this is set explicitly rather than
%   left to uiaxes' automatic 2-D/3-D interaction heuristic). The standard
%   axtoolbar (as ScalpDistributionView's own axes uses) is added too, for
%   its zoom/pan/restore-view/datatip buttons as alternate modes.
%
%   Only draws the bins currently ticked on in this dataset's own Average
%   plot, exactly like ScalpDistributionView -- see
%   TransTools.TickedScalpBins, shared between the two.
%
%   Style follows the project standard.
%
%   See also ALAKAZAMPLOTTER, BRAIN3D, SCALPDISTRIBUTIONVIEW, TIMESCRUBSTRIP,
%   TRANSTOOLS.DRAWBRAINMAP, TRANSTOOLS.READBRAINMESHNV,
%   TRANSTOOLS.RESOLVESCALPDISTRIBUTION, TRANSTOOLS.TICKEDSCALPBINS,
%   TRANSTOOLS.BUILDSOURCEFORWARDMODEL, TRANSTOOLS.INVERSESOLUTION,
%   TRANSTOOLS.COMPUTESOURCEESTIMATE,
%   TRANSTOOLS.DRAWSOURCEMAP, TRANSTOOLS.ENSUREFIELDTRIP.

    properties
    end

    properties (SetAccess = private)
        Figure          % owning uitab
        EEG             % averaged dataset (channels x samples[ x bins]) with .ScalpChanlocs/.ScalpHasPos/.ScalpMapLimit
        Grid            % uigridlayout: mode-dropdown row, optional bin-dropdown row, the 3D axes, the slider strip
        Axes            % the single 3D uiaxes
        Mesh            % TransTools.ReadBrainMeshNV(Meshes/BrainMesh_ICBM152.nv), read once at construction (Scalp-topography mode's mesh)
        BrainPatch      % the current mode's patch graphics object, updated in place on every redraw (see DrawBrainMap/DrawSourceMap)
        BinIndices      % original EEG.data 3rd-dim index for each selectable bin
        SelectedBin     % index INTO BinIndices of the bin currently drawn
        Strip           % TimeScrubStrip, the bin-dropdown/time-label/Play-button/slider scaffolding
        Mode = "scalp"  % "scalp", or one of the inverse methods "mne"/"eloreta"/"sloreta" -- see the class header comment
        Signed = false  % source modes only: project onto the cortical normal (signed) rather than take the magnitude
        ModeDropdown    % uidropdown choosing Mode
        SignedCheckbox  % uicheckbox choosing Signed, enabled only in a source mode
    end

    properties (Access = private)
        AxRow           % row index of Axes/the colorbar in Grid, needed again when rebuildColorbar reruns after a Mode switch
        ColorbarAxes    % the centring sub-grid TransTools.AddSharedColorbar built (its own name notwithstanding), deleted/rebuilt on a Mode switch (different scale/label per mode)
        SourceLeadfield     % TransTools.BuildSourceForwardModel's own leadfield (session-cached there already; kept here to avoid re-resolving labels every bin)
        SourceModel         % TransTools.BuildSourceForwardModel's own cortical-sheet struct (.pos/.tri) -- Source-estimate mode's mesh
        SourceResolvedLabels % channel order SourceLeadfield's rows actually correspond to -- see BuildSourceForwardModel's own header comment
        SourceElec          % TransTools.BuildSourceForwardModel's own template electrode definition -- ft_inverse_* takes it positionally
        SourceHeadmodel     % ditto, the template BEM volume conductor
        SourcePower         % nVertex x nTime source estimate, for whichever bin SourcePowerBin says
        SourcePowerBin      % which SelectedBin SourcePower was last computed for, or [] if none yet
        SourcePowerMethod   % which inverse method SourcePower was computed with -- switching method must invalidate the cache just as switching bin does
        SourcePowerSigned   % which orientation SourcePower was computed with -- likewise: a signed and a magnitude estimate are different numbers
        SourceNormals       % TransTools.SurfaceNormals(SourceModel), computed once per source model (pure geometry)
        SourceMapLimit      % shared [0, max] colour scale for the bin SourcePower holds
        SourceScaleLabel    % colorbar label for SourcePower's own method, from TransTools.InverseSolution's INFO
        SourceScaleNote     % the caveat belonging next to that label (shown in the dropdown tooltip)
        SourceResidualVariance % TransTools.InverseSolution's own INFO.ResidualVariance for the current bin/method -- shown as the axes title, see fitVarianceLabel
    end

    methods
        function this = Brain3DView(fig, eeg)
        %BRAIN3DVIEW  Build the rotatable brain view for EEG in FIG.
            this.Figure = fig;
            this.EEG    = eeg;

            meshFile = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'Meshes', 'BrainMesh_ICBM152.nv');
            this.Mesh = TransTools.ReadBrainMeshNV(meshFile);

            isBinned = ndims(eeg.data) == 3 && isfield(eeg, 'bindesc') && ~isempty(eeg.bindesc);
            if isBinned
                nBinsTotal = size(eeg.data, 3);
                labels = {eeg.bindesc.label};
            else
                nBinsTotal = 1;
                labels = {char(string(eeg.id))};
            end

            selected = TransTools.TickedScalpBins(fig, eeg, nBinsTotal);
            this.BinIndices = find(selected);
            binLabels = labels(this.BinIndices);
            this.SelectedBin = 1;

            hasDropdown = numel(this.BinIndices) > 1;
            dropdownRows = double(hasDropdown); % 0 or 1 extra row below the (always-present) mode row

            % Rows: [the mode dropdown, optional bin dropdown, the 3D axes,
            % the "t = ... ms" readout, the Play+slider strip]. Columns:
            % the axes itself, plus one narrow trailing column for the
            % shared colorbar -- same reasoning as ScalpDistributionView's
            % own colorbarAxes: attaching a colorbar directly to a real
            % axes with axis() 'equal' shrinks/distorts it to make room.
            this.Grid = uigridlayout(fig, [dropdownRows + 4, 2], ...
                "RowHeight", [{26}, repmat({26}, 1, dropdownRows), {'1x'}, {22}, {36}], ...
                "ColumnWidth", {'1x', TransTools.ColorbarColumnWidth()}, "Padding", [4 4 4 4]);

            modeRow = uigridlayout(this.Grid, [1, 3], ...
                "ColumnWidth", {70, '1x', 172}, "Padding", [0 0 0 0], "ColumnSpacing", 4);
            modeRow.Layout.Row = 1;
            modeRow.Layout.Column = 1;
            uilabel(modeRow, "Text", "Projection:", "HorizontalAlignment", "right");
            this.ModeDropdown = uidropdown(modeRow, ...
                "Items", ["Scalp topography", "Source estimate (dSPM)", ...
                          "Source estimate (eLORETA)", "Source estimate (sLORETA)"], ...
                "ItemsData", ["scalp", "mne", "eloreta", "sloreta"], "Value", "scalp", ...
                "Tooltip", Brain3DView.BaseTooltip, ...
                "ValueChangedFcn", @(dd, ~) this.onModeChanged(dd.Value));

            % Orientation is a property of the estimate, not a fourth
            % method, so it is a checkbox beside the methods rather than
            % three more dropdown entries (which would have made seven).
            % Disabled in scalp mode, where it means nothing.
            this.SignedCheckbox = uicheckbox(modeRow, ...
                "Text", "Signed (cortical normal)", "Value", false, "Enable", "off", ...
                "Tooltip", ['Project each vertex''s dipole onto the cortical normal, keeping ' ...
                    'the SIGN, instead of taking its magnitude. Pyramidal cells sit ' ...
                    'perpendicular to the cortical sheet, so the normal is the physically ' ...
                    'motivated direction -- and a magnitude cannot show an ERP''s polarity ' ...
                    'at all. Drawn on a diverging scale symmetric about zero. This is the ' ...
                    'same quantity region time courses are measured from.'], ...
                "ValueChangedFcn", @(cb, ~) this.onSignedChanged(cb.Value));

            axRow = dropdownRows + 2;
            this.AxRow = axRow;
            this.Axes = uiaxes(this.Grid);
            this.Axes.Layout.Row = axRow;
            this.Axes.Layout.Column = 1;
            this.Axes.ButtonDownFcn = @(~, ~) this.notifyActivated();
            axtoolbar(this.Axes, "default");
            % Explicitly make a plain click-and-drag orbit the head, rather
            % than relying on uiaxes' own "3-D content defaults to rotate"
            % heuristic: that heuristic is decided from the axes' content at
            % the time it is evaluated, and this axes starts out empty
            % (2-D) -- it only gets its 3-D patch/view a moment later, in
            % the first redraw() call below -- so leaving it to the
            % heuristic risked the default drag gesture never switching
            % away from 2-D pan. Setting Interactions here removes that
            % risk outright. axtoolbar's own zoom/pan/restore-view/datatip
            % buttons are unaffected and stay available as alternate modes;
            % this only changes the no-button-pressed default.
            this.Axes.Interactions = rotateInteraction;

            this.Strip = TimeScrubStrip(this.Grid, 2, axRow + 1, axRow + 2, ...
                binLabels, eeg.times, @() this.notifyActivated(), ...
                @(t) this.redraw(t), @(idx) this.onBinChanged(idx));
            this.redraw(this.Strip.Slider.Value);

            % One shared colorbar, in its own reserved column -- see
            % TransTools.AddSharedColorbar for why not attached directly to
            % Axes, and for why its handle is kept (rebuildColorbar swaps
            % its scale/label between the two Projection modes). Built
            % AFTER the first redraw() above, not before: reverted back to
            % this order after a real, reported regression (the colorbar
            % rendering noticeably smaller) when it was briefly moved
            % before redraw() for cross-file ordering consistency -- a
            % hidden axes created before anything else in the tab forces a
            % layout pass appears to get sized against a stale/placeholder
            % container, the same kind of "not yet actually placed" quirk
            % AlakazamPlotter.m's own comment documents for a freshly
            % constructed uiaxes' reported pixel width. Not fully root-
            % caused (no live MATLAB session to confirm the exact
            % mechanism) -- if this regresses again, suspect this ordering
            % first.
            this.ColorbarAxes = TransTools.AddSharedColorbar(this.Grid, axRow, 2, ...
                TransTools.DivergingColormap(), [-eeg.ScalpMapLimit, eeg.ScalpMapLimit], "Amplitude (\muV)");
        end

        function redraw(this, t)
        %REDRAW  Show the currently selected bin's brain projection at the
        %   instant nearest T (ms), in whichever Projection mode is
        %   current. Called directly by the constructor and by
        %   TimeScrubStrip's own callbacks (slider drag/release, Play, a
        %   bin switch).
            eeg = this.EEG;
            [~, idx] = min(abs(eeg.times - t));
            this.Strip.TimeLabel.Text = sprintf('t = %.0f ms', eeg.times(idx));
            if Brain3DView.isSourceMode(this.Mode)
                this.BrainPatch = TransTools.DrawSourceMap(this.Axes, this.SourcePower(:, idx), ...
                    this.SourceModel, this.SourceMapLimit, this.BrainPatch, this.Signed);
                % Set on every redraw rather than once per estimate: title()
                % on a uiaxes is cheap, and this keeps the title correct
                % without having to reason about whether DrawBrainPatch's own
                % cla() (rebuild path only, see its header) would otherwise
                % clear it -- the same "just set it every time" choice
                % TimeLabel.Text above already makes.
                title(this.Axes, this.fitVarianceLabel());
            else
                values = eeg.data(eeg.ScalpHasPos, idx, this.BinIndices(this.SelectedBin));
                this.BrainPatch = TransTools.DrawBrainMap(this.Axes, values, eeg.ScalpChanlocs, ...
                    eeg.ScalpMapLimit, this.Mesh, this.BrainPatch);
                title(this.Axes, ''); % nothing to report for a plain scalp projection
            end
        end

        function onWheel(this, callbackData)
        %ONWHEEL  Public: dispatched centrally by Alakazam.dispatchWheel
        %   for whichever tab is currently active; forwarded straight to
        %   TimeScrubStrip's own onWheel (mouse wheel scrubs the slider),
        %   same convention as ScalpDistributionView's own onWheel.
            this.Strip.onWheel(callbackData);
        end

    end

    methods (Access = private)
        function label = binLabelFor(this, selected)
        %BINLABELFOR  The bin name a stored estimate would be filed under.
        %   SourceEstimate keys its bins by label, not by index, because an
        %   index means nothing once a dataset has been reordered or a bin
        %   dropped. Returns '' when this dataset has no bin descriptions,
        %   which simply means nothing can be matched.
            label = '';
            eeg = this.EEG;
            if ~isfield(eeg, 'bindesc') || isempty(eeg.bindesc)
                return;
            end
            index = this.BinIndices(selected);
            if index <= numel(eeg.bindesc)
                label = eeg.bindesc(index).label;
            end
        end

        function key = storedEstimateKey(this, method, signed)
        %STOREDESTIMATEKEY  What this view would need a stored estimate to be.
        %
        %   The window and rate are deliberately EMPTY. This view scrubs the
        %   whole epoch at its own sample rate, so only an estimate stored
        %   over all of it can serve; one windowed for a cluster test is a
        %   different fit, and asking for it here would be asking for the
        %   wrong thing rather than for less of the right thing.
        %
        %   RegParam is TransTools.InverseSolution's own default because this
        %   view does not expose regularisation. If it ever does, this has to
        %   follow, or the view would silently accept estimates made at a
        %   different one.
            if signed
                orientation = 'normal';
            else
                orientation = 'magnitude';
            end
            % THE RESOLVED LABELS, not the dataset's own. The stored
            % estimate's key records the channels BuildSourceForwardModel
            % actually resolved against the 10-5 template, which is a subset
            % in a different order from what the dataset offered. Building
            % this key from the dataset's labels instead meant it could
            % never match anything, and the reuse path was simply dead.
            key = SourceCache.Key(this.SourceResolvedLabels, struct( ...
                'SourceSpace', size(this.SourceModel.pos, 1), ...
                'Method',      method, ...
                'Orientation', orientation, ...
                'RegParam',    0.05, ...
                'TimeWindow',  [], ...
                'ResampleHz',  []));
        end

        function onBinChanged(this, binIdx)
        %ONBINCHANGED  TimeScrubStrip's OnBinChangedFcn hook: switch the
        %   displayed bin (redraw() itself is called by TimeScrubStrip
        %   right after this returns). No title to update here, unlike
        %   ScalpDistributionView's own hook -- the mesh has none.
        %   Source-estimate mode needs recomputing for the new bin (see
        %   ensureSourceReady); if that fails, falls back to Scalp mode
        %   (via switchToMode, same as onModeChanged's own switch -- see
        %   its header comment for why that matters here too: without it,
        %   this fallback used to silently reset the camera to the
        %   default view, unlike a dropdown-triggered fallback) with a
        %   friendly alert rather than leaving Source mode showing a stale
        %   bin's data under the new bin's label.
            this.SelectedBin = binIdx;
            if Brain3DView.isSourceMode(this.Mode)
                try
                    this.ensureSourceReady();
                catch err
                    uialert(ancestor(this.Axes, "figure"), err.message, ...
                        "Could not compute the source estimate for this bin");
                    this.ModeDropdown.Value = "scalp";
                    this.switchToMode("scalp");
                end
            end
        end

        function onModeChanged(this, mode)
        %ONMODECHANGED  ModeDropdown ValueChangedFcn target. Switching TO
        %   Source-estimate mode may need to fetch FieldTrip (consent
        %   dialog, see TransTools.ensureFieldTrip) and/or compute a fresh
        %   leadfield/inverse for this dataset's channel set and the
        %   current bin -- both handled by ensureSourceReady, which can
        %   throw (declined install, a computation error, ...); on
        %   failure this reverts the dropdown to Scalp mode with a
        %   friendly alert instead of leaving the view in a half-switched
        %   state. Only reverts the DROPDOWN here, not the view/state --
        %   this.Mode was never actually changed yet at this point, so
        %   there is nothing to switchToMode() back out of.
            this.notifyActivated();
            if Brain3DView.isSourceMode(mode)
                try
                    this.ensureSourceReady(mode); % MODE, not this.Mode -- see ensureSourceReady
                catch err
                    uialert(ancestor(this.Axes, "figure"), err.message, ...
                        "Could not enable the source estimate");
                    this.ModeDropdown.Value = "scalp";
                    return;
                end
            end
            this.SignedCheckbox.Enable = Brain3DView.isSourceMode(mode);
            this.switchToMode(mode);
        end

        function onSignedChanged(this, signed)
        %ONSIGNEDCHANGED  SignedCheckbox ValueChangedFcn target. Same
        %   revert-on-failure shape as onModeChanged, and for the same
        %   reason: this recomputes the inverse (a signed estimate is
        %   different numbers, not a different rendering of the same ones),
        %   so it can fail, and a half-switched view would show one
        %   orientation's data under the other's colorbar.
        %
        %   Reverts only the CHECKBOX on failure -- this.Signed has not been
        %   committed yet at that point, so there is nothing to undo.
            this.notifyActivated();
            if ~Brain3DView.isSourceMode(this.Mode)
                return; % nothing to project in scalp mode
            end

            try
                this.ensureSourceReady(this.Mode, signed); % SIGNED, not this.Signed
            catch err
                uialert(ancestor(this.Axes, "figure"), err.message, ...
                    "Could not change the source orientation");
                this.SignedCheckbox.Value = this.Signed;
                return;
            end

            % Same camera-preserving full rebuild switchToMode does, and for
            % a reason worth stating: the MESH is unchanged here, so the
            % in-place FaceVertexCData fast path would happily run -- but
            % DrawBrainPatch only calls colormap() when it CREATES the patch
            % (CLim it sets every time). Updating in place would therefore
            % apply the signed symmetric range to the sequential parula
            % colormap, which reads as a picture rather than an error.
            [az, el] = view(this.Axes);
            this.Signed = signed;
            this.BrainPatch = [];
            this.rebuildColorbar();
            this.redraw(this.Strip.Slider.Value);
            view(this.Axes, [az, el]);
        end

        function switchToMode(this, mode)
        %SWITCHTOMODE  Actually commit to MODE and redraw: rebuild the
        %   patch/colorbar and redraw, preserving whatever camera rotation
        %   the user left the head at. Shared by onModeChanged's own
        %   successful switch and onBinChanged's own revert-to-Scalp-mode
        %   fallback -- both are "commit to a new Mode and redraw", and
        %   both need the same camera-preserving rebuild: a mode switch
        %   always rebuilds BrainPatch from scratch (the two modes' meshes
        %   have different vertex/face counts, so an in-place
        %   FaceVertexCData update -- the normal fast path -- cannot work
        %   across them), and DrawBrainMap/DrawSourceMap each reset the
        %   camera to their own fixed starting view whenever they rebuild.
        %   Capturing the view here before that happens, and restoring it
        %   after, is a UI-state concern that belongs at this level, not
        %   inside the drawing functions themselves (which have no reason
        %   to know a rebuild was actually just a mode switch rather than
        %   a first draw).
            [az, el] = view(this.Axes);
            this.Mode = mode;
            this.BrainPatch = []; % different mesh/geometry between modes -- force a full rebuild, not an update-in-place
            this.rebuildColorbar();
            this.redraw(this.Strip.Slider.Value);
            view(this.Axes, [az, el]); % restore, undoing the fresh patch's own default starting view
        end

        function ensureSourceReady(this, method, signed)
        %ENSURESOURCEREADY  Make sure SourceLeadfield/SourceModel (built
        %   once per channel set) and SourcePower (recomputed whenever
        %   SelectedBin or METHOD changes) are ready for the CURRENT bin.
        %
        %   METHOD defaults to this.Mode, but onModeChanged MUST pass the
        %   incoming mode explicitly: it calls this BEFORE committing the
        %   switch (so that a failure can revert cleanly without leaving a
        %   half-switched view), and at that moment this.Mode is still the
        %   OLD method. Reading this.Mode here would then compute the
        %   previous method's estimate and label it as the new one. Shows a
        %   modal busy indicator while computing (see beginBusy) -- both
        %   steps can take a real moment (leadfield: several thousand
        %   cortical points x N electrodes; the inverse itself is a fast
        %   matrix multiply once the leadfield exists, see
        %   TransTools.InverseSolution).
        %
        %   The leadfield is shared by all three inverse methods -- it is a
        %   property of the head and the electrodes, not of the method -- so
        %   switching method never rebuilds it, only re-solves.
            if nargin < 2 || isempty(method)
                method = this.Mode;
            end
            if nargin < 3
                signed = this.Signed;
            end
            eeg = this.EEG;
            scalpLabels = {eeg.ScalpChanlocs.labels};

            % Method as well as bin: the cached SourcePower belongs to the
            % method that produced it, and the three are on different scales,
            % so reusing one under another's colorbar would mislabel it.
            % METHOD, not this.Mode -- see this function's own header.
            % THE MESH FOLLOWS THE STORED ESTIMATE WHEN THERE IS ONE.
            % A stored estimate is a vector over ITS OWN vertices, so it can
            % only be drawn on the sheet it was computed for; demanding the
            % full-resolution one would refuse every estimate stored at a
            % coarser mesh, which is the size most analysts can afford. So
            % this view adopts the stored sheet instead, and rebuilds its
            % model when that differs from the one it is holding.
            %
            % The consequence is visible and deliberate: the surface really
            % is coarser, so the scale note says which sheet is being drawn
            % rather than letting a smoother-looking render pass for the
            % full one.
            space = SourceCache.Space(eeg, 20484);
            needsModel = isempty(this.SourceModel) || ...
                size(this.SourceModel.pos, 1) ~= space;
            needsSolve = ~(isequal(this.SourcePowerBin, this.SelectedBin) && ...
                           isequal(this.SourcePowerMethod, method) && ...
                           isequal(this.SourcePowerSigned, signed));
            if ~needsModel && ~needsSolve
                return; % already computed for this bin, with this method
            end

            % THE BUSY INDICATOR STARTS BEFORE THE LEADFIELD, not after it.
            % Building the forward model is the slow step by a wide margin
            % (several thousand cortical points x N electrodes, tens of
            % seconds upwards); the inverse that follows is a matrix
            % multiply. Started afterwards, the spinner appeared only for the
            % fast half and the app looked frozen through the slow one --
            % which is the exact case beginBusy's own two-phase updateFcn
            % exists for.
            % Both are onCleanup handles whose whole job is to stay alive
            % until this function returns, so neither is "unused" and
            % neither can become a ~: dropping restoreBusy would tear the
            % busy overlay down immediately.
            fig = ancestor(this.Axes, "figure");
            if needsModel
                [restoreBusy, setBusy] = beginBusy(fig, "Building the head model..."); %#ok<ASGLU>
            else
                restoreBusy = beginBusy(fig, "Computing source estimate..."); %#ok<NASGU>
            end

            if needsModel
                [this.SourceLeadfield, this.SourceModel, this.SourceResolvedLabels, ...
                    this.SourceElec, this.SourceHeadmodel] = ...
                    TransTools.BuildSourceForwardModel(scalpLabels, space);
                % The normals belong to the sheet, so a new sheet invalidates
                % them; keeping the old ones would project onto the wrong
                % geometry without any error.
                this.SourceNormals = [];
                setBusy("Computing source estimate...");
            end

            if ~needsSolve
                return; % the model was missing, but this bin/method is already solved
            end

            % A STORED ESTIMATE IS USED WHEN THERE IS AN EXACTLY MATCHING
            % ONE, and only then. The SourceEstimate transformation may have
            % inverted this dataset already; SourceCache.Lookup
            % checks both that the settings agree and that the data is still
            % the data the estimate was computed from, and returns nothing on
            % any doubt. The residual variance and scale labels come back
            % with it, since those are displayed and recomputing an inverse
            % to recover two strings would defeat the point.
            %
            % In practice this matches only when the estimate was stored over
            % the WHOLE epoch at full rate, because that is what this view
            % scrubs through. A stored estimate windowed for a cluster test
            % is a different fit and is correctly refused, so the two uses do
            % not share a node unless the analyst asked for the wide one.
            %
            % Asked BEFORE the data is reordered and the surface normals are
            % built: both are pure setup for an inverse that may not need to
            % happen, and the normals in particular are not free.
            [stored, storedInfo] = SourceCache.Lookup(eeg, ...
                this.binLabelFor(this.SelectedBin), this.storedEstimateKey(method, signed));

            if ~isempty(stored)
                this.SourcePower = stored;
                info = struct( ...
                    'ScaleLabel',       TransTools.FieldOr(storedInfo, 'scaleLabel', ''), ...
                    'ScaleNote',        TransTools.FieldOr(storedInfo, 'scaleNote', ''), ...
                    'ResidualVariance', TransTools.FieldOr(storedInfo, 'residualVariance', NaN));
            else
                % Reorder this bin's channel-by-time data to
                % SourceResolvedLabels' own order -- REQUIRED, not optional,
                % see TransTools.BuildSourceForwardModel's own header.
                [tf, reorder] = ismember(lower(this.SourceResolvedLabels), lower(scalpLabels));
                if ~all(tf)
                    throw(MException("Alakazam:Brain3DView", ...
                        ["Something appears to have gone wrong internally, I'm afraid: a resolved " ...
                         "source-model channel is missing from this dataset's own positioned channels."]));
                end
                scalpData = eeg.data(eeg.ScalpHasPos, :, this.BinIndices(this.SelectedBin));
                values = scalpData(reorder, :);

                solveOpts = struct();
                if signed
                    if isempty(this.SourceNormals)
                        % Pure geometry, so once per source model rather than
                        % per bin: the template sheet never changes.
                        this.SourceNormals = TransTools.SurfaceNormals(this.SourceModel);
                    end
                    solveOpts.Orientation = 'normal';
                    solveOpts.Normals     = this.SourceNormals;
                end

                [this.SourcePower, info] = TransTools.InverseSolution(values, this.SourceLeadfield, ...
                    this.SourceElec, this.SourceHeadmodel, method, solveOpts);
            end
            this.SourcePowerBin    = this.SelectedBin;
            this.SourcePowerMethod = method;
            this.SourcePowerSigned = signed;
            this.SourceScaleLabel  = info.ScaleLabel;
            this.SourceScaleNote   = info.ScaleNote;
            this.SourceResidualVariance = info.ResidualVariance;
            % Named on the scale note because a coarser sheet is a real
            % difference in what is being shown, not an implementation
            % detail: 5124 vertices renders visibly smoother than 20484 and
            % would otherwise be indistinguishable from a better estimate.
            this.SourceScaleNote = sprintf('%s Drawn on the %d-vertex template sheet.', ...
                this.SourceScaleNote, size(this.SourceModel.pos, 1));

            if signed
                this.SourceScaleLabel = [info.ScaleLabel ', signed'];
                this.SourceScaleNote  = [info.ScaleNote ' Projected onto the cortical normal, ' ...
                    'so the sign is meaningful and the scale is symmetric about zero.'];
            end
            this.ModeDropdown.Tooltip = [Brain3DView.BaseTooltip() ' ' this.SourceScaleNote];

            % Signed values straddle zero, so the shared scale has to be
            % symmetric about it or the colours would misrepresent polarity.
            this.SourceMapLimit = max(abs(this.SourcePower(:)), [], "omitnan");
            if ~isfinite(this.SourceMapLimit) || this.SourceMapLimit == 0
                this.SourceMapLimit = 1;
            end
        end

        function s = fitVarianceLabel(this)
        %FITVARIANCELABEL  A one-line readout of how much of the scalp
        %   data the CURRENT source estimate reproduces when projected
        %   back through the leadfield it came from -- shown as the axes
        %   title in Source-estimate mode (see redraw()).
        %
        %   Backed by TransTools.InverseSolution's own INFO.ResidualVariance
        %   (see its computation's own comment for exactly what this is a
        %   check on -- the forward model/registration, not anatomical
        %   accuracy). Reported as "variance explained" (1 - RV) rather
        %   than RV itself, since a higher number reading as "better" needs
        %   no separate legend the way a residual would.
        %
        %   Independent of this.Signed on purpose: ResidualVariance is
        %   computed from the raw current estimate BEFORE the
        %   magnitude/normal orientation collapse, so it does not change
        %   when the Signed checkbox is toggled, only when the bin or
        %   method does.
        %
        %   EMPTY FOR sLORETA, which reports no residual variance at all
        %   (NaN): its filter yields a standardized statistic rather than a
        %   current, so there is nothing to project back through the
        %   leadfield. No title is better than a title reading "Fit: NaN%",
        %   or worse, the -4403% a real recording produced when this was
        %   computed for it regardless.
            if isnan(this.SourceResidualVariance)
                s = '';
                return;
            end
            s = sprintf('Fit: %.0f%% variance explained', 100 * (1 - this.SourceResidualVariance));
        end

        function rebuildColorbar(this)
        %REBUILDCOLORBAR  Delete and rebuild ColorbarAxes for the current
        %   Mode's own scale/label -- see AddSharedColorbar's own header
        %   comment for why an existing colorbar cannot just have its
        %   scale/label swapped in place.
            delete(this.ColorbarAxes);
            if Brain3DView.isSourceMode(this.Mode)
                % The label travels with the estimate rather than being
                % hard-coded here: the three methods are on genuinely
                % different scales, and a colorbar reading "dSPM" over an
                % eLORETA map would be the exact confusion the tooltip warns
                % about. See TransTools.InverseSolution's own INFO.
                if this.Signed
                    this.ColorbarAxes = TransTools.AddSharedColorbar(this.Grid, this.AxRow, 2, ...
                        TransTools.DivergingColormap(), ...
                        [-this.SourceMapLimit, this.SourceMapLimit], this.SourceScaleLabel);
                else
                    this.ColorbarAxes = TransTools.AddSharedColorbar(this.Grid, this.AxRow, 2, ...
                        parula, [0, this.SourceMapLimit], this.SourceScaleLabel);
                end
            else
                this.ColorbarAxes = TransTools.AddSharedColorbar(this.Grid, this.AxRow, 2, ...
                    TransTools.DivergingColormap(), [-this.EEG.ScalpMapLimit, this.EEG.ScalpMapLimit], ...
                    "Amplitude (\muV)");
            end
        end
    end

    methods (Static, Access = private)
        function s = BaseTooltip()
        %BASETOOLTIP  The caveat that applies to every inverse mode. The
        %   ACTIVE method's own scale note is appended to this whenever an
        %   estimate is computed (see ensureSourceReady), so the tooltip
        %   always describes the scale actually on screen rather than
        %   listing all three and leaving the reader to work out which.
            s = ['Every source estimate uses FieldTrip''s TEMPLATE head model and ' ...
                 'electrode positions (no per-subject MRI/digitised cap) -- a real ' ...
                 'inverse computation, but still an approximation, not a validated ' ...
                 'per-subject localization. The three methods are on DIFFERENT SCALES ' ...
                 'and none of them is microvolts, so their numbers are not comparable ' ...
                 'to each other or to Scalp topography''s own scale.'];
        end

        function tf = isSourceMode(mode)
        %ISSOURCEMODE  Whether MODE is one of the inverse methods rather
        %   than the scalp projection.
        %
        %   A named test rather than strcmp(mode, "source") repeated at
        %   four sites: when the single "source" mode became three named
        %   methods, every one of those comparisons would have silently
        %   gone false, leaving the view drawing a scalp map while the
        %   dropdown said eLORETA. One place to be wrong is better than
        %   four places to forget.
            tf = any(strcmp(mode, ["mne", "eloreta", "sloreta"]));
        end
    end
end

