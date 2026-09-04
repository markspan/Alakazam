classdef InverseFilterCacheTest < matlab.unittest.TestCase
%INVERSEFILTERCACHETEST  The spatial-filter memo in TransTools.InverseSolution.
%
%   THE PREMISE, WHICH IS NOT OBVIOUS AND WAS MEASURED. All three
%   ft_inverse_* functions are handed the data (and two of them the data
%   covariance), so nothing in their signatures says the filter they return
%   is data-independent. It is: computing each from two completely different
%   datasets on one leadfield gives bit-identical operators for mne, eloreta
%   and sloreta alike. That is what makes reusing one across every subject
%   and bin of a group analysis legitimate rather than merely fast.
%
%   Everything here is therefore about the cache NOT conflating things that
%   differ. A wrong filter does not make an analysis slow, it inverts one
%   montage's data through another's forward model and reports plausible
%   numbers, so each dimension of the key gets its own test.
%
%   Run with: runtests('tests/InverseFilterCacheTest.m').
%
%   See also SOURCEINVERSETEST, FORWARDMODELCACHETEST, FIELDTRIPFIXTURES.

    properties (Constant)
        Labels = {'FP1','FP2','F7','F3','FZ','F4','F8','FC5','FC1','FC2', ...
                  'FC6','T7','C3','CZ','C4','T8','CP5','CP1','CP2','CP6', ...
                  'P7','P3','PZ','P4','P8','O1','OZ','O2','POZ'}
    end

    properties
        Leadfield; Sourcemodel; Labels_; Elec; Headmodel; Normals; NChan
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

        function buildModel(testCase)
            [a, b, c, d, e] = TransTools.BuildSourceForwardModel(testCase.Labels, 5124);
            testCase.Leadfield = a;
            testCase.Sourcemodel = b;
            testCase.Labels_ = c;
            testCase.Elec = d;
            testCase.Headmodel = e;
            testCase.Normals = TransTools.SurfaceNormals(b);
            testCase.NChan = numel(c);
        end
    end

    methods (Access = private)
        function [p, info] = invert(testCase, data, method, opts)
            [p, info] = TransTools.InverseSolution(data, testCase.Leadfield, ...
                testCase.Elec, testCase.Headmodel, method, opts);
        end

        function o = opts(testCase, varargin)
            o = struct('RegParam', 0.05, 'Orientation', 'magnitude', ...
                'Normals', testCase.Normals);
            for k = 1:2:numel(varargin)
                o.(varargin{k}) = varargin{k+1};
            end
        end

        function d = data(testCase, seed, scale)
            rng(seed);
            d = scale * randn(testCase.NChan, 41);
        end
    end

    methods (Test)
        function repeatedCallsGiveIdenticalResults(testCase)
        %REPEATEDCALLSGIVEIDENTICALRESULTS  The cache must change speed and
        %   nothing else.
            for method = {'mne', 'sloreta', 'eloreta'}
                x = testCase.data(1, 1);
                [p1, i1] = testCase.invert(x, method{1}, testCase.opts());
                [p2, i2] = testCase.invert(x, method{1}, testCase.opts());
                testCase.verifyEqual(p2, p1, ...
                    sprintf('%s must return the identical result on a cache hit.', method{1}));
                testCase.verifyEqual(i2.ResidualVariance, i1.ResidualVariance);
                testCase.verifyEqual(i2.ScaleLabel, i1.ScaleLabel, ...
                    'The scale label is set outside the cached branch and must survive a hit.');
            end
        end

        function newDataThroughACachedFilterStillDependsOnTheData(testCase)
        %NEWDATATHROUGHACACHEDFILTERSTILLDEPENDSONTHEDATA  The obvious way
        %   a filter cache could go wrong: returning the first subject's
        %   source estimate for every subject after it.
            first  = testCase.invert(testCase.data(1, 1), 'mne', testCase.opts());
            second = testCase.invert(testCase.data(2, 4), 'mne', testCase.opts());
            testCase.verifyNotEqual(second, first, ...
                'A cached filter must still be applied to each subject''s own data.');
        end

        function orientationIsAppliedAfterTheFilterAndStillChangesTheAnswer(testCase)
        %ORIENTATIONISAPPLIEDAFTERTHEFILTERANDSTILLCHANGESTHEANSWER
        %   Orientation is deliberately NOT part of the filter key: the
        %   filter is shared and the free-orientation collapse differs. This
        %   pins that the collapse still happens.
            x = testCase.data(1, 1);
            magnitude = testCase.invert(x, 'mne', testCase.opts('Orientation', 'magnitude'));
            normal    = testCase.invert(x, 'mne', testCase.opts('Orientation', 'normal'));

            testCase.verifyNotEqual(normal, magnitude);
            testCase.verifyTrue(any(normal(:) < 0), ...
                'A normal-projected estimate keeps its sign; a magnitude cannot be negative.');
            testCase.verifyTrue(all(magnitude(~isnan(magnitude)) >= 0));
        end

        function regularisationIsPartOfTheKey(testCase)
        %REGULARISATIONISPARTOFTHEKEY  Via sLORETA, DELIBERATELY, and this
        %   is the whole point of the test.
        %
        %   The obvious version of this used mne and proved nothing: mne
        %   applies its dSPM normalisation AFTER the filter, dividing by
        %   sqrt(lambda * sum(M.^2, 2)), so changing RegParam changes the
        %   result through that division even when a stale filter is reused.
        %   Written with mne, the test passed with method and regularisation
        %   deleted from the cache key, which was checked by deleting them.
        %
        %   sLORETA gets no post-filter normalisation, so RegParam reaches
        %   the answer ONLY through the filter. If the cache ignored it,
        %   these two would be identical.
            x = testCase.data(1, 1);
            loose = testCase.invert(x, 'sloreta', testCase.opts('RegParam', 0.05));
            tight = testCase.invert(x, 'sloreta', testCase.opts('RegParam', 0.50));
            testCase.verifyNotEqual(tight, loose, ...
                'Two regularisations are two different filters, not two precisions.');
        end

        function methodIsPartOfTheKey(testCase)
        %METHODISPARTOFTHEKEY  sLORETA against eLORETA, for the same reason.
        %
        %   Comparing either against mne would prove nothing, since only mne
        %   carries the dSPM normalisation and that alone would separate
        %   them. These two share every line of the code path after the
        %   filter, so if one were served the other's cached filter their
        %   results would be bit-identical.
            x = testCase.data(1, 1);
            sloreta = testCase.invert(x, 'sloreta', testCase.opts());
            eloreta = testCase.invert(x, 'eloreta', testCase.opts());
            testCase.verifyNotEqual(eloreta, sloreta, ...
                ['sLORETA and eLORETA differ only in their filter, so identical ' ...
                 'results here mean one was served the other''s.']);
        end

        function aDifferentLeadfieldIsNotServedFromTheCache(testCase)
        %ADIFFERENTLEADFIELDISNOTSERVEDFROMTHECACHE  The worst case the key
        %   guards: one montage's data inverted through another's model.
        %   With a different channel count a wrongly reused filter cannot
        %   even multiply, so this would throw rather than mislead; the
        %   digest is what covers the same-count case.
            testCase.invert(testCase.data(1, 1), 'mne', testCase.opts());

            [lf2, sm2, rl2, el2, hm2] = ...
                TransTools.BuildSourceForwardModel(testCase.Labels(1:20), 5124);
            rng(1);
            other = randn(numel(rl2), 41);
            p = TransTools.InverseSolution(other, lf2, el2, hm2, 'mne', ...
                struct('RegParam', 0.05, 'Orientation', 'magnitude', ...
                       'Normals', TransTools.SurfaceNormals(sm2)));
            testCase.verifyEqual(size(p, 2), 41);
            testCase.verifyFalse(all(isnan(p(:))));
        end

        function theSecondCallIsSubstantiallyFaster(testCase)
        %THESECONDCALLISSUBSTANTIALLYFASTER  eLORETA, because its weighting
        %   is an iterative fixed-point solve and it is the one that hurts:
        %   3.85 s per call, repeated for every subject and bin before this.
        %   Loose bound on purpose, so a slow machine does not fail it.
            x = testCase.data(3, 1);
            o = testCase.opts('RegParam', 0.11);   % a key nothing else used

            t = tic; testCase.invert(x, 'eloreta', o); cold = toc(t);
            t = tic; testCase.invert(x, 'eloreta', o); warm = toc(t);

            testCase.assumeGreaterThan(cold, 0.5, ...
                'Machine too fast for this to be a meaningful comparison.');
            testCase.verifyLessThan(warm, cold / 5, ...
                'A cached eLORETA filter should not be within 5x of recomputing it.');
        end
    end
end
