classdef SourceClusterStatsTest < matlab.unittest.TestCase
%SOURCECLUSTERSTATSTEST  Group statistics on source estimates.
%
%   THE TESTS THAT MATTER MOST HERE ARE THE REFUSALS. A cluster test always
%   returns something: a map, a p-value, a picture. It does not fail loudly
%   when the design underneath it is invalid, it just produces a confident
%   answer to a question nobody asked. Two such combinations are possible
%   with these options, and both are refused rather than run:
%
%     magnitude + vsZero   a magnitude source estimate is non-negative at
%                          every vertex by construction, so testing it
%                          against zero would flag essentially all cortex
%     eLORETA              un-normalized amplitude, so vertices are not on
%                          comparable footing in a vertex-wise test
%
%   Those, and the adjacency, are checkable without FieldTrip and run in
%   milliseconds. The one end-to-end test is tagged 'Slow': it inverts real
%   subjects onto FieldTrip's real template sheet and permutes, which is
%   tens of seconds even with the sample count cut right down.
%
%   Run with: runtests('tests/SourceClusterStatsTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Transformations')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        % ---- refusing invalid designs, before any computation -------------
        function magnitudeAgainstZeroIsRefused(testCase)
        %MAGNITUDEAGAINSTZEROISREFUSED  The most dangerous combination
        %   available, because it runs perfectly happily and returns a map
        %   of almost the whole cortex.
            err = testCase.errorFrom(@() SourceClusterStats( ...
                {'a.mat', 'b.mat'}, struct('mode', 'vsZero', 'bin', 'A'), ...
                struct('Orientation', 'magnitude')));

            testCase.verifyEqual(err.identifier, 'Alakazam:SourceClusterStats');
            testCase.verifySubstring(err.message, 'positive at every vertex');
        end

        function eloretaIsRefusedForAGroupTest(testCase)
        %ELORETAISREFUSEDFORAGROUPTEST  Excellent localizer, wrong input to
        %   a vertex-wise test: it is not depth-normalized, so vertices are
        %   not comparable with one another.
            err = testCase.errorFrom(@() SourceClusterStats( ...
                {'a.mat', 'b.mat'}, struct('mode', 'paired', 'binA', 'A', 'binB', 'B'), ...
                struct('Method', 'eloreta')));

            testCase.verifyEqual(err.identifier, 'Alakazam:SourceClusterStats');
            testCase.verifySubstring(err.message, 'depth bias');
        end

        function signedAgainstZeroIsAllowed(testCase)
        %SIGNEDAGAINSTZEROISALLOWED  The counterpart of the refusal above:
        %   with a signed estimate the null is meaningful, so this
        %   combination must NOT be blocked. Checked by confirming the
        %   failure that follows is about the missing files, not the design.
            err = testCase.errorFrom(@() SourceClusterStats( ...
                {'no-such-file.mat', 'nor-this.mat'}, ...
                struct('mode', 'vsZero', 'bin', 'A'), struct('Orientation', 'normal')));

            testCase.verifyEmpty(strfind(err.message, 'positive at every vertex'));
        end

        function aBadTimeWindowIsRefused(testCase)
            err = testCase.errorFrom(@() SourceClusterStats( ...
                {'a.mat', 'b.mat'}, struct('mode', 'paired', 'binA', 'A', 'binB', 'B'), ...
                struct('TimeWindow', 300)));

            testCase.verifySubstring(err.message, 'startMs stopMs');
        end

        function oneSubjectIsRefused(testCase)
            err = testCase.errorFrom(@() SourceClusterStats({'only.mat'}, ...
                struct('mode', 'vsZero', 'bin', 'A'), struct()));

            testCase.verifySubstring(err.message, 'at least 2 subjects');
        end

        % ---- the adjacency the correction clusters over -------------------
        function meshAdjacencyIsSymmetricAndExcludesSelf(testCase)
            sphere = testCase.icosphere();

            [nb, labels] = TransTools.SourceNeighbours(sphere);

            testCase.verifyNumElements(nb, size(sphere.pos, 1));
            testCase.verifyNumElements(labels, size(sphere.pos, 1));
            for k = 1:numel(nb)
                testCase.verifyFalse(ismember(nb(k).label, nb(k).neighblabel), ...
                    'A vertex was listed as its own neighbour.');
                for other = nb(k).neighblabel
                    back = nb(strcmp({nb.label}, other{1})).neighblabel;
                    testCase.verifyTrue(ismember(nb(k).label, back), ...
                        'Adjacency is not symmetric.');
                end
            end
        end

        function adjacencyFollowsTheMeshNotEuclideanDistance(testCase)
        %ADJACENCYFOLLOWSTHEMESHNOTEUCLIDEANDISTANCE  The reason mesh
        %   adjacency is the correct choice: two vertices can be very close
        %   in space while not being connected across the surface, as
        %   opposite banks of a sulcus are. A distance-based neighbourhood
        %   would merge them and invent spatial extent.
            %   Two separate triangles, placed a hair apart but sharing no
            %   vertex -- geometrically adjacent, topologically not.
            sheet = struct();
            sheet.pos = [0 0 0; 1 0 0; 0 1 0; ...
                         0 0 0.001; 1 0 0.001; 0 1 0.001];
            sheet.tri = [1 2 3; 4 5 6];

            nb = TransTools.SourceNeighbours(sheet);

            testCase.verifyEqual(sort(nb(1).neighblabel), {'v2', 'v3'}, ...
                'Vertex 1 gained a neighbour it shares no triangle with.');
            testCase.verifyFalse(ismember('v4', nb(1).neighblabel), ...
                'A vertex 1 micron away, on a disconnected face, was treated as adjacent.');
        end

        function aVolumetricGridIsRefused(testCase)
            testCase.verifyError(@() TransTools.SourceNeighbours(struct('pos', randn(20, 3))), ...
                'Alakazam:SourceNeighbours');
        end

        function vertexLabelsMatchBetweenAdjacencyAndData(testCase)
        %VERTEXLABELSMATCHBETWEENADJACENCYANDDATA  FieldTrip matches the
        %   neighbour structure to the data BY LABEL and silently intersects
        %   the two sets. If these ever disagreed, the test would quietly
        %   run on whatever overlapped rather than failing.
            sphere = testCase.icosphere();

            [nb, fromNeighbours] = TransTools.SourceNeighbours(sphere);
            fromData = TransTools.SourceVertexLabels(size(sphere.pos, 1));

            testCase.verifyEqual(fromData(:), fromNeighbours(:));
            testCase.verifyEqual({nb.label}, fromData(:)');
        end

        % ---- the design logic is shared, not copied ------------------------
        function theDesignBuilderTakesTheTimelockFactory(testCase)
        %THEDESIGNBUILDERTAKESTHETIMELOCKFACTORY  The scalp and source tests
        %   share ClusterStats.buildDesign; only the timelock factory
        %   differs. If that parameter stopped being honoured, the source
        %   test would silently run on scalp channels.
            subjects = {struct('id', 's1'), struct('id', 's2')};
            called = strings(0);
            factory = @(EEG, binLabel) fakeTimelock(EEG, binLabel);

            [timelocks, design, ivar, uvar, statistic] = ClusterStats.buildDesign( ...
                subjects, struct('mode', 'paired', 'binA', 'A', 'binB', 'B'), factory);

            testCase.verifyNumElements(timelocks, 4);      % 2 subjects x 2 bins
            testCase.verifyEqual(statistic, 'depsamplesT');
            testCase.verifyEqual(timelocks{1}.label, {'made-up'});
            testCase.verifySize(design, [2, 4]);
            testCase.verifyEqual(ivar, 1);
            testCase.verifyEqual(uvar, 2);
            testCase.verifyEmpty(called);

            function tl = fakeTimelock(~, binLabel)
                tl = struct('label', {{'made-up'}}, 'time', 0:0.01:0.05, ...
                    'avg', ones(1, 6), 'dimord', 'chan_time', 'bin', binLabel);
            end
        end
    end

    % ---- against the real template sheet and real recordings ---------------
    methods (Test, TestTags = {'Slow'})
        function theWholePipelineRunsOnRealSubjects(testCase)
        %THEWHOLEPIPELINERUNSONREALSUBJECTS  End to end: shared forward
        %   model, per-subject signed dSPM, mesh adjacency, TFCE
        %   permutation. Checks the SHAPE and the settings actually used --
        %   not the p-values, which a two-subject fixture cannot support and
        %   which would be a meaningless thing to pin anyway.
            FieldTripFixtures.require(testCase);
            files = testCase.realSubjectAverages();
            testCase.assumeNotEmpty(files, ...
                'The BCN2025 cached averages are not present in this checkout.');

            L = load(files{1}, 'EEG');
            bins = {L.EEG.bindesc.label};
            contrast = struct('mode', 'paired', 'binA', bins{1}, 'binB', bins{2});

            summary = FieldTripFixtures.quietly(@() SourceClusterStats(files, contrast, ...
                struct('TimeWindow', [200 400], 'ResampleHz', 100, 'numrandomization', 10)));

            testCase.verifySize(summary.stat.stat, ...
                [numel(summary.vertexLabels), numel(summary.times)]);
            testCase.verifyEqual(summary.opts.correctm, 'tfce');
            testCase.verifyEqual(summary.opts.Method, 'mne');
            testCase.verifyEqual(summary.opts.Orientation, 'normal');
            testCase.verifyGreaterThanOrEqual(summary.times(1), 200);
            testCase.verifyLessThanOrEqual(summary.times(end), 400);
            testCase.verifyEqual(summary.nSubjects, numel(files));
            testCase.verifyNotEmpty(summary.sourcemodel.tri);
        end
    end

    methods (Access = private)
        function err = errorFrom(~, fn)
            try
                fn();
                err = MException('Alakazam:NoError', 'no error was raised');
            catch err
            end
        end

        function s = icosphere(~)
            [x, y, z] = sphere(10);
            p = unique([x(:), y(:), z(:)], 'rows');
            s = struct('pos', p, 'tri', convhull(p(:, 1), p(:, 2), p(:, 3)));
        end

        function files = realSubjectAverages(~)
        %REALSUBJECTAVERAGES  The cached BCN2025 subject averages, when this
        %   checkout has them. Data/ is gitignored, so this returns {} on a
        %   clean clone and the test assumes out rather than failing.
            root = fileparts(fileparts(mfilename('fullpath')));
            found = dir(fullfile(root, 'Data', 'Cache', 'BCN2025*', '**', 'Average*.mat'));
            files = arrayfun(@(f) fullfile(f.folder, f.name), found, 'UniformOutput', false);
            files = files(:)';
            if numel(files) > 2
                files = files(1:2);
            elseif numel(files) < 2
                files = {};
            end
        end
    end
end
