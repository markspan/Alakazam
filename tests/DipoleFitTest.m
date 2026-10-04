classdef DipoleFitTest < matlab.unittest.TestCase
%DIPOLEFITTEST  Dipole Fit finds a dipole that was put there.
%
%   A dipole (or a mirrored pair) is placed in FieldTrip's template head,
%   its scalp field computed by FieldTrip's own forward model, a little
%   noise added, and the result fitted: the fitted position must lie within
%   a centimetre of the true one, with a low residual variance. The same
%   head model simulates and fits, so this checks the pipeline (channel
%   order, units, the window, the model, the reference), not anatomical
%   accuracy, which no template can promise. Needs FieldTrip, skips without.
%
%   See also DIPOLEFIT, DIPOLEVIEW.

    properties (Constant)
        Labels = {'Fp1', 'Fp2', 'AF3', 'AF4', 'F7', 'F3', 'Fz', 'F4', 'F8', 'FC5', 'FC1', ...
                  'FC2', 'FC6', 'T7', 'C3', 'Cz', 'C4', 'T8', 'CP5', 'CP1', 'CP2', 'CP6', ...
                  'P7', 'P3', 'Pz', 'P4', 'P8', 'PO3', 'PO4', 'O1', 'Oz', 'O2'}
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Views'), fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Transformations', 'DipoleFit')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end

        function requireFieldTrip(testCase)
            FieldTripFixtures.require(testCase);
        end
    end

    methods (Test)
        function findsTheDipoleThatWasPutThere(testCase)
            truth = [-48 -22 4];
            avg = testCase.simulate(truth, [0.3 0.2 0.93]);
            result = FieldTripFixtures.quietly(@() DipoleFit(avg, struct('Bins', {{'A'}}, ...
                'WindowStart', 80, 'WindowStop', 120, 'Model', 'One dipole', 'GridResolution', 10)));
            fit = result.dipoleFit;
            testCase.verifyEqual(fit.bin, 'A');
            testCase.verifySize(fit.pos, [1 3]);
            testCase.verifyLessThan(norm(fit.pos - truth), 10, ...
                sprintf('Fitted at [%s], put at [%s].', num2str(fit.pos, '%.0f '), num2str(truth)));
            testCase.verifyTrue(isscalar(fit.rv), 'One residual variance for the window.');
            testCase.verifyLessThan(fit.rv, 0.05);
            testCase.verifyEqual(fit.gof, 1 - fit.rv, 'AbsTol', 1e-12);
            testCase.verifyNumElements(fit.rvTime, numel(fit.time), 'FieldTrip''s own, per sample.');
            testCase.verifyEqual(fit.time([1 end]), [80 120], 'AbsTol', 1e-9, 'The window, in ms.');
            testCase.verifyTrue(contains(fit.region{1}, '_L'), ...
                sprintf('A left-hemisphere position is named as one (%s).', fit.region{1}));
            testCase.verifyEqual(result.data, avg.data, 'The data are not changed.');
        end

        function findsAMirroredPair(testCase)
            truth = [-46 -24 6; 46 -24 6];
            avg = testCase.simulate(truth, [0.2 0.1 0.97; -0.2 0.1 0.97]);
            result = FieldTripFixtures.quietly(@() DipoleFit(avg, struct('Bins', {{'A'}}, ...
                'WindowStart', 80, 'WindowStop', 120, 'Model', 'Mirrored pair', 'GridResolution', 10)));
            fit = result.dipoleFit;
            testCase.verifySize(fit.pos, [2 3]);
            testCase.verifyEqual(fit.pos(1, 2:3), fit.pos(2, 2:3), 'AbsTol', 1e-6, 'Mirrored across x.');
            testCase.verifyEqual(fit.pos(1, 1), -fit.pos(2, 1), 'AbsTol', 1e-6);
            left = fit.pos(fit.pos(:, 1) < 0, :);
            testCase.verifyLessThan(norm(left - truth(1, :)), 10);
            testCase.verifyLessThan(fit.rv, 0.05);
        end

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

        function aWindowThatEndsBeforeItStartsIsRefused(testCase)
            avg = testCase.simulate([-48 -22 4], [0 0 1]);
            testCase.verifyError(@() DipoleFit(avg, struct('Bins', {{'A'}}, 'WindowStart', 120, ...
                'WindowStop', 80)), 'Alakazam:DipoleFit');
        end
    end

    methods (Access = private)
        function avg = simulate(testCase, positions, moments)
        %SIMULATE  An averaged dataset holding the field of the dipoles, a
        %   Gaussian in time peaking at 100 ms, with noise at a fortieth of it.
            [~, ~, labels, elec, headmodel] = FieldTripFixtures.quietly(@() ...
                TransTools.BuildSourceForwardModel(testCase.Labels, 5124));
            [headmodel, elec] = FieldTripFixtures.quietly(@() ft_prepare_vol_sens(headmodel, elec));
            topography = zeros(numel(labels), 1);
            for k = 1:size(positions, 1)
                lf = FieldTripFixtures.quietly(@() ft_compute_leadfield(positions(k, :), elec, headmodel));
                topography = topography + lf * (moments(k, :)' / norm(moments(k, :)));
            end
            times = -100:4:300;
            course = exp(-((times - 100) / 25) .^ 2);
            clean = topography * course;
            rng(3);
            noisy = clean + randn(size(clean)) * max(abs(clean(:))) / 40;

            avg = struct('data', noisy, 'times', times, 'srate', 250, 'pnts', numel(times), ...
                'nbchan', numel(labels), 'trials', 1, 'DataFormat', 'AVERAGED', ...
                'DataType', 'TimeDomain', 'File', 'simulated.set', 'id', 'Average');
            avg.chanlocs = struct('labels', cellstr(string(labels(:)))');
            avg.chanlocs = avg.chanlocs(:)';
            avg.bindesc = struct('index', 1, 'label', 'A', 'trials', [], 'combo', [], 'n', 50);
        end
    end
end
