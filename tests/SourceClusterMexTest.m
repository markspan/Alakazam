classdef SourceClusterMexTest < matlab.unittest.TestCase
%SOURCECLUSTERMEXTEST  The accelerated cluster path: that it is FASTER is
%   not the claim under test here, that it is IDENTICAL is.
%
%   The acceleration replaces FieldTrip's own TFCE with a compiled kernel,
%   reached by a route (correctm='max' plus a pre-enhancing statfun) that is
%   only legitimate if it reproduces correctm='tfce' exactly. That is an
%   algebraic claim about somebody else's code, so it is asserted against
%   that code rather than reasoned about: both routes run on the same data
%   under the same random seed, and the p-values must match.
%
%   Run with: runtests('tests/SourceClusterMexTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Transformations')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function theEdgeListJoinsSpaceAndTimeAndNothingElse(testCase)
        %THEEDGELISTJOINSSPACEANDTIMEANDNOTHINGELSE  Hand-checkable case: 3
        %   vertices in a line, 2 samples. Expect 3 temporal edges (each
        %   vertex to itself at the next sample) and 2 spatial edges per
        %   sample, so 7 in total, each listed once.
            connmat = [0 1 0; 1 0 1; 0 1 0];
            edges = TransTools.TfceEdges(connmat, [3 2]);

            testCase.verifyEqual(size(edges), [7 2]);
            testCase.verifyClass(edges, 'int32');
            % Undirected and unique: no edge appears in both orientations.
            both = sort(double(edges), 2);
            testCase.verifyEqual(size(unique(both, 'rows'), 1), 7);
            % Temporal edges join index v to v+3, one sample apart.
            temporal = both(both(:, 2) - both(:, 1) == 3, :);
            testCase.verifyEqual(size(temporal, 1), 3);
        end

        function anIsolatedPointScoresWhatTheFormulaSays(testCase)
        %ANISOLATEDPOINTSCORESWHATTHEFORMULASAYS  With no edges every active
        %   point is its own component of extent 1, so TFCE reduces to
        %   (1/(H+1)) * 1^E * v^(H+1), which is checkable by hand and pins
        %   the exponent convention the kernel implements.
            testCase.assumeTrue(TransTools.EnsureTfceMex(), 'No compiled TFCE kernel.');
            vals = [0; 2; 0; 3];
            edges = zeros(0, 2, 'int32');
            tfceE = 0.5; tfceH = 2;

            score = alakazam_tfce(vals, edges, tfceE, tfceH);

            expected = (1 / (tfceH + 1)) * (1 .^ tfceE) * (vals .^ (tfceH + 1));
            expected(vals <= 0) = 0;
            testCase.verifyEqual(score, expected, 'RelTol', 1e-12);
        end

        function poolingReproducesFieldTripsOwnArithmetic(testCase)
        %POOLINGREPRODUCESFIELDTRIPSOWNARITHMETIC  A split run's p-values
        %   must equal what the unsplit accumulation would have produced
        %   from the same permutation extremes. Brute-forced here with
        %   ft_statistics_montecarlo's own literal loop, including its +1,
        %   because this is the one place a parallel run could disagree with
        %   a serial one and still look entirely plausible.
            rng(5);
            statobs = randn(200, 1);
            counts  = [7 6 7];
            results = cell(1, 3);
            posAll = []; negAll = [];
            for k = 1:3
                pd = randn(1, counts(k)) + 1;
                nd = randn(1, counts(k)) - 1;
                results{k} = struct('stat', statobs, 'prob', zeros(200, 1), ...
                    'posdistribution', pd, 'negdistribution', nd);
                posAll = [posAll pd]; negAll = [negAll nd]; %#ok<AGROW>
            end
            cfg = struct('tail', 0, 'alpha', 0.05);

            stat = ClusterStats.poolMontecarlo(results, counts, cfg);

            testCase.verifyEqual(stat.prob, ...
                bruteForceProb(statobs, posAll, negAll), 'AbsTol', 1e-15);
        end

        function tiesBetweenObservedAndPermutedAreCountedCorrectly(testCase)
        %TIESBETWEENOBSERVEDANDPERMUTEDARECOUNTEDCORRECTLY  The pooled
        %   counts use sorted-edge lookups rather than the obvious loop, and
        %   half-open bins are exactly where such a substitution goes wrong.
        %   Ties are vanishingly rare with continuous statistics and are
        %   still the case worth pinning.
            statobs = [-1; 0; 1; 2];
            pd = [0 1 2];
            nd = [-1 0 1];
            results = {struct('stat', statobs, 'prob', zeros(4, 1), ...
                'posdistribution', pd, 'negdistribution', nd)};
            cfg = struct('tail', 0, 'alpha', 0.05);

            stat = ClusterStats.poolMontecarlo(results, 3, cfg);

            testCase.verifyEqual(stat.prob, ...
                bruteForceProb(statobs, pd, nd), 'AbsTol', 1e-15);
        end
    end

    methods (Test, TestTags = {'Slow'})
        function theAcceleratedRouteGivesIdenticalProbabilities(testCase)
        %THEACCELERATEDROUTEGIVESIDENTICALPROBABILITIES  The claim the whole
        %   substitution rests on. Same data, same seed, both routes.
            FieldTripFixtures.require(testCase);
            testCase.assumeTrue(TransTools.EnsureTfceMex(), 'No compiled TFCE kernel.');
            [tl, nb, connmat, nV, nSamp] = FieldTripFixtures.quietly(@() smallSourceData());

            base = struct('method', 'montecarlo', 'statistic', 'depsamplesT', ...
                'clusteralpha', 0.05, 'minnbchan', 0, 'neighbours', nb, 'tail', 0, ...
                'alpha', 0.05, 'numrandomization', 15, ...
                'design', [repmat(1:8, 1, 2); [ones(1, 8) 2 * ones(1, 8)]], ...
                'uvar', 1, 'ivar', 2, 'correcttail', 'alpha', ...
                'feedback', 'no', 'randomseed', 4242);

            a = base; a.correctm = 'tfce'; a.tfce_method = 'exact';
            b = base; b.correctm = 'max';  b.statistic = @ClusterStats.tfceStatfun;
            b.alakazamTfce = struct('base', 'depsamplesT', ...
                'edges', TransTools.TfceEdges(connmat, [nV nSamp]), 'E', 0.5, 'H', 2);

            sa = FieldTripFixtures.quietly(@() ft_timelockstatistics(a, tl{:}));
            sb = FieldTripFixtures.quietly(@() ft_timelockstatistics(b, tl{:}));

            testCase.verifyEqual(sb.prob, sa.prob, ...
                'The accelerated route must reproduce FieldTrip''s p-values exactly.');
            testCase.verifyEqual(sb.statraw, sa.stat, 'AbsTol', 1e-12);
            testCase.verifyEqual(sb.stat, sa.stattfce, 'RelTol', 1e-9);
        end

        function eachWorkerPermutesDifferently(testCase)
        %EACHWORKERPERMUTESDIFFERENTLY  The failure that would invalidate a
        %   parallel run while looking entirely healthy: identical seeds
        %   across chunks would make every worker draw the SAME
        %   permutations, so a "1000-permutation" null distribution would
        %   really hold N/K distinct values, K times over. Asserted on the
        %   returned distributions, which is where it would show.
            FieldTripFixtures.require(testCase);
            testCase.assumeTrue(TransTools.EnsureTfceMex(), 'No compiled TFCE kernel.');
            testCase.assumeFalse(isempty(ver('parallel')), 'No Parallel Computing Toolbox.');
            [tl, nb, connmat, nV, nSamp] = FieldTripFixtures.quietly(@() smallSourceData());

            cfg = struct('method', 'montecarlo', 'statistic', @ClusterStats.tfceStatfun, ...
                'correctm', 'max', 'clusteralpha', 0.05, 'minnbchan', 0, ...
                'neighbours', nb, 'tail', 0, 'alpha', 0.05, 'numrandomization', 8, ...
                'design', [repmat(1:8, 1, 2); [ones(1, 8) 2 * ones(1, 8)]], ...
                'uvar', 1, 'ivar', 2, 'correcttail', 'alpha', 'feedback', 'no', ...
                'randomseedBase', 1000, ...
                'alakazamTfce', struct('base', 'depsamplesT', ...
                    'edges', TransTools.TfceEdges(connmat, [nV nSamp]), 'E', 0.5, 'H', 2));

            stat = FieldTripFixtures.quietly(@() ClusterStats.runMontecarlo(cfg, tl, 2));

            pd = stat.posdistribution;
            testCase.assertNumElements(pd, 8);
            testCase.verifyNotEqual(pd(1:4), pd(5:8));
        end
    end
