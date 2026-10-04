classdef BeamformerView < AlakazamView
%BEAMFORMERVIEW  A beamformer's map of relative power change: on the cortex
%   for the cortical sheet, on three slices of the template MRI for a volume
%   grid.
%
%   CORTICAL SHEET: the sheet itself, coloured by the change at each vertex,
%   rotatable, as the source estimates are drawn.
%
%   VOLUME GRID: the grid interpolated onto FieldTrip's template MRI
%   (single_subj_T1, MNI space) by FieldTrip's ft_sourceinterpolate, and
%   three orthogonal slices drawn through the map's peak: the anatomy in
%   grey, the change over it in the diverging colour scale, more opaque
%   where it is larger, so the peak reads at a glance and the anatomy is not
%   lost under the weak values.
%
%   Both are on a scale symmetric about zero, as every signed map in the
%   application is: a rise and a fall look alike but for their colour. A bin
%   dropdown switches between the bins that were mapped, and the title names
%   the peak and the AAL region at or near it.
%
%   See also BEAMFORMER, ALAKAZAMPLOTTER, BRAIN3DVIEW.

    properties (SetAccess = private)
        Figure
        EEG
        Grid
        Axes            % one axes (sheet), or three (grid: sagittal, coronal, axial)
        BinLabels
        SelectedBin = 1
        BinDropdown
        TitleLabel      % what is shown: method, bin, windows, the peak and its region
        Colorbar
        Slices          % grid: the interpolated volume per bin, made when first shown
    end

    methods
        function this = BeamformerView(fig, eeg)
            this.Figure = fig;
            this.EEG    = eeg;
            bf = eeg.beamformer;
            this.BinLabels = cellstr(string(bf.bins));
            this.Slices = cell(1, numel(this.BinLabels));

            hasDropdown = numel(this.BinLabels) > 1;
            dropdownRows = double(hasDropdown);
            this.Grid = uigridlayout(fig, [dropdownRows + 2, 2], ...
                "RowHeight", [repmat({26}, 1, dropdownRows), {22}, {'1x'}], ...
                "ColumnWidth", {'1x', TransTools.ColorbarColumnWidth()}, "Padding", [4 4 4 4]);
            if hasDropdown
                this.BinDropdown = TransTools.BuildBinDropdown(this.Grid, 1, 1, ...
                    this.BinLabels, @(idx) this.onBinChanged(idx));
            end
            % A label rather than an axes title: it spans the three slices
            % instead of being cut off over the first, and an atlas name
            % such as Parietal_Inf_L is not read as TeX subscripts.
            this.TitleLabel = uilabel(this.Grid, 'Text', '', 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center', 'Tag', 'BeamformerTitle');
            this.TitleLabel.Layout.Row = dropdownRows + 1;
            this.TitleLabel.Layout.Column = [1 2];

            row = dropdownRows + 2;
            if strcmp(bf.sourceModel, 'grid')
                tiles = uigridlayout(this.Grid, [1 3], 'Padding', [0 0 0 0], 'ColumnSpacing', 2);
                tiles.Layout.Row = row;
                tiles.Layout.Column = 1;
                this.Axes = gobjects(1, 3);
                for k = 1:3
                    this.Axes(k) = uiaxes(tiles);
                    this.Axes(k).ButtonDownFcn = @(~, ~) this.notifyActivated();
                    axtoolbar(this.Axes(k), {'zoomin', 'zoomout', 'restoreview'});
                end
            else
                this.Axes = uiaxes(this.Grid);
                this.Axes.Layout.Row = row;
                this.Axes.Layout.Column = 1;
                this.Axes.ButtonDownFcn = @(~, ~) this.notifyActivated();
                axtoolbar(this.Axes, "default");
                this.Axes.Interactions = rotateInteraction;
            end

            this.redraw();
            this.Colorbar = TransTools.AddSharedColorbar(this.Grid, row, 2, ...
                TransTools.DivergingColormap(), this.limits(), 'relative power change');
        end
    end

    methods (Access = private)
        function lim = limits(this)
        %LIMITS  Symmetric about zero, at the largest change over every bin,
        %   so the bins are drawn on one scale and can be compared by eye.
            m = max(abs(this.EEG.beamformer.values(:)), [], 'omitnan');
            if isempty(m) || ~isfinite(m) || m <= 0
                m = 1;
            end
            lim = [-m, m];
        end

        function redraw(this)
            bf = this.EEG.beamformer;
            b  = this.SelectedBin;
            if strcmp(bf.sourceModel, 'grid')
                this.drawSlices(b);
            else
                ax = this.Axes;
                cla(ax);
                TransTools.DrawBrainPatch(ax, bf.pos, bf.tri, bf.values(:, b), ...
                    TransTools.DivergingColormap(), this.limits(), []);
                axis(ax, 'equal', 'off');
                view(ax, [-90 20]);
                camlight(ax, 'headlight');
            end
            this.TitleLabel.Text = this.titleFor(b);
        end

        function drawSlices(this, b)
        %DRAWSLICES  Three slices through the peak, the change over the anatomy.
            if isempty(this.Slices{b})
                this.Slices{b} = interpolated(this.EEG.beamformer, b);
            end
            volume = this.Slices{b};
            peak = this.EEG.beamformer.peakPos(b, :);
            voxel = round(volume.transform \ [peak 1]');
            voxel = min(max(voxel(1:3)', 1), volume.dim);
            cmap = TransTools.DivergingColormap();
            lim = this.limits();
            planes = {@(v) squeeze(v(voxel(1), :, :)), @(v) squeeze(v(:, voxel(2), :)), ...
                      @(v) squeeze(v(:, :, voxel(3)))};
            names = {'sagittal', 'coronal', 'axial'};
            for k = 1:3
                ax = this.Axes(k);
                cla(ax);
                anatomy = planes{k}(volume.anatomy)';
                change  = planes{k}(volume.pow)';
                grey = rescale(double(anatomy));
                image(ax, repmat(grey, 1, 1, 3));
                hold(ax, 'on');
                index = round((change - lim(1)) / diff(lim) * (size(cmap, 1) - 1)) + 1;
                index = min(max(index, 1), size(cmap, 1));
                index(~isfinite(change)) = 1;
                colour = reshape(cmap(index, :), [size(change), 3]);
                % NaN outside the brain first, then the clamp: min(1, NaN)
                % is 1 in MATLAB, which drew every empty voxel opaque.
                alpha = abs(change) / max(abs(lim));
                alpha(~isfinite(alpha)) = 0;
                alpha = min(alpha, 1);
                image(ax, colour, 'AlphaData', alpha);
                set(ax, 'YDir', 'normal');
                axis(ax, 'image', 'off');
                text(ax, 2, 2, names{k}, 'Color', 'w', 'FontSize', 9, 'VerticalAlignment', 'bottom');
                hold(ax, 'off');
            end
        end

        function text = titleFor(this, b)
            bf = this.EEG.beamformer;
            what = upper(bf.method);
            if isfinite(bf.frequency)
                what = sprintf('%s at %g Hz', what, bf.frequency);
            end
            peak = bf.peakPos(b, :);
            region = '';
            if b <= numel(bf.peakRegion) && ~isempty(bf.peakRegion{b})
                region = sprintf(' (%s)', bf.peakRegion{b});
            end
            text = sprintf('%s, %s: %g to %g ms against %g to %g ms; peak at [%d %d %d]%s', ...
                what, this.BinLabels{b}, bf.active(1), bf.active(2), bf.baseline(1), bf.baseline(2), ...
                round(peak(1)), round(peak(2)), round(peak(3)), region);
        end

        function onBinChanged(this, binIdx)
            this.notifyActivated();
            this.SelectedBin = binIdx;
            this.redraw();
        end
    end

    methods
        function focus = currentFocus(this)
            focus = struct('Bin', this.BinLabels{this.SelectedBin});
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
function volume = interpolated(bf, b)
%INTERPOLATED  Bin B's grid map on FieldTrip's template MRI, by
%   ft_sourceinterpolate: .anatomy and .pow on the MRI's voxels, with its
%   .transform and .dim.
    persistent mri
    if isempty(mri)
        ftRoot = fileparts(which('ft_defaults'));
        mri = ft_convert_units(ft_read_mri(fullfile(ftRoot, 'template', 'anatomy', ...
            'single_subj_T1.nii')), 'mm');
    end
    source = struct('pos', bf.pos, 'inside', logical(bf.inside), 'dim', bf.dim, ...
        'pow', bf.values(:, b), 'unit', 'mm'); %#ok<NASGU> used in evalc
    cfg = struct('parameter', 'pow', 'interpmethod', 'linear', 'feedback', 'no'); %#ok<NASGU> used in evalc
    [~, volume] = evalc('ft_sourceinterpolate(cfg, source, mri);');
end
