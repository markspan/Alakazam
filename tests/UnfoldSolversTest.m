classdef UnfoldSolversTest < matlab.unittest.TestCase
%UNFOLDSOLVERSTEST  The toolbox's other ways to fit a bin plan: MATLAB's
%   exact solver and glmnet's regularised one in place of lsmr, and a
%   regression on epochs (uf_epoch, uf_glmfit_nodc) in place of a
%   deconvolution (Unfold.fitBins' Solver, GlmnetAlpha, OverlapCorrection).
%
%   Each is held to what it should give: the exact solver lsmr's answer on a
%   design lsmr can solve; lasso exact zeros, ridge something other than
%   least squares; and, on epochs, with y ~ 1, a bin's mean of its epochs,
%   built here by hand with Unfold's rounding of each latency.
%
%   They need the Unfold toolbox and skip cleanly without it.
%
%   Run with: runtests('tests/UnfoldSolversTest.m').
%
%   See also UNFOLD.FITBINS, UNFOLDBINSTEST, UNFOLDCOVARIATESTEST.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Support'), fullfile(root, 'tests')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (TestMethodSetup)
        function requireUnfold(testCase)
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
        end
    end

    methods (Test)
        % ---- the solvers ---------------------------------------------------- %
        function theExactSolverGivesLsmrsAnswer(testCase)
        %THEEXACTSOLVERGIVESLSMRSANSWER  On a design lsmr solves, MATLAB's
        %   own exact solver ('matlab') finds the same waveforms. The
        %   responses, at a fixed lag to the Frequent events, are left out,
        %   since the pair has no single answer.
            EEG = UnfoldBinsTest.recording();
            args = {'WindowMs', UnfoldBinsTest.WindowMs, 'ArtifactThresholdUv', 0, 'OtherEvents', {}};

            lsmr = Unfold.fitBins(EEG, args{:});
            [exact, info] = Unfold.fitBins(EEG, args{:}, 'Solver', 'matlab');

            testCase.verifyEqual(exact.data, lsmr.data, 'AbsTol', 1e-6);
            testCase.verifyEqual(info.solver, 'matlab');
        end

        function glmnetRegularises(testCase)
        %GLMNETREGULARISES  Lasso, glmnet's default (alpha 1), sets betas
        %   to exactly zero where the response is nothing but noise, which
        %   least squares never does; ridge (alpha 0) zeroes nothing but is
        %   not the least-squares fit either.
            EEG = UnfoldBinsTest.recording();
            args = {'WindowMs', UnfoldBinsTest.WindowMs, 'ArtifactThresholdUv', 0, 'OtherEvents', {}};

            lsmr = Unfold.fitBins(EEG, args{:});
            [lasso, info] = Unfold.fitBins(EEG, args{:}, 'Solver', 'glmnet');
            ridge = Unfold.fitBins(EEG, args{:}, 'Solver', 'glmnet', 'GlmnetAlpha', 0);

            testCase.verifyEqual(info.glmnetAlpha, 1, 'The toolbox''s default.');
            testCase.verifyEqual(nnz(lsmr.data == 0), 0);
            testCase.verifyGreaterThan(nnz(lasso.data == 0), 0, 'Lasso zeroes betas.');
            testCase.verifyGreaterThan(max(abs(ridge.data - lsmr.data), [], 'all'), 1e-3, ...
                'Ridge shrinks the betas.');
        end

        function aGlmnetFitGivesTrialsToo(testCase)
        %AGLMNETFITGIVESTRIALSTOO  uf_glmfit adds a column of its own for
        %   glmnet, its intercept for the whole recording ('glmnet-DC-
        %   Correction', NaN in X). It is subtracted with the neighbours and
        %   is no event's own response, so every trial still comes out.
            EEG = UnfoldBinsTest.recording();
            args = {'WindowMs', UnfoldBinsTest.WindowMs, 'ArtifactThresholdUv', 0, 'OtherEvents', {}};

            [trials, info] = Unfold.fitBins(EEG, args{:}, 'Solver', 'glmnet', 'GlmnetAlpha', 0, ...
                'Output', 'trials');
            lsmrTrials = Unfold.fitBins(EEG, args{:}, 'Output', 'trials');

            testCase.verifyEqual(info.trials, size(lsmrTrials.data, 3));
            testCase.verifyTrue(all(isfinite(trials.data), 'all'));
        end

        % ---- a regression on epochs -------------------------------------- %
        function withoutOverlapCorrectionABinIsTheMeanOfItsEpochs(testCase)
        %WITHOUTOVERLAPCORRECTIONABINISTHEMEANOFITSEPOCHS  With y ~ 1,
        %   uf_glmfit_nodc's intercept is the mean of the bin's epochs, cut
        %   as uf_epoch cuts them (each latency rounded, the window stopping
        %   a sample before its end, as EEGLAB's pop_epoch does), which the
        %   deconvolution on this overlapping recording is not.
            EEG = UnfoldBinsTest.recording();
            args = {'WindowMs', UnfoldBinsTest.WindowMs, 'ArtifactThresholdUv', 0};

            [epoched, info] = Unfold.fitBins(EEG, args{:}, 'OverlapCorrection', false);
            deconvolved = Unfold.fitBins(EEG, args{:}, 'OtherEvents', {});

            [byHand, lags] = UnfoldSolversTest.meanEpoch(EEG, 1, zeros(0, 2));
            testCase.verifyEqual(epoched.data(:, :, 1), byHand, 'AbsTol', 1e-9);
            testCase.verifyEqual(epoched.times, lags * 1000 / EEG.srate, 'AbsTol', 1e-9);
            testCase.verifyFalse(info.overlapCorrection);
            testCase.verifyGreaterThan(max(abs(epoched.data(:, 1:size(deconvolved.data, 2) - 1, 1) ...
                - deconvolved.data(:, 1:end - 1, 1)), [], 'all'), 0.1, ...
                'The neighbours'' overlap stays in an average of epochs.');
        end

        function anEpochTouchingAnArtefactIsLeftOut(testCase)
        %ANEPOCHTOUCHINGANARTEFACTISLEFTOUT  An epoch touching a stretch the
        %   scan marks is not in the fit (uf_epoch's winrej), so the bin is
        %   the mean of the others and counts only those.
            EEG = UnfoldBinsTest.recording();
            frequent = find(arrayfun(@(e) isequal(e.bini, 1), EEG.event));
            at = round(EEG.event(frequent(10)).latency);
            EEG.data(:, at + 30:at + 35) = EEG.data(:, at + 30:at + 35) + 500;

            [fitted, info] = Unfold.fitBins(EEG, 'WindowMs', UnfoldBinsTest.WindowMs, ...
                'ArtifactThresholdUv', 150, 'OverlapCorrection', false);

            [byHand, ~, count] = UnfoldSolversTest.meanEpoch(EEG, 1, info.excludedIntervals);
            testCase.verifyGreaterThan(info.epochsLeftOut, 0);
            testCase.verifyEqual(fitted.bindesc(1).n, count);
            testCase.verifyEqual(fitted.data(:, :, 1), byHand, 'AbsTol', 1e-9);
        end

        function anEpochSpanningACutIsLeftOut(testCase)
        %ANEPOCHSPANNINGACUTISLEFTOUT  A cut is handed to uf_epoch as a
        %   stretch of one sample, so the epochs whose window spans it are
        %   left out, as DefineBins leaves them out.
            EEG = UnfoldBinsTest.recording();
            frequent = find(arrayfun(@(e) isequal(e.bini, 1), EEG.event));
            cut = round(EEG.event(frequent(20)).latency) + 10;
            EEG.event(end + 1) = struct('type', 'boundary', 'latency', cut, 'bini', []);
            [~, order] = sort([EEG.event.latency]);
            EEG.event = EEG.event(order);

            [fitted, info] = Unfold.fitBins(EEG, 'WindowMs', UnfoldBinsTest.WindowMs, ...
                'ArtifactThresholdUv', 0, 'OverlapCorrection', false);

            [byHand, ~, count] = UnfoldSolversTest.meanEpoch(EEG, 1, [cut cut]);
            testCase.verifyGreaterThan(info.epochsLeftOut, 0);
            testCase.verifyEqual(fitted.bindesc(1).n, count);
            testCase.verifyEqual(fitted.data(:, :, 1), byHand, 'AbsTol', 1e-9);
        end

        function aFixedLagIsNoConcernWithoutOverlapCorrection(testCase)
        %AFIXEDLAGISNOCONCERNWITHOUTOVERLAPCORRECTION  Two bins at a lag
        %   that never varies cannot be told apart by a deconvolution, which
        %   the plan notes; a regression on epochs fits each epoch on its
        %   own and has nothing to tell apart.
            EEG = UnfoldBinsTest.recording('FixedLag', true);

            deconvolving = Unfold.binModel(EEG, 'OverlapCorrection', true);
            onEpochs = Unfold.binModel(EEG, 'OverlapCorrection', false);

            testCase.verifyTrue(any(contains(deconvolving.notes, 'not identified apart')));
            testCase.verifyFalse(any(contains(onEpochs.notes, 'not identified apart')));
        end

        function theTrialsWithoutOverlapCorrectionAreTheEpochs(testCase)
            EEG = UnfoldBinsTest.recording();
            args = {'WindowMs', UnfoldBinsTest.WindowMs, 'ArtifactThresholdUv', 0, ...
                'OverlapCorrection', false};

            waveforms = Unfold.fitBins(EEG, args{:});
            [trials, info] = Unfold.fitBins(EEG, args{:}, 'Output', 'trials');

            frequent = find(arrayfun(@(e) isequal(e.bini, 1), EEG.event));
            first = round(EEG.event(frequent(1)).latency);
            inFirstBin = trials.bindesc(1).trials;
            testCase.verifyEqual(info.trials, size(trials.data, 3));
            testCase.verifyEqual(trials.data(:, :, inFirstBin(1)), EEG.data(:, first + (-20:79)), ...
                'AbsTol', 1e-12, 'The epoch as it is, nothing subtracted.');
            testCase.verifyEqual(mean(trials.data(:, :, inFirstBin), 3), waveforms.data(:, :, 1), ...
                'AbsTol', 1e-9);
        end

        function theTermsComeFromTheEpochFitToo(testCase)
            EEG = UnfoldCovariatesTest.confoundedRecording();

            [terms, info] = Unfold.fitBins(EEG, 'WindowMs', [-100 400], 'ArtifactThresholdUv', 0, ...
                'Formulas', struct('bin', 'A', 'formula', 'y ~ 1 + gain'), 'Output', 'terms', ...
                'EvaluateAt', 'gain = 1 2', 'OverlapCorrection', false);

            testCase.verifyEqual({terms.bindesc.label}, {'A: (Intercept)', 'A: gain = 1', ...
                'A: gain = 2', 'B: (Intercept)'});
            testCase.verifyTrue(all(isfinite(terms.data), 'all'));
            testCase.verifyFalse(info.overlapCorrection);
        end

        function anOffsetIsNoObstacleWithoutOverlapCorrection(testCase)
        %ANOFFSETISNOOBSTACLEWITHOUTOVERLAPCORRECTION  A regression on
        %   epochs has an intercept at every sample, which takes up a
        %   standing voltage as an average does; only the deconvolution,
        %   whose design has no constant term, refuses it.
            EEG = UnfoldBinsTest.recording();
            EEG.data = EEG.data + 11000;
            args = {'WindowMs', UnfoldBinsTest.WindowMs, 'ArtifactThresholdUv', 0};

            fitted = Unfold.fitBins(EEG, args{:}, 'OverlapCorrection', false);

            testCase.verifyEqual(fitted.data(:, :, 1), UnfoldSolversTest.meanEpoch(EEG, 1, zeros(0, 2)), ...
                'AbsTol', 1e-6);
            testCase.verifyError(@() Unfold.fitBins(EEG, args{:}), 'Alakazam:Unfold:DcOffset');
        end
    end

    methods (Static)
        function [average, lags, count] = meanEpoch(EEG, bin, marks)
        %MEANEPOCH  The mean of BIN's epochs by hand, as uf_epoch cuts them:
        %   each latency rounded, samples -20 to 79 at 100 Hz (the window
        %   -200 to 800 ms, stopping a sample short as pop_epoch does), an
        %   epoch left out when its window, to 800 ms, touches one of MARKS
        %   or the cut at sample 1, or runs off the recording.
            lags = -20:79;
            rows = find(arrayfun(@(e) isequal(e.bini, bin), EEG.event));
            centres = round([EEG.event(rows).latency]);
            keep = centres - 20 > 1 & centres + 79 <= size(EEG.data, 2);
            for m = 1:size(marks, 1)
                keep = keep & ~(centres - 20 <= marks(m, 2) & centres + 80 >= marks(m, 1));
            end
            centres = centres(keep);
            count = numel(centres);
            average = zeros(size(EEG.data, 1), numel(lags));
            for c = centres
                average = average + double(EEG.data(:, c + lags));
            end
            average = average / count;
        end
    end
end