end

% ======================================================================= %
function prob = bruteForceProb(statobs, posAll, negAll)
%BRUTEFORCEPROB  ft_statistics_montecarlo's own accumulation, written out.
%   The literal loop is the reference the pooled shortcut has to match.
    prbPos = zeros(size(statobs));
    prbNeg = zeros(size(statobs));
    for i = 1:numel(posAll)
        prbPos = prbPos + (statobs < posAll(i));
        prbNeg = prbNeg + (statobs > negAll(i));
    end
    nRand = numel(posAll) + 1;
    prob = min((prbPos + 1) ./ nRand, (prbNeg + 1) ./ nRand);
end

function [tl, nb, connmat, nV, nSamp] = smallSourceData()
%SMALLSOURCEDATA  The coarsest template sheet, a short window, 8 subjects,
%   and a real effect in a patch so that clusters actually form.
    % Guarded because a previous test class may have torn the gifti reader
    % off the path -- see TransTools.EnsureGiftiReader.
    TransTools.EnsureGiftiReader();
    ftRoot = fileparts(which('ft_defaults'));
    sm = ft_convert_units(ft_read_headshape(fullfile(ftRoot, 'template', ...
        'sourcemodel', 'cortex_5124.surf.gii')), 'mm');
    [nb, labels, connmat] = TransTools.SourceNeighbours(sm);
    nV = numel(labels); nSamp = 7;
    rng(11);
    tl = cell(1, 16);
    for i = 1:16
        tl{i} = struct('label', {labels(:)}, 'time', linspace(0.25, 0.4, nSamp), ...
            'avg', randn(nV, nSamp), 'dimord', 'chan_time');
    end
    for i = 1:8
        tl{i}.avg(1:400, 2:5) = tl{i}.avg(1:400, 2:5) + 1.5;
    end
end
