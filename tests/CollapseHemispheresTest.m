classdef CollapseHemispheresTest < matlab.unittest.TestCase
%COLLAPSEHEMISPHERESTEST  Contralateral and ipsilateral waveforms.
%
%   THE ANCHOR CASE is agreementWithTheComposedRoute. Alakazam can already
%   produce the contra-minus-ipsi DIFFERENCE by composing DeriveChannels
%   with a coefficient-weighted bin operation, and that composition was
%   checked against ERPLAB's own BinOps_Contra on Luck chapter 10 subject 1,
%   agreeing to 6.7e-15 uV (see Docs/luck.md). So the strongest available
%   test of this transform is that its Contra minus its Ipsi reproduces that
%   same already-validated quantity, which ties the new code to a published
%   reference rather than to my own arithmetic.
%
%   Run with: runtests('tests/CollapseHemispheresTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Transformations', 'CollapseHemispheres'), ...
                     fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        % --- the arithmetic ---------------------------------------------- %
        function contraAndIpsiFollowErplabsOwnExpression(testCase)
        %CONTRAANDIPSIFOLLOWERPLABSOWNEXPRESSION  contra = (b1@RH + b2@LH)/2
        %   with b1 the left-side bin, computed by hand from the fixture.
            EEG = testCase.averagedFixture();
            [L, R] = testCase.pairIndices(EEG);

            out = CollapseHemispheres(EEG, testCase.options());

            contra = testCase.binData(out, 'Contra');
            ipsi   = testCase.binData(out, 'Ipsi');
            testCase.verifyEqual(contra(L, :), ...
                (EEG.data(R, :, 1) + EEG.data(L, :, 2)) / 2, 'AbsTol', 1e-12);
            testCase.verifyEqual(ipsi(L, :), ...
                (EEG.data(L, :, 1) + EEG.data(R, :, 2)) / 2, 'AbsTol', 1e-12);
        end

        function agreementWithTheComposedRoute(testCase)
        %AGREEMENTWITHTHECOMPOSEDROUTE  contra - ipsi must equal
        %   (lat(b1) - lat(b2))/2 with lat = right - left, which is the
        %   composition Docs/luck.md records agreeing with ERPLAB's
        %   BinOps_Contra to 6.7e-15 uV. If this transform and that identity
        %   disagree, one of them is wrong and it is not the published one.
            EEG = testCase.averagedFixture();
            [L, R] = testCase.pairIndices(EEG);

            out = CollapseHemispheres(EEG, testCase.options());

            contra = testCase.binData(out, 'Contra');
            ipsi   = testCase.binData(out, 'Ipsi');
            difference = contra(L, :) - ipsi(L, :);
            lat1 = EEG.data(R, :, 1) - EEG.data(L, :, 1);
            lat2 = EEG.data(R, :, 2) - EEG.data(L, :, 2);
            testCase.verifyEqual(difference, (lat1 - lat2) / 2, 'AbsTol', 1e-12);
        end

        function bothElectrodesOfAPairCarryTheSameCollapsedWaveform(testCase)
        %BOTHELECTRODESOFAPAIRCARRYTHESAMECOLLAPSEDWAVEFORM  There is one
        %   contra waveform per pair, and it is written to both members so
        %   the montage survives. Measuring at either gives the same answer,
        %   which is what lets an existing Measure window keep working.
            EEG = testCase.averagedFixture();
            [L, R] = testCase.pairIndices(EEG);

            contra = testCase.binData(CollapseHemispheres(EEG, testCase.options()), 'Contra');

            testCase.verifyEqual(contra(L, :), contra(R, :), 'AbsTol', 1e-12);
        end

        function aMidlineChannelCarriesThePlainTwoSideMean(testCase)
        %AMIDLINECHANNELCARRIESTHEPLAINTWOSIDEMEAN  Cz has no laterality to
        %   collapse, and contra and ipsi both reduce to the mean of the two
        %   sides there. Leaving it NaN would break every downstream step
        %   for a channel about which nothing is wrong.
            EEG = testCase.averagedFixture();
            mid = find(strcmp({EEG.chanlocs.labels}, 'Cz'));
            testCase.assertNotEmpty(mid);

            out = CollapseHemispheres(EEG, testCase.options());

            expected = (EEG.data(mid, :, 1) + EEG.data(mid, :, 2)) / 2;
            contra = testCase.binData(out, 'Contra');
            ipsi   = testCase.binData(out, 'Ipsi');
            testCase.verifyEqual(contra(mid, :), expected, 'AbsTol', 1e-12);
            testCase.verifyEqual(ipsi(mid, :), expected, 'AbsTol', 1e-12);
        end

        function eachSideIsAveragedBeforeTheTwoSidesAre(testCase)
        %EACHSIDEISAVERAGEDBEFORETHETWOSIDESARE  Two bins on the left and
        %   one on the right must still weigh the sides equally, or a design
        %   that happens to split one side into more conditions would tilt
        %   the collapse toward it.
            EEG = testCase.averagedFixture(3);
            [L, R] = testCase.pairIndices(EEG);
            opts = testCase.options();
            opts.leftBins = {'Left', 'AlsoLeft'};

            contra = testCase.binData(CollapseHemispheres(EEG, opts), 'Contra');

            meanLeftSide = mean(EEG.data(R, :, [1 3]), 3);
            testCase.verifyEqual(contra(L, :), (meanLeftSide + EEG.data(L, :, 2)) / 2, ...
                'AbsTol', 1e-12);
        end

        function standardErrorsPropagateAsTheRootOfSquaredErrors(testCase)
        %STANDARDERRORSPROPAGATEASTHEROOTOFSQUAREDERRORS  The same
        %   convention Average.m uses for its own combination bins, so an
        %   error band drawn on a Contra waveform means what it does
        %   everywhere else in the app.
            EEG = testCase.averagedFixture();
            [L, R] = testCase.pairIndices(EEG);

            out = CollapseHemispheres(EEG, testCase.options());

            contraBin = find(strcmp(testCase.binLabels(out), 'Contra'));
            expected = sqrt((EEG.stErr(R, :, 1) / 2) .^ 2 + (EEG.stErr(L, :, 2) / 2) .^ 2);
            testCase.verifyEqual(out.stErr(L, :, contraBin), expected, 'AbsTol', 1e-12);
        end

        % --- shape and idempotency --------------------------------------- %
        function theMontageIsUnchanged(testCase)
            EEG = testCase.averagedFixture();

            out = CollapseHemispheres(EEG, testCase.options());

            testCase.verifyEqual(size(out.data, 1), size(EEG.data, 1));
            testCase.verifyEqual({out.chanlocs.labels}, {EEG.chanlocs.labels});
        end

        function twoBinsAreAddedAndEverySliceGrowsWithThem(testCase)
        %TWOBINSAREADDEDANDEVERYSLICEGROWSWITHTHEM  A dataset whose data has
        %   more bins than its bindesc, stErr or aSME is one that breaks
        %   somewhere downstream rather than here.
            EEG = testCase.averagedFixture();

            out = CollapseHemispheres(EEG, testCase.options());

            testCase.verifyEqual(size(out.data, 3), size(EEG.data, 3) + 2);
            testCase.verifyEqual(numel(out.bindesc), numel(EEG.bindesc) + 2);
            testCase.verifyEqual(size(out.stErr, 3), size(out.data, 3));
            testCase.verifyEqual(size(out.aSME, 2), size(out.data, 3));
            testCase.verifyEqual(testCase.binLabels(out), ...
                [testCase.binLabels(EEG), {'Contra', 'Ipsi'}]);
        end

        function theNewBinsGetIndicesOfTheirOwn(testCase)
            out = CollapseHemispheres(testCase.averagedFixture(), testCase.options());

            idx = [out.bindesc.index];
            testCase.verifyEqual(numel(unique(idx)), numel(idx), ...
                'A repeated bin index would make bin arithmetic ambiguous.');
        end

        function runningItTwiceReplacesRatherThanAccumulates(testCase)
        %RUNNINGITTWICEREPLACESRATHERTHANACCUMULATES  Recalculate and
        %   template replay both re-run the transform on the same input, and
        %   a second Contra bin stacked on the first is the failure mode
        %   DeriveChannels had to solve the same way.
            EEG = testCase.averagedFixture();
            opts = testCase.options();

            once  = CollapseHemispheres(EEG, opts);
            twice = CollapseHemispheres(once, opts);

            testCase.verifyEqual(testCase.binLabels(twice), testCase.binLabels(once));
            testCase.verifyEqual(twice.data, once.data, 'AbsTol', 1e-12);
        end

        function theBinsCanBeNamedSomethingElse(testCase)
            opts = testCase.options();
            opts.contraLabel = 'N2pc contra';
            opts.ipsiLabel   = 'N2pc ipsi';

            out = CollapseHemispheres(testCase.averagedFixture(), opts);

            testCase.verifyTrue(ismember('N2pc contra', testCase.binLabels(out)));
            testCase.verifyTrue(ismember('N2pc ipsi', testCase.binLabels(out)));
        end

        % --- refusals ---------------------------------------------------- %
        function unaveragedDataIsRefusedWithAnExplanation(testCase)
            EEG = makeTestEEG('trials', 4);
            testCase.verifyError(@() CollapseHemispheres(EEG, testCase.options()), ...
                'Alakazam:CollapseHemispheres');
        end

        function aSingleBinIsRefused(testCase)
            EEG = testCase.averagedFixture();
            EEG.data = EEG.data(:, :, 1);
            EEG.bindesc = EEG.bindesc(1);
            testCase.verifyError(@() CollapseHemispheres(EEG, testCase.options()), ...
                'Alakazam:CollapseHemispheres');
        end

        function aBinNamedInTheOptionsButAbsentFromTheDataIsRefusedByName(testCase)
        %ABINNAMEDINTHEOPTIONSBUTABSENTFROMTHEDATAISREFUSEDBYNAME  Options
        %   name bins rather than numbering them precisely so that replaying
        %   a template onto a dataset whose bins differ either works or says
        %   what it wanted, instead of collapsing the wrong two conditions.
            opts = testCase.options();
            opts.leftBins = {'Leftish'};

            message = '';
            try
                CollapseHemispheres(testCase.averagedFixture(), opts);
            catch err
                testCase.verifyEqual(err.identifier, 'Alakazam:CollapseHemispheres');
                message = err.message;
            end
            testCase.assertNotEmpty(message, 'It should have refused this at all.');
            testCase.verifyTrue(contains(message, 'Leftish'), ...
                'The message has to name the bin it wanted, or it cannot be acted on.');
        end

        function oneSideWithNoBinsIsRefused(testCase)
            opts = testCase.options();
            opts.rightBins = {};
            testCase.verifyError(@() CollapseHemispheres( ...
                testCase.averagedFixture(), opts), 'Alakazam:CollapseHemispheres');
        end

        function thesameBinOnASideTwiceIsRefused(testCase)
        %THESAMEBINONASIDETWICEISREFUSED  It would weight that bin double
        %   and the result would look perfectly ordinary.
            opts = testCase.options();
            opts.leftBins = {'Left', 'Left'};
            testCase.verifyError(@() CollapseHemispheres( ...
                testCase.averagedFixture(), opts), 'Alakazam:CollapseHemispheres');
        end

        function twoBinsWithTheSameNameIsRefused(testCase)
            opts = testCase.options();
            opts.ipsiLabel = opts.contraLabel;
            testCase.verifyError(@() CollapseHemispheres( ...
                testCase.averagedFixture(), opts), 'Alakazam:CollapseHemispheres');
        end

        function aMontageWithNoPairsIsRefusedRatherThanSilentlyEmpty(testCase)
        %AMONTAGEWITHNOPAIRSISREFUSEDRATHERTHANSILENTLYEMPTY  An
        %   unpositioned equidistant montage pairs nothing, and a Contra bin
        %   that is really just the two-side mean everywhere would look like
        %   a result.
        %   Note the labels: "E1".."E4" would NOT do, because the 10-20
        %   odd/even rule pairs them quite correctly. They have to be names
        %   no convention can read, which is what an unpositioned montage of
        %   arbitrary sensor names actually looks like.
            EEG = testCase.averagedFixture();
            names = {'alpha', 'beta', 'gamma', 'delta'};
            for k = 1:numel(EEG.chanlocs)
                EEG.chanlocs(k).labels = names{k};
                EEG.chanlocs(k).X = [];
                EEG.chanlocs(k).Y = [];
                EEG.chanlocs(k).Z = [];
            end

            testCase.verifyError(@() CollapseHemispheres(EEG, testCase.options()), ...
                'Alakazam:CollapseHemispheres');
        end
    end

    methods (Access = private)
        function EEG = averagedFixture(testCase, nBins)
        %AVERAGEDFIXTURE  An averaged dataset with one lateral pair, a
        %   midline channel and a peripheral, and a deterministic waveform
        %   per channel and bin so every expectation can be computed rather
        %   than approximated.
            if nargin < 2
                nBins = 2;
            end
            labels = {'PO7', 'PO8', 'Cz', 'HEOG'};
            nChan = numel(labels);
            nPnts = 12;

            EEG = struct();
            EEG.chanlocs = struct('labels', labels, ...
                'X', {-70, -70, 0, 80}, 'Y', {45, -45, 0, 60}, 'Z', {20, 20, 90, -10});
            EEG.srate = 250;
            EEG.nbchan = nChan;
            EEG.pnts = nPnts;
            EEG.times = (0:nPnts - 1) * 4;
            EEG.trials = 1;
            EEG.DataFormat = 'Averaged';
            EEG.DataType = 'TimeDomain';

            t = (1:nPnts) / nPnts;
            EEG.data  = zeros(nChan, nPnts, nBins);
            EEG.stErr = zeros(nChan, nPnts, nBins);
            EEG.aSME  = zeros(nChan, nBins);
            for b = 1:nBins
                for c = 1:nChan
                    EEG.data(c, :, b)  = c + 10 * b + sin(2 * pi * (t + 0.1 * c * b));
                    EEG.stErr(c, :, b) = 0.1 * c + 0.01 * b;
                    EEG.aSME(c, b)     = 0.2 * c + 0.02 * b;
                end
            end

            names = {'Left', 'Right', 'AlsoLeft', 'AlsoRight'};
            EEG.bindesc = struct('label', {}, 'index', {}, 'n', {}, 'trials', {});
            for b = 1:nBins
                EEG.bindesc(b) = struct('label', names{b}, 'index', b, ...
                    'n', 100 + b, 'trials', []);
            end
            testCase.assertEqual(numel(EEG.bindesc), nBins);
        end

        function opts = options(~)
            opts = struct('leftBins', {{'Left'}}, 'rightBins', {{'Right'}}, ...
                'pairing', 'auto', 'contraLabel', 'Contra', 'ipsiLabel', 'Ipsi');
        end

        function [L, R] = pairIndices(~, EEG)
            labels = {EEG.chanlocs.labels};
            L = find(strcmp(labels, 'PO7'));
            R = find(strcmp(labels, 'PO8'));
        end

        function labels = binLabels(~, EEG)
            labels = arrayfun(@(b) char(string(b.label)), EEG.bindesc(:)', ...
                'UniformOutput', false);
        end

        function d = binData(testCase, EEG, label)
            k = find(strcmp(testCase.binLabels(EEG), label), 1);
            testCase.assertNotEmpty(k, sprintf('No bin called "%s".', label));
            d = EEG.data(:, :, k);
        end
    end
end
