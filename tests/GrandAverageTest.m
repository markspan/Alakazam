classdef GrandAverageTest < matlab.unittest.TestCase
%GRANDAVERAGETEST  Unit tests for src/GrandAverage.m's compatibility
%   errors, which are the part of it a user actually has to act on.
%
%   Every subject's Average is cached under a name made of the
%   transformation plus a timestamp, so reporting a mismatch as
%   "Average25225213" and "Average27224649" identifies nothing: in a
%   workspace holding more than one study those two may not even be the
%   same experiment. Each dataset carries the recording it came from as
%   EEG.setname, so the errors name both.
%
%   The error band is tested too: with trial-count weighting it has to be
%   the standard error of the weighted mean it is drawn around, which one
%   case pins by hand arithmetic and another by simulation, independently
%   of the formula in GrandAverage.
%
%   Run with: runtests('tests/GrandAverageTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'src')));
        end
    end

    methods (Test)
        function channelMismatchNamesBothRecordingAndAverage(testCase)
            files = testCase.writeSubjects( ...
                struct('setname', '12_N400_preprocessed', 'nbchan', 30, 'stem', 'Average25225213'), ...
                struct('setname', '11_P3_corrected',      'nbchan', 32, 'stem', 'Average27224649'));

            err = testCase.errorFrom(@() GrandAverage(files, false));

            testCase.verifySubstring(err.message, '11_P3_corrected / Average27224649');
            testCase.verifySubstring(err.message, '12_N400_preprocessed / Average25225213');
            testCase.verifySubstring(err.message, '32 channels');
        end

        function epochLengthMismatchIsAlsoNamed(testCase)
            files = testCase.writeSubjects( ...
                struct('setname', 'subjA', 'pnts', 50, 'stem', 'Average1'), ...
                struct('setname', 'subjB', 'pnts', 80, 'stem', 'Average2'));

            err = testCase.errorFrom(@() GrandAverage(files, false));

            testCase.verifySubstring(err.message, 'subjB / Average2');
            testCase.verifySubstring(err.message, 'subjA / Average1');
        end

        function binMismatchIsAlsoNamed(testCase)
            files = testCase.writeSubjects( ...
                struct('setname', 'subjA', 'bins', {{'Rare', 'Frequent'}}, 'stem', 'Average1'), ...
                struct('setname', 'subjB', 'bins', {{'Rare', 'Odd'}},      'stem', 'Average2'));

            err = testCase.errorFrom(@() GrandAverage(files, false));

            testCase.verifySubstring(err.message, 'subjB / Average2');
            testCase.verifySubstring(err.message, 'subjA / Average1');
        end

        function aDatasetWithoutASetnameFallsBackToTheFileStem(testCase)
        %ADATASETWITHOUTASETNAMEFALLSBACKTOTHEFILESTEM  setname can be
        %   absent or blank on a dataset built before it was set, or
        %   imported from a format that never had one. An error message
        %   must still name something rather than fail while being built.
            files = testCase.writeSubjects( ...
                struct('setname', '', 'nbchan', 30, 'stem', 'AverageOld'), ...
                struct('setname', '', 'nbchan', 32, 'stem', 'AverageNewer'));

            err = testCase.errorFrom(@() GrandAverage(files, false));

            testCase.verifySubstring(err.message, 'AverageNewer');
            testCase.verifySubstring(err.message, 'AverageOld');
            testCase.verifyEmpty(strfind(err.message, ' / '));
        end

        function filenameStandsInWhenSetnameIsBlank(testCase)
            files = testCase.writeSubjects( ...
                struct('setname', '', 'filename', 'sub01.set', 'nbchan', 30, 'stem', 'Average1'), ...
                struct('setname', '', 'filename', 'sub02.set', 'nbchan', 32, 'stem', 'Average2'));

            err = testCase.errorFrom(@() GrandAverage(files, false));

            testCase.verifySubstring(err.message, 'sub02 / Average2');
            testCase.verifySubstring(err.message, 'sub01 / Average1');
        end

        % ---- the error band ----------------------------------------------
        function withoutWeightingTheBandIsThePlainSem(testCase)
        %WITHOUTWEIGHTINGTHEBANDISTHEPLAINSEM  std / sqrt(N) across the
        %   subjects, whatever their trial counts.
            testCase.seed(1);
            [files, data] = testCase.randomSubjects([10 20 30 40]);
            EEG = GrandAverage(files, false);
            testCase.verifyEqual(EEG.data, mean(data, 4), 'AbsTol', 1e-12);
            testCase.verifyEqual(EEG.stErr, std(data, 0, 4) / 2, 'AbsTol', 1e-12);
        end

        function equalTrialCountsGiveThePlainSemWhenWeightedToo(testCase)
            testCase.seed(2);
            [files, data] = testCase.randomSubjects([25 25 25]);
            EEG = GrandAverage(files, true);
            testCase.verifyEqual(EEG.stErr, std(data, 0, 4) / sqrt(3), 'AbsTol', 1e-12);
        end

        function theWeightedBandWorkedByHand(testCase)
        %THEWEIGHTEDBANDWORKEDBYHAND  Three subjects at 0, 3 and 6 uV with
        %   1, 1 and 2 trials: weights 1/4, 1/4 and 1/2, and a mean of 3.75.
        %   The weighted variance is (14.0625/4 + 0.5625/4 + 5.0625/2) /
        %   (1 - 3/8) = 9.9 and the standard error is sqrt(9.9 * 3/8).
            files = testCase.writeSubjects( ...
                struct('stem', 'A', 'value', 0, 'n', 1), ...
                struct('stem', 'B', 'value', 3, 'n', 1), ...
                struct('stem', 'C', 'value', 6, 'n', 2));
            EEG = GrandAverage(files, true);
            testCase.verifyEqual(EEG.data, repmat(3.75, size(EEG.data)), 'AbsTol', 1e-12);
            testCase.verifyEqual(EEG.stErr, repmat(sqrt(3.7125), size(EEG.stErr)), 'AbsTol', 1e-12);
        end

        function theWeightedBandIsTheSpreadOfTheWeightedMean(testCase)
        %THEWEIGHTEDBANDISTHESPREADOFTHEWEIGHTEDMEAN  What the band claims,
        %   checked by simulation rather than by the formula: every channel
        %   x sample x bin is a fresh draw of five subjects with a standard
        %   deviation of 1, weighted 1:2:3:4:10. Across the draws, the
        %   weighted mean's own variance and the mean squared band must both
        %   be sum(w.^2) = 0.325; the plain SEM would average 1/5 = 0.2.
            testCase.seed(3);
            counts = [1 2 3 4 10];
            [files, data] = testCase.randomSubjects(counts, 8, 2000);
            EEG = GrandAverage(files, true);

            target = sum((counts / sum(counts)) .^ 2);
            testCase.verifyEqual(var(EEG.data(:)), target, 'RelTol', 0.05, ...
                'The weighted mean varies by this much from draw to draw.');
            testCase.verifyEqual(mean(EEG.stErr(:) .^ 2), target, 'RelTol', 0.05, ...
                'The band says so.');
            plain = std(data, 0, 4) / sqrt(numel(counts));
            testCase.verifyLessThan(mean(plain(:) .^ 2), 0.25, ...
                'The plain SEM would have drawn it too narrow, so the check is not vacuous.');
        end

        function aCombinationBinKeepsThePlainSemWhenWeighted(testCase)
        %ACOMBINATIONBINKEEPSTHEPLAINSEMWHENWEIGHTED  A difference bin has
        %   no trial count, so its mean and band fall back to equal weights:
        %   3 uV and std([0 3 6]) / sqrt(3) = sqrt(3), beside the weighted
        %   bin of the hand-worked case.
            files = testCase.writeSubjects( ...
                struct('stem', 'A', 'value', 0, 'n', {{1, 'combination'}}), ...
                struct('stem', 'B', 'value', 3, 'n', {{1, 'combination'}}), ...
                struct('stem', 'C', 'value', 6, 'n', {{2, 'combination'}}));
            EEG = GrandAverage(files, true);
            testCase.verifyEqual(EEG.stErr(:, :, 1), repmat(sqrt(3.7125), size(EEG.stErr, 1:2)), 'AbsTol', 1e-12);
            testCase.verifyEqual(EEG.data(:, :, 2), repmat(3, size(EEG.data, 1:2)), 'AbsTol', 1e-12);
            testCase.verifyEqual(EEG.stErr(:, :, 2), repmat(sqrt(3), size(EEG.stErr, 1:2)), 'AbsTol', 1e-12);
        end

        function thePooledAsmeUsesTheSameWeights(testCase)
        %THEPOOLEDASMEUSESTHESAMEWEIGHTS  SMEs of 1, 2 and 3 uV with 1, 1
        %   and 2 trials: sqrt(1/16 + 4/16 + 9/4) = sqrt(2.5625) weighted,
        %   sqrt(1 + 4 + 9) / 3 without.
            files = testCase.writeSubjects( ...
                struct('stem', 'A', 'n', 1, 'aSME', 1), ...
                struct('stem', 'B', 'n', 1, 'aSME', 2), ...
                struct('stem', 'C', 'n', 2, 'aSME', 3));
            weighted = GrandAverage(files, true);
            plain = GrandAverage(files, false);
            testCase.verifyEqual(weighted.aSME, repmat(sqrt(2.5625), size(weighted.aSME)), 'AbsTol', 1e-12);
            testCase.verifyEqual(plain.aSME, repmat(sqrt(14) / 3, size(plain.aSME)), 'AbsTol', 1e-12);
        end
    end

    % ==================================================================== %
    methods
        function err = errorFrom(testCase, fcn)
        %ERRORFROM  The MException FCN throws, so its message can be
        %   asserted on. verifyError checks the identifier but returns no
        %   exception, and the whole point here is the wording.
            err = [];
            try
                fcn();
            catch caught
                err = caught;
            end
            testCase.assertNotEmpty(err, 'Expected a compatibility error, but none was thrown.');
            testCase.verifyEqual(err.identifier, 'Alakazam:GrandAverage');
        end

        function files = writeSubjects(testCase, varargin)
        %WRITESUBJECTS  Save one .mat per spec into a temp folder and return
        %   their paths. GrandAverage loads from disk, so the fixtures have
        %   to be real files; the stem is what ends up in the message.
            folder = fullfile(tempname());
            mkdir(folder);
            testCase.addTeardown(@() rmdir(folder, 's'));

            files = cell(1, numel(varargin));
            for i = 1:numel(varargin)
                spec = varargin{i};
                EEG = testCase.averagedSubject(spec);
                files{i} = fullfile(folder, [spec.stem '.mat']);
                save(files{i}, 'EEG');
            end
        end

        function [files, data] = randomSubjects(testCase, counts, nbchan, pnts)
        %RANDOMSUBJECTS  One subject of independent standard-normal values
        %   per trial count in COUNTS, written to disk, and their data
        %   stacked as nchan x npnts x nbin x nsubjects.
            if nargin < 3
                nbchan = 4;
                pnts = 50;
            end
            specs = cell(1, numel(counts));
            data = zeros(nbchan, pnts, 2, numel(counts));
            for s = 1:numel(counts)
                data(:, :, :, s) = randn(nbchan, pnts, 2);
                specs{s} = struct('stem', sprintf('Average%d', s), 'nbchan', nbchan, ...
                    'pnts', pnts, 'n', counts(s), 'data', data(:, :, :, s));
            end
            files = testCase.writeSubjects(specs{:});
        end

        function seed(testCase, n)
        %SEED  Seed the generator for this test and restore it afterwards.
            previous = rng(n);
            testCase.addTeardown(@rng, previous);
        end

        function EEG = averagedSubject(~, spec)
        %AVERAGEDSUBJECT  An Averaged dataset from SPEC: random data unless
        %   SPEC gives 'data' or a constant 'value'; 'n' is every bin's trial
        %   count, or a cell with one per bin; 'aSME' a constant SME.
            nbchan = getOr(spec, 'nbchan', 4);
            pnts   = getOr(spec, 'pnts', 50);
            bins   = getOr(spec, 'bins', {'Rare', 'Frequent'});
            counts = getOr(spec, 'n', 20);
            if ~iscell(counts)
                counts = repmat({counts}, 1, numel(bins));
            end

            EEG = struct();
            EEG.setname    = getOr(spec, 'setname', '');
            if isfield(spec, 'filename')
                EEG.filename = spec.filename;
            end
            EEG.DataFormat = 'Averaged';
            EEG.trials     = 1;
            EEG.srate      = 250;
            EEG.times      = (0:pnts - 1) / 250 * 1000;
            EEG.nbchan     = nbchan;
            EEG.chanlocs   = struct('labels', arrayfun(@(k) sprintf('Ch%d', k), ...
                1:nbchan, 'UniformOutput', false));
            if isfield(spec, 'data')
                EEG.data = spec.data;
            elseif isfield(spec, 'value')
                EEG.data = repmat(spec.value, nbchan, pnts, numel(bins));
            else
                EEG.data = randn(nbchan, pnts, numel(bins));
            end
            EEG.stErr = abs(randn(nbchan, pnts, numel(bins)));
            EEG.bindesc = struct('label', bins, ...
                'index', num2cell(1:numel(bins)), 'n', counts);
            if isfield(spec, 'aSME')
                EEG.aSME = repmat(spec.aSME, nbchan, numel(bins));
            end
        end
    end
end

function value = getOr(s, name, default)
    if isfield(s, name) && ~isempty(s.(name))
        value = s.(name);
    else
        value = default;
    end
end
