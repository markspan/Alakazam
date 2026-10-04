classdef DipoleView < AlakazamView
%DIPOLEVIEW  The dipoles Dipole Fit placed: on a see-through template brain,
%   with a table of their positions, regions and residual variance.
%
%   Each dipole is a dot at its position with an arrow along its moment at
%   the instant of the window where the moment is largest, drawn in the
%   template brain the source estimates use (BrainNet Viewer's ICBM152
%   mesh, in MNI millimetres). A bin dropdown switches between the bins
%   that were fitted. The table gives the numbers: position, the AAL region
%   at or near it, and the residual variance of the fit over its window,
%   which is the figure that says how far to trust the picture.
%
%   See also DIPOLEFIT, ALAKAZAMPLOTTER, BRAIN3DVIEW.

    properties (SetAccess = private)
        Figure
        EEG
        Grid
        Axes
        Table           % the numbers of the shown bin's dipoles
        BinLabels       % the bins that were fitted, in EEG.dipoleFit's order
        SelectedBin = 1
        BinDropdown
    end

    properties (Constant)
        DipoleColours = [0.753 0.255 0.247; 0.290 0.498 0.788]   % red, then blue
        ArrowLength = 22                                            % mm
    end

    methods
        function this = DipoleView(fig, eeg)
            this.Figure = fig;
            this.EEG    = eeg;
            this.BinLabels = {eeg.dipoleFit.bin};

            hasDropdown = numel(this.BinLabels) > 1;
            dropdownRows = double(hasDropdown);
            this.Grid = uigridlayout(fig, [dropdownRows + 2, 1], ...
                "RowHeight", [repmat({26}, 1, dropdownRows), {'1x'}, {110}], "Padding", [4 4 4 4]);
            if hasDropdown
                this.BinDropdown = TransTools.BuildBinDropdown(this.Grid, 1, 1, ...
                    this.BinLabels, @(idx) this.onBinChanged(idx));
            end

            this.Axes = uiaxes(this.Grid);
            this.Axes.Layout.Row = dropdownRows + 1;
            this.Axes.ButtonDownFcn = @(~, ~) this.notifyActivated();
            axtoolbar(this.Axes, "default");
            this.Axes.Interactions = rotateInteraction;

            this.Table = uitable(this.Grid, 'RowName', {}, ...
                'ColumnName', {'Dipole', 'x (mm)', 'y (mm)', 'z (mm)', 'Region (AAL)', 'Residual variance'}, ...
                'ColumnWidth', {60, 70, 70, 70, 'auto', 130});
            this.Table.Layout.Row = dropdownRows + 2;

            this.drawBrain();
            this.redraw();
        end
    end

    methods (Access = private)
        function drawBrain(this)
        %DRAWBRAIN  The template brain, once: see-through, so that a deep
        %   dipole is not hidden behind the cortex in front of it.
            meshFile = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'Meshes', ...
                'BrainMesh_ICBM152.nv');
            mesh = TransTools.ReadBrainMeshNV(meshFile);
            ax = this.Axes;
            patch(ax, 'Vertices', mesh.Vertices, 'Faces', mesh.Faces, 'FaceColor', [0.82 0.82 0.82], ...
                'EdgeColor', 'none', 'FaceAlpha', 0.12, 'Tag', 'brain', 'HitTest', 'off');
            axis(ax, 'equal', 'off');
            view(ax, [-90 20]);   % from the left
            camlight(ax, 'headlight');
            hold(ax, 'on');
        end

        function redraw(this)
            ax = this.Axes;
            delete(findobj(ax, 'Tag', 'dipole'));
            fit = this.EEG.dipoleFit(this.SelectedBin);
            orientations = momentAtPeak(fit.mom, size(fit.pos, 1));
            rows = cell(size(fit.pos, 1), 6);
            for k = 1:size(fit.pos, 1)
                colour = this.DipoleColours(min(k, end), :);
                p = fit.pos(k, :);
                plot3(ax, p(1), p(2), p(3), 'o', 'MarkerSize', 9, 'MarkerFaceColor', colour, ...
                    'MarkerEdgeColor', 'k', 'Tag', 'dipole');
                d = orientations(k, :) * this.ArrowLength;
                quiver3(ax, p(1), p(2), p(3), d(1), d(2), d(3), 0, 'Color', colour, ...
                    'LineWidth', 2.5, 'MaxHeadSize', 0.8, 'Tag', 'dipole');
                region = '';
                if k <= numel(fit.region)
                    region = fit.region{k};
                end
                if isempty(region)
                    region = '(no labelled region within 10 mm)';
                end
                rows(k, :) = {k, round(p(1)), round(p(2)), round(p(3)), region, ...
                    sprintf('%.1f%%', 100 * fit.rv)};
            end
            this.Table.Data = rows;
            title(ax, sprintf('%s: %s, %g to %g ms, %.1f%% of the data unexplained', ...
                fit.bin, lower(fit.model), fit.window(1), fit.window(2), 100 * fit.rv), ...
                'Interpreter', 'none');   % bin labels are literal text, not TeX
        end

        function onBinChanged(this, binIdx)
            this.notifyActivated();
            this.SelectedBin = binIdx;
            this.redraw();
        end
    end

    methods
        function focus = currentFocus(this)
            focus = struct('Bin', char(string(this.BinLabels{this.SelectedBin})));
        end

        function applyFocus(this, focus)
            if ~isstruct(focus) || ~isfield(focus, 'Bin')
                return;
            end
            idx = ViewFocus.indexOfLabel(this.BinLabels, focus.Bin);
            if isempty(idx) || isequal(idx, this.SelectedBin)
                return;
            end
            this.onBinChanged(idx);
            if ~isempty(this.BinDropdown) && isvalid(this.BinDropdown)
                this.BinDropdown.Value = idx;
            end
        end
    end
end

% ======================================================================= %
function orientations = momentAtPeak(mom, nDipoles)
%MOMENTATPEAK  Each dipole's unit orientation at the sample where its moment
%   is largest: a regional dipole may turn over its window, and the arrow
%   shows it where it matters most.
    orientations = zeros(nDipoles, 3);
    for k = 1:nDipoles
        m = mom(3 * (k - 1) + (1:3), :);
        [~, at] = max(vecnorm(m, 2, 1));
        v = m(:, at)';
        if norm(v) > 0
            orientations(k, :) = v / norm(v);
        end
    end
end
