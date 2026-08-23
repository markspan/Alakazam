classdef Brain3DView < handle
%BRAIN3DVIEW  A rotatable 3D brain surface, coloured by an averaged ERP,
%   scrubbable by time, in either of two Projection modes:
%     "Scalp topography" (default) -- the scalp-measured amplitude,
%       spherically interpolated onto a BrainNet Viewer brain surface for
%       legibility; not source-localized in any way. See DrawBrainMap.
%     "Source estimate (MNE)" -- a real, noise-normalized (dSPM-style)
%       Tikhonov-regularized minimum-norm inverse, computed with
%       FieldTrip's own template BEM head model and a template
%       cortical-sheet source model, drawn directly onto that cortical
%       sheet. See TransTools.BuildSourceForwardModel/
%       ComputeSourceEstimate/DrawSourceMap. IMPORTANT CAVEAT, also shown
%       in the mode dropdown's own tooltip: this uses a TEMPLATE head
%       model and TEMPLATE electrode positions, not a per-subject MRI or
%       digitised cap -- it is a genuine inverse computation, more
%       physiologically grounded than the scalp-topography mode, but is
%       still an approximation, not a validated per-subject localization.
%       Its colour scale is a noise-normalized statistic (see
%       ComputeSourceEstimate's own header for the dSPM formula), not a
%       physical unit -- not comparable to scalp mode's signed microvolts,
%       by design, not a rendering bug (this comes up often enough to
%       repeat here as well as in the mode tooltip and README).
%       Needs FieldTrip (a ~400 MB one-time download, consent-gated -- see
%       TransTools.ensureFieldTrip), fetched lazily the first time this
%       mode is selected. Switching into it the first time (or onto a
%       bin not yet computed) is noticeably slower than scalp mode --
%       leadfield/inverse computation, not just a redraw -- shown with a
%       modal busy indicator (see ensureSourceReady/beginBusy).
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
%   TRANSTOOLS.BUILDSOURCEFORWARDMODEL, TRANSTOOLS.COMPUTESOURCEESTIMATE,
%   TRANSTOOLS.DRAWSOURCEMAP, TRANSTOOLS.ENSUREFIELDTRIP.

    properties
        % Called (no args) when the user clicks the head, the bin dropdown
        % or the slider. Wired by AlakazamPlotter to
        % Alakazam.registerTileClick -- see ScalpDistributionView's own
        % ActivatedFcn for why.
        ActivatedFcn = function_handle.empty
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
        Mode = "scalp"  % "scalp" or "source" -- see the class header comment
        ModeDropdown    % uidropdown choosing Mode
    end

    properties (Access = private)
        AxRow           % row index of Axes/the colorbar in Grid, needed again when rebuildColorbar reruns after a Mode switch
        ColorbarAxes    % the centring sub-grid TransTools.AddSharedColorbar built (its own name notwithstanding), deleted/rebuilt on a Mode switch (different scale/label per mode)
        SourceLeadfield     % TransTools.BuildSourceForwardModel's own leadfield (session-cached there already; kept here to avoid re-resolving labels every bin)
        SourceModel         % TransTools.BuildSourceForwardModel's own cortical-sheet struct (.pos/.tri) -- Source-estimate mode's mesh
        SourceResolvedLabels % channel order SourceLeadfield's rows actually correspond to -- see BuildSourceForwardModel's own header comment
        SourcePower         % nVertex x nTime source estimate, for whichever bin SourcePowerBin says
        SourcePowerBin      % which SelectedBin SourcePower was last computed for, or [] if none yet
        SourceMapLimit      % shared [0, max] colour scale for the bin SourcePower holds
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

            modeRow = uigridlayout(this.Grid, [1, 2], ...
                "ColumnWidth", {70, '1x'}, "Padding", [0 0 0 0], "ColumnSpacing", 4);
            modeRow.Layout.Row = 1;
            modeRow.Layout.Column = 1;
            uilabel(modeRow, "Text", "Projection:", "HorizontalAlignment", "right");
            this.ModeDropdown = uidropdown(modeRow, ...
                "Items", ["Scalp topography", "Source estimate (MNE)"], ...
                "ItemsData", ["scalp", "source"], "Value", "scalp", ...
                "Tooltip", ['Source estimate uses FieldTrip''s TEMPLATE head model and ' ...
                    'electrode positions (no per-subject MRI/digitised cap) -- a real ' ...
                    'inverse computation, but still an approximation, not a validated ' ...
                    'per-subject localization. Its colour scale (dSPM, noise-normalized) ' ...
                    'is a statistic, not microvolts -- not comparable to Scalp topography''s ' ...
                    'own scale.'], ...
                "ValueChangedFcn", @(dd, ~) this.onModeChanged(dd.Value));

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
            if strcmp(this.Mode, "source")
                this.BrainPatch = TransTools.DrawSourceMap(this.Axes, this.SourcePower(:, idx), ...
                    this.SourceModel, this.SourceMapLimit, this.BrainPatch);
            else
                values = eeg.data(eeg.ScalpHasPos, idx, this.BinIndices(this.SelectedBin));
                this.BrainPatch = TransTools.DrawBrainMap(this.Axes, values, eeg.ScalpChanlocs, ...
                    eeg.ScalpMapLimit, this.Mesh, this.BrainPatch);
            end
        end

        function onWheel(this, callbackData)
        %ONWHEEL  Public: dispatched centrally by Alakazam.dispatchWheel
        %   for whichever tab is currently active; forwarded straight to
        %   TimeScrubStrip's own onWheel (mouse wheel scrubs the slider),
        %   same convention as ScalpDistributionView's own onWheel.
            this.Strip.onWheel(callbackData);
        end

        function notifyActivated(this)
        %NOTIFYACTIVATED  Call ActivatedFcn, if set, guarding the usual
        %   empty-function_handle case.
            if ~isempty(this.ActivatedFcn)
                this.ActivatedFcn();
            end
        end
    end

    methods (Access = private)
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
            if strcmp(this.Mode, "source")
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
            if strcmp(mode, "source")
                try
                    this.ensureSourceReady();
                catch err
                    uialert(ancestor(this.Axes, "figure"), err.message, ...
                        "Could not enable the source estimate");
                    this.ModeDropdown.Value = "scalp";
                    return;
                end
            end
            this.switchToMode(mode);
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

        function ensureSourceReady(this)
        %ENSURESOURCEREADY  Make sure SourceLeadfield/SourceModel (built
        %   once per channel set) and SourcePower (recomputed whenever
        %   SelectedBin changes) are ready for the CURRENT bin. Shows a
        %   modal busy indicator while computing (see beginBusy) -- both
        %   steps can take a real moment (leadfield: several thousand
        %   cortical points x N electrodes; the inverse itself is a fast
        %   matrix multiply once the leadfield exists, see
        %   TransTools.ComputeSourceEstimate).
            eeg = this.EEG;
            scalpLabels = {eeg.ScalpChanlocs.labels};

            if isempty(this.SourceModel)
                [this.SourceLeadfield, this.SourceModel, this.SourceResolvedLabels] = ...
                    TransTools.BuildSourceForwardModel(scalpLabels);
            end

            if isequal(this.SourcePowerBin, this.SelectedBin)
                return; % already computed for this bin
            end

            fig = ancestor(this.Axes, "figure");
            restoreBusy = beginBusy(fig, "Computing source estimate...");

            % Reorder this bin's channel-by-time data to SourceResolvedLabels'
            % own order -- REQUIRED, not optional, see
            % TransTools.BuildSourceForwardModel's own header comment.
            [tf, reorder] = ismember(lower(this.SourceResolvedLabels), lower(scalpLabels));
            if ~all(tf)
                throw(MException("Alakazam:Brain3DView", ...
                    ["Something appears to have gone wrong internally, I'm afraid: a resolved " ...
                     "source-model channel is missing from this dataset's own positioned channels."]));
            end
            scalpData = eeg.data(eeg.ScalpHasPos, :, this.BinIndices(this.SelectedBin)); % nScalpChan x nTime
            values = scalpData(reorder, :);

            this.SourcePower = TransTools.ComputeSourceEstimate(values, this.SourceLeadfield);
            this.SourcePowerBin = this.SelectedBin;
            this.SourceMapLimit = max(this.SourcePower(:), [], "omitnan");
            if ~isfinite(this.SourceMapLimit) || this.SourceMapLimit == 0
                this.SourceMapLimit = 1;
            end
        end

        function rebuildColorbar(this)
        %REBUILDCOLORBAR  Delete and rebuild ColorbarAxes for the current
        %   Mode's own scale/label -- see AddSharedColorbar's own header
        %   comment for why an existing colorbar cannot just have its
        %   scale/label swapped in place.
            delete(this.ColorbarAxes);
            if strcmp(this.Mode, "source")
                this.ColorbarAxes = TransTools.AddSharedColorbar(this.Grid, this.AxRow, 2, ...
                    parula, [0, this.SourceMapLimit], "dSPM (noise-normalized)");
            else
                this.ColorbarAxes = TransTools.AddSharedColorbar(this.Grid, this.AxRow, 2, ...
                    TransTools.DivergingColormap(), [-this.EEG.ScalpMapLimit, this.EEG.ScalpMapLimit], ...
                    "Amplitude (\muV)");
            end
        end
    end
end
