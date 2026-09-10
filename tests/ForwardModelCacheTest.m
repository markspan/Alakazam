classdef (TestTags = {'Slow'}) ForwardModelCacheTest < matlab.unittest.TestCase
%FORWARDMODELCACHETEST  The forward-model cache must be fast AND be the
%   same model.
%
%   Building the leadfield is the largest fixed cost in a source analysis,
%   measured at 18.0 s for 29 channels on the 20484 sheet. It is cached in
%   a small in-memory LRU, which brings the usual caching hazard: the
%   failure mode of a wrong cache is not slowness, it is an analysis run
%   against somebody else's forward model, with plausible numbers and no
%   way to notice. So the first test here is identity, not speed.
%
%   The speed assertions are deliberately loose (a cache hit must be an
%   order of magnitude faster, not some particular number of milliseconds),
%   because a timing test that pins an absolute figure fails on a slower
%   machine for no reason and teaches everyone to ignore it.
%
%   TAGGED SLOW WHOLE, 22 seconds: proving a cache is faster than the
%   thing it caches means computing that thing at least once, and here
%   that is a FieldTrip leadfield over thousands of dipoles. Run it with
%   runAlakazamTests("slow").
%
%   Run with: runtests('tests/ForwardModelCacheTest.m').
%
%   See also SOURCEINVERSETEST, FIELDTRIPFIXTURES.

    properties (Constant)
        Labels = {'FP1','FP2','F7','F3','FZ','F4','F8','FC5','FC1','FC2', ...
                  'FC6','T7','C3','CZ','C4','T8','CP5','CP1','CP2','CP6', ...
                  'P7','P3','PZ','P4','P8','O1','OZ','O2','POZ'}
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src')));
        end

        function requireFieldTrip(testCase)
            FieldTripFixtures.require(testCase);
        end
    end

    methods (Access = private)
        function [out, seconds] = build(testCase, labels, space) %#ok<INUSD>
            t = tic;
            [a, b, c, d, e] = TransTools.BuildSourceForwardModel(labels, space);
            seconds = toc(t);
            out = struct('leadfield', a, 'sourcemodel', b, ...
                'resolvedLabels', {c}, 'elec', d, 'headmodel', e);
        end

        function [out, seconds] = cachedOnly(testCase, labels, space) %#ok<INUSD>
            t = tic;
            [a, b, c, d, e] = TransTools.BuildSourceForwardModel(labels, space, 'cachedonly');
            seconds = toc(t);
            out = struct('leadfield', a, 'sourcemodel', b, ...
                'resolvedLabels', {c}, 'elec', d, 'headmodel', e);
        end
    end

    methods (Test)
        function aCacheHitReturnsTheIdenticalModel(testCase)
        %ACACHEHITRETURNSTHEIDENTICALMODEL  The assertion that matters. A
        %   fast wrong leadfield is far worse than a slow right one.
            first  = testCase.build(testCase.Labels, 5124);
            second = testCase.build(testCase.Labels, 5124);

            testCase.verifyEqual(second.leadfield, first.leadfield);
            testCase.verifyEqual(second.resolvedLabels, first.resolvedLabels);
            testCase.verifyEqual(second.sourcemodel.pos, first.sourcemodel.pos);
            testCase.verifyEqual(second.elec, first.elec);
        end

        function aCacheHitIsMuchFasterThanABuild(testCase)
            [~, cold] = testCase.build(testCase.Labels, 5124);
            [~, warm] = testCase.build(testCase.Labels, 5124);
            testCase.verifyLessThan(warm, max(cold / 10, 0.5), ...
                'A cache hit should not be within an order of magnitude of a build.');
        end

        function aDifferentMeshIsADifferentModel(testCase)
        %ADIFFERENTMESHISADIFFERENTMODEL  The mesh is in the key. Returning
        %   the cached leadfield for the wrong sheet would be silently,
        %   catastrophically wrong: the vertices would not be the vertices.
            coarse = testCase.build(testCase.Labels, 5124);
            fine   = testCase.build(testCase.Labels, 8196);
            testCase.verifyNotEqual(numel(coarse.leadfield.leadfield), ...
                numel(fine.leadfield.leadfield));
        end

        function aDifferentChannelSetIsADifferentModel(testCase)
        %ADIFFERENTCHANNELSETISADIFFERENTMODEL  The leadfield's rows ARE the
        %   channels, so a different set must not come back from the cache.
            all29 = testCase.build(testCase.Labels, 5124);
            fewer = testCase.build(testCase.Labels(1:20), 5124);
            testCase.verifyNotEqual(numel(fewer.resolvedLabels), ...
                numel(all29.resolvedLabels));
        end

        function alternatingBetweenModelsDoesNotEvictEither(testCase)
        %ALTERNATINGBETWEENMODELSDOESNOTEVICTEITHER  The regression that
        %   motivated the multi-entry LRU. With a single-entry cache, going
        %   A, B, A rebuilt A from scratch: measured at 16.1 s for a model
        %   computed seconds earlier. Both must now be hits.
            testCase.build(testCase.Labels, 5124);
            testCase.build(testCase.Labels, 8196);

            [~, backToFirst]  = testCase.build(testCase.Labels, 5124);
            [~, backToSecond] = testCase.build(testCase.Labels, 8196);

            testCase.verifyLessThan(backToFirst, 1.0, ...
                'Returning to a recently used model must not rebuild it.');
            testCase.verifyLessThan(backToSecond, 1.0, ...
                'Nor must alternating evict the other one.');
        end

        function askingWithoutBuildingReturnsNothingAndCostsNothing(testCase)
        %ASKINGWITHOUTBUILDINGRETURNSNOTHINGANDCOSTSNOTHING  'cachedonly' is
        %   the mode that lets a caller do optional work only when it is
        %   cheap. The source cluster report's point-spread figure is worth
        %   drawing when the model is in hand and is not worth 18 s of a
        %   click that asked for something else, so it asks this way.
        %
        %   BOTH HALVES MATTER. Returning empty is what makes the caller skip
        %   its work; returning empty QUICKLY is the entire reason the mode
        %   exists, since a miss that quietly built the model anyway would
        %   satisfy every other assertion here and reintroduce the cost.
        %
        %   A label subset used by no other test, so the miss is a real miss
        %   however the classes are ordered: the cache is one persistent for
        %   the whole MATLAB session, not one per test class.
            labels = testCase.Labels(1:13);

            t = tic;
            [leadfield, sourcemodel, resolved, elec, headmodel] = ...
                TransTools.BuildSourceForwardModel(labels, 5124, 'cachedonly');
            miss = toc(t);

            testCase.verifyEmpty(leadfield, 'A model came back that was never built.');
            testCase.verifyEmpty(sourcemodel);
            testCase.verifyEmpty(resolved);
            testCase.verifyEmpty(elec);
            testCase.verifyEmpty(headmodel);
            testCase.verifyLessThan(miss, 1.0, sprintf( ...
                ['A cache miss took %.1f s, so it built the model instead of ' ...
                 'declining to. That is the cost this mode exists to avoid.'], miss));

            built = testCase.build(labels, 5124);
            [hit, warm] = testCase.cachedOnly(labels, 5124);

            testCase.verifyEqual(hit.leadfield, built.leadfield, ...
                'After a build, the same question must return the same model.');
            testCase.verifyEqual(hit.resolvedLabels, built.resolvedLabels);
            testCase.verifyLessThan(warm, 1.0);
        end

        function anUnknownModeIsRefusedByName(testCase)
            testCase.verifyError(@() TransTools.BuildSourceForwardModel( ...
                testCase.Labels, 5124, 'peek'), ...
                'Alakazam:BuildSourceForwardModel:mode');
        end
    end
end
