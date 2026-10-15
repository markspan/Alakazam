classdef DipoleViewTest < matlab.unittest.TestCase
%DIPOLEVIEWTEST  The view of a dipole fit: the dipoles on the template
%   brain, each arrow along its moment where the moment is largest, and a
%   table of their positions, regions and the residual variance. On a fit
%   written by hand, as Dipole Fit (a plugin, AlakazamDipolefit) stores
%   one. Needs FieldTrip for the template brain, and skips without it.
%
%   Run with: runtests('tests/DipoleViewTest.m').
%
%   See also DIPOLEVIEW, ALAKAZAMPLOTTER.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Views'), fullfile(root, 'src', 'Transformations')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end

        function requireFieldTrip(testCase)
            FieldTripFixtures.require(testCase);
        end
    end

    methods (Test)
        function theViewShowsTheDipolesAndTheirNumbers(testCase)
            eeg = struct('id', 'DipoleFit', 'DataFormat', 'AVERAGED', 'DataType', 'TimeDomain');
            % The second dipole turns: along y and weak at first, along x and
            % strongest at the end. The arrow must show the end.
            grow = linspace(0, 1, 11);
            mom = [repmat([0; 0; 1], 1, 11); 2 * grow; 0.5 * (1 - grow); zeros(1, 11)];
            eeg.dipoleFit = struct('bin', 'A', 'window', [80 120], 'model', 'Mirrored pair', ...
                'pos', [-46 -24 6; 46 -24 6], 'region', {{'Temporal_Mid_L', ''}}, ...
                'mom', mom, 'time', 80:4:120, 'rv', 0.0234, 'gof', 0.9766);
            testCase.verifyEqual(AlakazamPlotter.viewClassFor(eeg), 'DipoleView');

            fig = uifigure('Visible', 'off');
            closeFig = onCleanup(@() delete(fig));
            view = DipoleView(fig, eeg);
            rows = view.Table.Data;
            testCase.verifyEqual(rows(:, 2:4), {-46, -24, 6; 46, -24, 6});
            testCase.verifyEqual(rows{1, 5}, 'Temporal_Mid_L');
            testCase.verifyTrue(contains(rows{2, 5}, 'no labelled region'));
            testCase.verifyEqual(rows{1, 6}, '2.3%');
            arrows = findobj(view.Axes, 'Type', 'quiver', 'Tag', 'dipole');
            testCase.verifyNumElements(arrows, 2);
            second = arrows(arrayfun(@(a) a.XData > 0, arrows));
            testCase.verifyEqual([second.UData, second.VData, second.WData], [DipoleView.ArrowLength 0 0], ...
                'AbsTol', 1e-9, 'Along the moment where it is largest.');
            testCase.verifyTrue(contains(view.Axes.Title.String, '2.3%'));
        end
    end
end
