classdef AutoEyeICACacheTest < matlab.unittest.TestCase
%AUTOEYEICACACHETEST  AutoEyeICA reuses a decomposition it has already made for
%   the same data, so changing the eye threshold prunes rather than decomposes.
%
%   ICA is the one step of the RIFT chain that varies by an order of magnitude
%   between recordings (13 s typically, 111 s on one of ten) and is not
%   reproducible: nothing seeds it, so a second run on the same data gives
%   different components. The decomposition and ICLabel's classification do not
%   depend on the eye threshold, so they are kept (TransTools.IcaCache, and on
%   the node under etc.alz.eyeICA.decomposition) and only the pruning is redone.
%
%   Needs EEGLAB with FastICA and ICLabel, as DimigenRiftTemplateTest does, and is
%   skipped where they are missing (without FastICA AutoEyeICA opens pop_runica's
%   own dialog, which a test cannot answer).
%
%   Run with: runtests('tests/AutoEyeICACacheTest.m').
%
%   See also AUTOEYEICA, TRANSTOOLS.ICACACHE, TRANSTOOLS.DATAKEY.

    methods (TestClassSetup)
        function addSourceToPathAndCheckTools(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'src')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations'), 'IncludeSubfolders', true));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'src', 'Support')));
            try
                EEGLabEnvironment.ensure();
            catch
                % The assumptions below say exactly what is missing.
            end
            testCase.assumeTrue(~isempty(which('pop_select')), 'EEGLAB is not available.');
            testCase.assumeTrue(~isempty(which('fastica')), ...
                'FastICA is not available; AutoEyeICA would open pop_runica''s own dialog.');
            testCase.assumeTrue(~isempty(which('iclabel')), 'ICLabel is not available.');
        end
    end

    methods (TestMethodSetup)
        function emptyTheCache(~)
            TransTools.IcaCache('clear');
        end
    end

    methods (Test)
        function aSecondRunOnTheSameDataReusesTheDecompositionAndOnlyRePrunes(testCase)
            EEG = testCase.recording();

            first = AutoEyeICA(EEG, struct('EyeThreshold', 0.99));
            testCase.verifyEqual(TransTools.IcaCache('hits'), 0, 'The first run has nothing to reuse.');
            second = AutoEyeICA(EEG, struct('EyeThreshold', 0.2));

            testCase.verifyEqual(TransTools.IcaCache('hits'), 1, ...
                'Changing only the threshold must be answered from the cache.');
            a = first.etc.alz.eyeICA.decomposition;
            b = second.etc.alz.eyeICA.decomposition;
            testCase.verifyEqual(b.icaweights, a.icaweights, ...
                ['Different weights mean ICA ran again: it is not seeded, so a fresh ' ...
                 'decomposition of the same data would not match.']);

            % Each result prunes exactly what its own threshold asks of the SAME
            % classification.
            classes = a.etc.ic_classification.ICLabel.classes;
            probs = a.etc.ic_classification.ICLabel.classifications;
            eyeCol = find(strcmpi(classes, 'Eye'), 1);
            testCase.verifyEqual(first.etc.alz.eyeICA.removed, find(probs(:, eyeCol) > 0.99)');
            testCase.verifyEqual(second.etc.alz.eyeICA.removed, find(probs(:, eyeCol) > 0.2)');
            testCase.verifyEqual(second.etc.alz.eyeICA.nComponents, size(probs, 1));
        end

        function pruningFromTheCacheRemovesExactlyTheComponentsAskedFor(testCase)
        %PRUNINGFROMTHECACHEREMOVESEXACTLYTHECOMPONENTSASKEDFOR  On this synthetic data
        %   ICLabel finds no eye components at any sensible threshold, so the test above
        %   prunes nothing. Here the threshold is the median of the eye probabilities, so
        %   about half the components go, and the pruned data is compared with the data
        %   minus those components' own projection, computed independently from the
        %   stored weights.
            EEG = testCase.recording();
            first = AutoEyeICA(EEG, struct('EyeThreshold', 0.99));    % prunes nothing
            d = first.etc.alz.eyeICA.decomposition;
            probs = d.etc.ic_classification.ICLabel.classifications;
            eyeCol = find(strcmpi(d.etc.ic_classification.ICLabel.classes, 'Eye'), 1);
            threshold = median(probs(:, eyeCol));

            pruned = AutoEyeICA(EEG, struct('EyeThreshold', threshold));

            testCase.verifyEqual(TransTools.IcaCache('hits'), 1, 'The pruning should come from the cache.');
            removed = pruned.etc.alz.eyeICA.removed;
            testCase.assertNotEmpty(removed);
            testCase.assertLessThan(numel(removed), size(probs, 1));
            testCase.verifyEqual(removed, find(probs(:, eyeCol) > threshold)');
            testCase.verifyEqual(size(pruned.icaweights, 1), size(probs, 1) - numel(removed), ...
                'The weights that remain describe the components that survive.');

            before = double(first.data(d.icachansind, :));
            activations = (d.icaweights * d.icasphere) * before;
            expected = before - d.icawinv(:, removed) * activations(removed, :);
            testCase.verifyEqual(double(pruned.data(d.icachansind, :)), expected, ...
                'AbsTol', 1e-3 * max(abs(expected(:))));
        end

        function aDecompositionPrimedFromAStoredNodeIsUsedInALaterSession(testCase)
        %ADECOMPOSITIONPRIMEDFROMASTOREDNODEISUSEDINALATERSESSION  Recalculate hands
        %   the decomposition kept on the node to the session cache; it is found
        %   again by the hash of the data, so it serves this data and no other.
            EEG = testCase.recording();
            first = AutoEyeICA(EEG, struct('EyeThreshold', 0.99));
            stored = first.etc.alz.eyeICA.decomposition;

            TransTools.IcaCache('clear');                % a new session
            TransTools.IcaCache('put', stored.key, stored);
            again = AutoEyeICA(EEG, struct('EyeThreshold', 0.5));

            testCase.verifyEqual(TransTools.IcaCache('hits'), 1);
            testCase.verifyEqual(again.etc.alz.eyeICA.decomposition.icaweights, stored.icaweights);

            other = EEG;
            other.data = other.data * 1.01;              % different data, same channels
            AutoEyeICA(other, struct('EyeThreshold', 0.5));
            testCase.verifyEqual(TransTools.IcaCache('hits'), 1, ...
                'A decomposition must not be reused for data it was not computed from.');
        end

        function redecomposeForcesAFreshDecomposition(testCase)
            EEG = testCase.recording();
            first = AutoEyeICA(EEG, struct('EyeThreshold', 0.99));

            forced = AutoEyeICA(EEG, struct('EyeThreshold', 0.99, 'Redecompose', true));

            testCase.verifyEqual(TransTools.IcaCache('hits'), 0);
            testCase.verifyNotEqual(forced.etc.alz.eyeICA.decomposition.icaweights, ...
                first.etc.alz.eyeICA.decomposition.icaweights);
        end
    end

    methods (Access = private)
        function EEG = recording(~)
        %RECORDING  Sixteen 10-5 channels of mixed super-Gaussian sources: enough
        %   independent structure for FastICA to converge, and named so that
        %   AutoEyeICA finds template positions for every channel.
            rng(4);
            labels = {'Fz', 'Cz', 'Pz', 'Oz', 'C3', 'C4', 'F3', 'F4', 'P3', 'P4', ...
                      'O1', 'O2', 'T7', 'T8', 'FC1', 'FC2'};
            n = numel(labels);
            nT = 6000;
            sources = sign(randn(n, nT)) .* (-log(rand(n, nT)));
            EEG = eeg_emptyset();
            EEG.data = single(5 * randn(n) * sources);
            EEG.srate = 250;
            EEG.nbchan = n;
            EEG.pnts = nT;
            EEG.trials = 1;
            EEG.xmin = 0;
            EEG.xmax = (nT - 1) / EEG.srate;
            EEG.chanlocs = struct('labels', labels);
            EEG = eeg_checkset(EEG);
            EEG.File = fullfile(tempdir, 'aut_recording.mat');
            EEG.DataFormat = 'CONTINUOUS';
            EEG.times = (0:nT - 1) / EEG.srate;
        end
    end
end
