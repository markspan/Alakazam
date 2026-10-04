classdef BeamformerTest < matlab.unittest.TestCase
%BEAMFORMERTEST  Beamformer finds the source whose power was raised.
%
%   Trials are simulated in FieldTrip's template head: a source at a
%   cortical vertex, oriented along the cortex, carries bursts at 12 Hz in
%   the active window only, with a random phase on every trial, among
%   background sources and sensor noise. LCMV and DICS (at 12 Hz) must put
%   the largest power increase within 15 mm of it, on the cortical sheet and
%   on the volume grid. One head model simulates and scans, so this checks
%   the pipeline (channels, reference, windows, the common filter, the
%   contrast), not anatomical accuracy. Needs FieldTrip, skips without.
%
%   See also BEAMFORMER, BEAMFORMERVIEW.

    properties (Constant)
        Labels = {'Fp1', 'Fp2', 'AF3', 'AF4', 'F7', 'F3', 'Fz', 'F4', 'F8', 'FC5', 'FC1', ...
                  'FC2', 'FC6', 'T7', 'C3', 'Cz', 'C4', 'T8', 'CP5', 'CP1', 'CP2', 'CP6', ...
                  'P7', 'P3', 'Pz', 'P4', 'P8', 'PO3', 'PO4', 'O1', 'Oz', 'O2'}
        Near = [-38 -62 42]     % the source sits at the sheet vertex closest to this
    end

    properties
        Truth       % the source's position, mm
        Epochs      % the simulated epoched dataset
        Sheet       % LCMV on the cortical sheet, made once
        GridResult  % LCMV on the volume grid, made once
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Views'), fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Transformations', 'Average'), ...
                     fullfile(root, 'src', 'Transformations', 'Beamformer'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end

        function simulateOnce(testCase)
            FieldTripFixtures.require(testCase);
            [testCase.Epochs, testCase.Truth] = testCase.simulate();
            testCase.Sheet = FieldTripFixtures.quietly(@() Beamformer(testCase.Epochs, ...
                testCase.opts('LCMV (time domain)', 'Cortical sheet')));
            testCase.GridResult = FieldTripFixtures.quietly(@() Beamformer(testCase.Epochs, ...
                testCase.opts('LCMV (time domain)', 'Volume grid')));
        end
    end

    methods (Test)
        function lcmvOnTheSheetFindsTheSource(testCase)
            result = testCase.Sheet;
            bf = result.beamformer;
            testCase.verifyEqual(bf.method, 'lcmv');
            testCase.verifyEqual(bf.sourceModel, 'cortex');
            testCase.verifyLessThan(norm(bf.peakPos - testCase.Truth), 15, ...
                sprintf('Peak at [%s], source at [%s].', num2str(bf.peakPos, '%.0f '), num2str(testCase.Truth, '%.0f ')));
            [~, atSource] = min(vecnorm(bf.pos - testCase.Truth, 2, 2));
            testCase.verifyGreaterThan(bf.values(atSource, 1), 1, ...
                'At the source, power more than doubled in the active window.');
            testCase.verifyEqual(result.DataFormat, "Averaged", 'The output is the average.');
            testCase.verifyEqual(bf.nTrials, 60);
            testCase.verifyTrue(contains(bf.peakRegion{1}, '_L'), bf.peakRegion{1});
        end

        function dicsAtTheFrequencyFindsTheSource(testCase)
            result = FieldTripFixtures.quietly(@() Beamformer(testCase.Epochs, testCase.opts('DICS (frequency)', 'Cortical sheet')));
            bf = result.beamformer;
            testCase.verifyEqual(bf.method, 'dics');
            testCase.verifyEqual(bf.frequency, 12);
            testCase.verifyLessThan(norm(bf.peakPos - testCase.Truth), 15, ...
                sprintf('Peak at [%s], source at [%s].', num2str(bf.peakPos, '%.0f '), num2str(testCase.Truth, '%.0f ')));
        end

        function lcmvOnTheGridFindsTheSource(testCase)
            result = testCase.GridResult;
            bf = result.beamformer;
            testCase.verifyEqual(bf.sourceModel, 'grid');
            testCase.verifyNotEmpty(bf.dim);
            testCase.verifyEqual(size(bf.values, 1), prod(bf.dim), 'One value per grid point.');
            testCase.verifyLessThan(norm(bf.peakPos - testCase.Truth), 15, ...
                sprintf('Peak at [%s], source at [%s].', num2str(bf.peakPos, '%.0f '), num2str(testCase.Truth, '%.0f ')));
        end

        function theViewDrawsTheSheetMapOnTheCortex(testCase)
            testCase.verifyEqual(AlakazamPlotter.viewClassFor(testCase.Sheet), 'BeamformerView');
            fig = uifigure('Visible', 'off');
            closeFig = onCleanup(@() delete(fig));
            view = BeamformerView(fig, testCase.Sheet);
            brain = findobj(view.Axes, 'Type', 'patch');
            testCase.verifyNumElements(brain, 1);
            testCase.verifyEqual(brain.FaceVertexCData(:), testCase.Sheet.beamformer.values(:, 1), ...
                'Each vertex coloured by its own change.');
            testCase.verifyTrue(contains(view.TitleLabel.Text, 'LCMV, A: 300 to 500 ms against -200 to 0 ms'));
            testCase.verifyTrue(contains(view.TitleLabel.Text, testCase.Sheet.beamformer.peakRegion{1}), ...
                'The peak''s region, as written.');
        end

        function theViewSlicesTheGridThroughItsPeak(testCase)
            fig = uifigure('Visible', 'off');
            closeFig = onCleanup(@() delete(fig));
            view = FieldTripFixtures.quietly(@() BeamformerView(fig, testCase.GridResult));
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

        function aTrialRejectedInAWindowIsLeftOut(testCase)
            epochs = testCase.Epochs;
            epochs.data(3, 122, 7) = NaN;      % 7th trial, a sample at 305 ms, in the active window
            result = FieldTripFixtures.quietly(@() Beamformer(epochs, ...
                testCase.opts('LCMV (time domain)', 'Cortical sheet')));
            testCase.verifyEqual(result.beamformer.nTrials, 59);
        end

        function windowsOfDifferentLengthsAreRefused(testCase)
            o = testCase.opts('LCMV (time domain)', 'Cortical sheet');
            o.BaselineStart = -250;
            testCase.verifyError(@() Beamformer(testCase.Epochs, o), 'Alakazam:Beamformer');
        end

        function anAverageIsRefused(testCase)
            avg = Average(testCase.Epochs, struct());
            testCase.verifyError(@() Beamformer(avg, testCase.opts('LCMV (time domain)', 'Cortical sheet')), ...
                'Alakazam:Beamformer');
        end
    end

    methods (Access = private)
        function o = opts(~, method, model)
            o = struct('Bins', {{'A'}}, 'Method', method, 'Frequency', 12, 'Smoothing', 4, ...
                'ActiveStart', 300, 'ActiveStop', 500, 'BaselineStart', -200, 'BaselineStop', 0, ...
                'SourceModel', model, 'SourceSpace', '5124', 'GridResolution', 10, 'Lambda', 5);
        end

        function [EEG, truth] = simulate(testCase)
            [lf, sheet, labels] = FieldTripFixtures.quietly(@() ...
                TransTools.BuildSourceForwardModel(testCase.Labels, 5124));
            normals = TransTools.SurfaceNormals(sheet);
            [~, at] = min(vecnorm(sheet.pos - testCase.Near, 2, 2));
            truth = sheet.pos(at, :);
            topography = lf.leadfield{at} * normals(at, :)';

            rng(12);
            nChan = numel(labels);
            nTrials = 60;
            srate = 200;
            times = -300:1000 / srate:700;
            burst = (times >= 300 & times <= 500) .* hann(numel(times))';
            burst(times >= 300 & times <= 500) = hann(nnz(times >= 300 & times <= 500))';
            others = randi(size(sheet.pos, 1), 1, 6);
            data = zeros(nChan, numel(times), nTrials);
            scale = norm(topography);
            for k = 1:nTrials
                signal = topography * (burst .* sin(2 * pi * 12 * times / 1000 + 2 * pi * rand));
                background = zeros(nChan, numel(times));
                for o = others
                    background = background + lf.leadfield{o} * normals(o, :)' * randn(1, numel(times)) * 0.5;
                end
                data(:, :, k) = signal + background + randn(nChan, numel(times)) * scale * 0.1;
            end

            EEG = makeTestEEG('nbchan', nChan, 'trials', nTrials, 'srate', srate, ...
                'epochMs', [-300 700], 'labels', cellstr(string(labels(:)))');
            EEG.data = data;
            EEG.bindesc = struct('index', 1, 'label', 'A', 'trials', 1:nTrials, 'combo', []);
            EEG.File = 'simulated.set';
        end
    end
end
