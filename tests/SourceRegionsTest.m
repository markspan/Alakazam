classdef SourceRegionsTest < matlab.unittest.TestCase
%SOURCEREGIONSTEST  Region time courses (SourceRegions): each region is
%   FieldTrip's mean over its atlas vertices of Source Estimate's own
%   estimate, the signed mean flips each vertex to its region's dominant
%   orientation, and the result is an ordinary averaged dataset whose
%   channels are regions.
%
%   Synthetic subjects with a standard 10-20 montage, through the real
%   template forward model and FieldTrip's AAL atlas, on the 5124-vertex
%   sheet. Needs FieldTrip, and skips without it.
%
%   See also SOURCEREGIONS, SOURCENOISEMODELTEST.

    properties (Constant)
        Labels = {'Fp1', 'Fp2', 'F7', 'F3', 'Fz', 'F4', 'F8', 'T7', 'C3', 'Cz', ...
                  'C4', 'T8', 'P7', 'P3', 'Pz', 'P4', 'P8', 'O1', 'O2'}
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Views'), fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Transformations', 'Average'), ...
                     fullfile(root, 'src', 'Transformations', 'SourceEstimate'), ...
                     fullfile(root, 'src', 'Transformations', 'SourceRegions'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end

        function requireFieldTrip(testCase)
            FieldTripFixtures.require(testCase);
        end
    end

    methods (Test)
        function aRegionIsTheMeanOfItsVertices(testCase)
            avg = testCase.subjectAverage();
            [regions, opts] = FieldTripFixtures.quietly(@() SourceRegions(avg, testCase.regionOpts('Mean magnitude')));
            [values, vertexRegion, names] = testCase.reference(avg, opts, 'magnitude');

            testCase.verifyEqual({regions.chanlocs.labels}, names, 'One channel per region present.');
            testCase.verifySize(regions.data, [numel(names), numel(avg.times), 2]);
            for r = [1, round(numel(names) / 2), numel(names)]
                here = vertexRegion == find(strcmp(names{r}, names));
                expected = reshape(mean(values(here, :, :), 1), 1, [], 2);
                testCase.verifyEqual(regions.data(r, :, :), expected, 'RelTol', 1e-10, ...
                    sprintf('%s is the mean of its vertices.', names{r}));
            end
            testCase.verifyGreaterThan(min(regions.data(:)), 0, 'A mean of magnitudes is positive.');
        end

        function theSignedMeanFlipsEachVertexToItsRegion(testCase)
            avg = testCase.subjectAverage();
            [regions, opts] = FieldTripFixtures.quietly(@() SourceRegions(avg, testCase.regionOpts('Signed mean')));
            [values, vertexRegion, names, normals] = testCase.reference(avg, opts, 'normal');
            for r = [1, numel(names)]
                here = find(vertexRegion == r);
                [~, ~, V] = svd(normals(here, :), 'econ');
                flips = sign(normals(here, :) * V(:, 1));
                if sum(flips) < 0
                    flips = -flips;
                end
                expected = reshape(mean(values(here, :, :) .* flips, 1), 1, [], 2);
                testCase.verifyEqual(regions.data(r, :, :), expected, 'RelTol', 1e-10, 'AbsTol', 1e-12);
            end
            testCase.verifyLessThan(min(regions.data(:)), 0, 'A signed mean keeps both polarities.');
        end

        function theRegionsAreAnOrdinaryAveragedDataset(testCase)
            avg = testCase.subjectAverage();
            regions = FieldTripFixtures.quietly(@() SourceRegions(avg, testCase.regionOpts('Mean magnitude')));
            testCase.verifyEqual(regions.times, avg.times, 'The input''s own time axis.');
            testCase.verifyEqual(regions.nbchan, numel(regions.chanlocs));
            testCase.verifyEqual({regions.bindesc.label}, {'A', 'B'});
            testCase.verifyFalse(isfield(regions, 'noiseCov'), 'The electrodes'' noise is gone.');
            testCase.verifyFalse(isfield(regions, 'sourceEstimate'), 'The vertex estimate is not carried.');
            testCase.verifySize(regions.stErr, size(regions.data));
            info = regions.etc.alz.sourceRegions;
            testCase.verifyEqual(info.atlas, 'AAL');
            testCase.verifyEqual(info.noiseModel, 'baseline', 'Source Estimate''s default, used here.');
            testCase.verifyEqual(sum(info.nVertices) > 0, true);

            fig = uifigure('Visible', 'off');
            closeFig = onCleanup(@() delete(fig));
            view = AverageView(fig, regions);
            testCase.verifyEqual(string(view.Axes.YLabel.String), string(info.scaleLabel), ...
                'Its axis is the estimate''s scale, not microvolts.');
        end

        function theAtlasLabelsAreFieldTripsNearestNeighbourOnes(testCase)
        %THEATLASLABELSAREFIELDTRIPSNEARESTNEIGHBOURONES  Every vertex of the
        %   sheet carries the label FieldTrip's own route gives it, as its
        %   parcellation tutorials put an atlas on a source model.
            [~, sourcemodel] = FieldTripFixtures.quietly(@() ...
                TransTools.BuildSourceForwardModel(testCase.Labels, 5124));
            ftRoot = fileparts(which('ft_defaults'));
            files = {'aal', fullfile('aal', 'ROI_MNI_V4.nii'); ...
                     'brainnetome', fullfile('brainnetome', 'BNA_MPM_thr25_1.25mm.nii')};
            for k = 1:size(files, 1)
                [labelled, names] = TransTools.AtlasVertexLabels(sourcemodel, files{k, 1});
                atlas = ft_convert_units(ft_read_atlas(fullfile(ftRoot, 'template', 'atlas', files{k, 2})), 'mm');
                cfg = struct('interpmethod', 'nearest', 'parameter', 'tissue');
                theirs = FieldTripFixtures.quietly(@() ft_sourceinterpolate(cfg, atlas, ...
                    struct('pos', sourcemodel.pos, 'tri', sourcemodel.tri, 'unit', 'mm')));
                expected = double(theirs.tissue(:));
                expected(~isfinite(expected)) = 0;
                testCase.verifyEqual(labelled, expected, files{k, 1});
                testCase.verifyEqual(names, atlas.tissuelabel(:), files{k, 1});
            end
        end

        function theAtlasIsPutOnTheSheetByFieldTripItself(testCase)
        %THEATLASISPUTONTHESHEETBYFIELDTRIPITSELF  The lookup is FieldTrip's
        %   ft_sourceinterpolate, nearest neighbour, not a copy of it: a
        %   stand-in, first on the path, records what it is asked and hands
        %   back labels of its own, which are the ones that come out. A
        %   sheet of 97 vertices, so the lookup's cache has nothing for it.
            [~, sourcemodel] = FieldTripFixtures.quietly(@() ...
                TransTools.BuildSourceForwardModel(testCase.Labels, 5124));
            sheet = struct('pos', sourcemodel.pos(1:97, :), 'unit', 'mm');
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            fid = fopen(fullfile(folder, 'ft_sourceinterpolate.m'), 'w');
            fprintf(fid, '%s\n', ...
                'function out = ft_sourceinterpolate(cfg, functional, anatomical)', ...
                'setappdata(groot, ''AtlasLookupCfg'', cfg);', ...
                'out = anatomical;', ...
                'out.tissue = mod((1:size(anatomical.pos, 1))'', 7);', ...
                'end');
            fclose(fid);
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(folder));
            setappdata(groot, 'AtlasLookupCfg', []);
            testCase.addTeardown(@() rmappdata(groot, 'AtlasLookupCfg'));

            labelled = TransTools.AtlasVertexLabels(sheet, 'aal');

            cfg = getappdata(groot, 'AtlasLookupCfg');
            testCase.assertNotEmpty(cfg, 'FieldTrip''s ft_sourceinterpolate was not called.');
            testCase.verifyEqual(cfg.interpmethod, 'nearest');
            testCase.verifyEqual(cfg.parameter, 'tissue');
            testCase.verifyEqual(labelled, mod((1:97)', 7), 'The labels are the ones FieldTrip gave.');
        end
    end

    methods (Access = private)
        function avg = subjectAverage(testCase)
            rng(4);
            EEG = makeTestEEG('nbchan', numel(testCase.Labels), 'trials', 30, ...
                'srate', 100, 'epochMs', [-200 500], 'labels', testCase.Labels);
            nChan = numel(testCase.Labels);
            EEG.data = randn(nChan, EEG.pnts, 30);
            response = linspace(-1, 1, nChan)' * (EEG.times > 100 & EEG.times < 300) * 3;
            EEG.data(:, :, 1:15) = EEG.data(:, :, 1:15) + response;
            EEG.bindesc(1) = struct('index', 1, 'label', 'A', 'trials', 1:15, 'combo', []);
            EEG.bindesc(2) = struct('index', 2, 'label', 'B', 'trials', 16:30, 'combo', []);
            avg = Average(EEG);
            avg.File = 'subject.set';
        end

        function opts = regionOpts(~, value)
            opts = struct('Atlas', 'AAL', 'Value', value, 'Method', 'dSPM', ...
                'SourceSpace', '5124', 'NoiseCovariance', 'auto', 'SNR', 3, 'RegParam', 0.05);
        end

        function [values, vertexRegion, names, normals] = reference(~, avg, opts, orientation)
        %REFERENCE  The same estimate through Source Estimate directly, and the
        %   atlas's vertices, for an independent mean.
            est = FieldTripFixtures.quietly(@() SourceEstimate(avg, struct('Method', 'mne', ...
                'Orientation', orientation, 'SourceSpace', 5124, 'TimeWindow', [], ...
                'ResampleHz', [], 'RegParam', opts.RegParam, 'NoiseCovariance', 'auto', 'SNR', 3)));
            values = est.sourceEstimate(end).values;
            [~, sourcemodel] = TransTools.BuildSourceForwardModel({est.ScalpChanlocs.labels}, 5124);
            [vertexRegion, allNames] = TransTools.AtlasVertexLabels(sourcemodel, 'aal');
            present = unique(vertexRegion(vertexRegion > 0));
            [~, vertexRegion] = ismember(vertexRegion, present);
            names = cellstr(string(allNames(present)))';
            normals = TransTools.SurfaceNormals(sourcemodel);
        end
    end
end
