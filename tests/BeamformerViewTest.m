classdef BeamformerViewTest < matlab.unittest.TestCase
%BEAMFORMERVIEWTEST  The view of a beamformer's map: on the cortex for a
%   cortical sheet, on three slices of the template MRI through the peak for
%   a volume grid, with a title that names the method, the windows, the peak
%   and its region.
%
%   On maps written by hand, as Beamformer (a plugin, AlakazamBeamformer)
%   stores them in EEG.beamformer: a small sheet, and a regular 10 mm grid
%   in MNI space with one peak. The plugin's own tests draw its real
%   output. The grid case needs FieldTrip (the template MRI and
%   ft_sourceinterpolate), and skips without it.
%
%   Run with: runtests('tests/BeamformerViewTest.m').
%
%   See also BEAMFORMERVIEW, ALAKAZAMPLOTTER.

    properties (Constant)
        Peak = [-40 -60 40]     % the grid's peak, on a grid point, mm
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Views'), fullfile(root, 'src', 'Transformations')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function theSheetIsColouredByItsOwnChange(testCase)
            eeg = BeamformerViewTest.sheet();
            testCase.verifyEqual(AlakazamPlotter.viewClassFor(eeg), 'BeamformerView');
            fig = uifigure('Visible', 'off');
            closeFig = onCleanup(@() delete(fig));
            view = BeamformerView(fig, eeg);
            brain = findobj(view.Axes, 'Type', 'patch');
            testCase.verifyNumElements(brain, 1);
            testCase.verifyEqual(brain.FaceVertexCData(:), eeg.beamformer.values(:, 1), ...
                'Each vertex coloured by its own change.');
            testCase.verifyTrue(contains(view.TitleLabel.Text, ...
                'LCMV, A: 300 to 500 ms against -200 to 0 ms; peak at [-38 -62 42] (Parietal_Inf_L)'), ...
                view.TitleLabel.Text);

            view.applyFocus(struct('Bin', 'B'));
            brain = findobj(view.Axes, 'Type', 'patch');
            testCase.verifyEqual(brain.FaceVertexCData(:), eeg.beamformer.values(:, 2), ...
                'The second bin, on the same scale.');
            testCase.verifyTrue(contains(view.TitleLabel.Text, 'LCMV, B:'));
        end

        function aDicsMapNamesItsFrequency(testCase)
            eeg = BeamformerViewTest.sheet();
            eeg.beamformer.method = 'dics';
            eeg.beamformer.frequency = 12;
            fig = uifigure('Visible', 'off');
            closeFig = onCleanup(@() delete(fig));
            view = BeamformerView(fig, eeg);
            testCase.verifyTrue(startsWith(view.TitleLabel.Text, 'DICS at 12 Hz, A:'), view.TitleLabel.Text);
        end

        function theGridIsSlicedThroughItsPeak(testCase)
            FieldTripFixtures.require(testCase);
            fig = uifigure('Visible', 'off');
            closeFig = onCleanup(@() delete(fig));
            view = FieldTripFixtures.quietly(@() BeamformerView(fig, BeamformerViewTest.grid()));
            testCase.verifyNumElements(view.Axes, 3, 'Sagittal, coronal and axial.');
            for k = 1:3
                layers = findobj(view.Axes(k), 'Type', 'image');
                testCase.verifyNumElements(layers, 2, 'The anatomy, and the change over it.');
                overlay = layers(arrayfun(@(i) ~isscalar(i.AlphaData), layers));
                testCase.verifyGreaterThan(max(overlay.AlphaData(:)), 0.95, ...
                    'Each slice passes through the peak, where the change is drawn opaque.');
                testCase.verifyLessThan(mean(overlay.AlphaData(:)), 0.5, ...
                    'Outside the brain, and where the change is small, the anatomy shows.');
            end
        end
    end

    methods (Static, Access = private)
        function eeg = averaged(bf)
        %AVERAGED  An averaged dataset carrying the map BF, as Beamformer's
        %   result does.
            eeg = struct('id', 'Beamformer', 'DataFormat', 'AVERAGED', 'DataType', 'TimeDomain', ...
                'trials', 1, 'beamformer', bf);
        end

        function eeg = sheet()
        %SHEET  Two bins on a small closed sheet: a rise near the left
        %   parietal cortex in A, a weaker fall in B.
            [x, y, z] = sphere(12);
            pos = unique(70 * [x(:), y(:), z(:)], 'rows');
            tri = convhulln(pos);
            rise = exp(-sum((pos - [-38 -62 42]) .^ 2, 2) / (2 * 20 ^ 2));
            bf = struct('bins', {{'A', 'B'}}, 'method', 'lcmv', 'frequency', NaN, ...
                'sourceModel', 'cortex', 'pos', pos, 'tri', tri, 'values', [2 * rise, -rise], ...
                'peakPos', [-38 -62 42; -38 -62 42], 'peakRegion', {{'Parietal_Inf_L', ''}}, ...
                'active', [300 500], 'baseline', [-200 0], 'nTrials', 60);
            eeg = BeamformerViewTest.averaged(bf);
        end

        function eeg = grid()
        %GRID  One bin on a regular 10 mm grid in MNI space, in FieldTrip's
        %   order (x fastest), inside an ellipsoid round the brain: a change
        %   of 1 at the peak, falling off over about 15 mm.
            xs = -80:10:80;
            ys = -110:10:80;
            zs = -60:10:90;
            [X, Y, Z] = ndgrid(xs, ys, zs);
            pos = [X(:), Y(:), Z(:)];
            inside = sum(((pos - [0 -20 15]) ./ [70 95 75]) .^ 2, 2) <= 1;
            values = exp(-sum((pos - BeamformerViewTest.Peak) .^ 2, 2) / (2 * 15 ^ 2));
            values(~inside) = NaN;
            bf = struct('bins', {{'A'}}, 'method', 'lcmv', 'frequency', NaN, ...
                'sourceModel', 'grid', 'pos', pos, 'dim', [numel(xs), numel(ys), numel(zs)], ...
                'inside', inside, 'values', values, 'peakPos', BeamformerViewTest.Peak, ...
                'peakRegion', {{'Parietal_Inf_L'}}, 'active', [300 500], 'baseline', [-200 0], ...
                'nTrials', 60);
            eeg = BeamformerViewTest.averaged(bf);
        end
    end
end
