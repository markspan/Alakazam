classdef AtlasVertexLabelsTest < matlab.unittest.TestCase
%ATLASVERTEXLABELSTEST  An atlas on the template cortical sheet, by
%   TransTools.AtlasVertexLabels: every vertex carries the label FieldTrip's
%   own nearest-neighbour route gives it, for AAL and Brainnetome, and the
%   lookup is FieldTrip's ft_sourceinterpolate, not a copy of it. The
%   source cluster report names its clusters by it, and Source Regions (a
%   plugin) its regions. Needs FieldTrip, and skips without it.
%
%   Run with: runtests('tests/AtlasVertexLabelsTest.m').
%
%   See also TRANSTOOLS.ATLASVERTEXLABELS, TRANSTOOLS.DESCRIBECLUSTER.

    properties (Constant)
        Labels = {'Fp1', 'Fp2', 'F7', 'F3', 'Fz', 'F4', 'F8', 'T7', 'C3', 'Cz', ...
                  'C4', 'T8', 'P7', 'P3', 'Pz', 'P4', 'P8', 'O1', 'O2'}
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Transformations')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end

        function requireFieldTrip(testCase)
            FieldTripFixtures.require(testCase);
        end
    end

    methods (Test)
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
end
