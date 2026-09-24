classdef UnfoldCovariatesTest < matlab.unittest.TestCase
%UNFOLDCOVARIATESTEST  Covariates in the deconvolution model.
%
%   A covariate here is a NUISANCE regressor: it is fitted per event type,
%   mean-centred, and its slope is then dropped, so the result is still one
%   waveform per bin and the node's shape does not change. What it buys is
%   the waveform that is left, and the case that shows it is a covariate
%   UNBALANCED BETWEEN BINS: if the rare events happen to have larger values
%   than the frequent ones, a model without the covariate charges that
%   difference to the bins and reports a condition effect that is not one.
%   itSeparatesACovariateFromTheBinItIsConfoundedWith is that case, with two
%   bins whose true responses are identical.
%
%   THE CENTRING IS NOT COSMETIC. A bin's waveform is the model's intercept,
%   which is the response when every predictor is zero. On a raw covariate
%   that means the response at an amplitude, or a reaction time, of zero:
%   an extrapolation off the end of the data. Centred, it is the response at
%   the covariate's average value, which is what the bin's waveform should
%   mean and what makes it comparable with an average of the same events.
%
%   Run with: runtests('tests/UnfoldCovariatesTest.m').
%
%   See also UNFOLD.BINMODEL, UNFOLD.EVENTCOVARIATES, DECONVOLVE.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Transformations', 'Deconvolve'), ...
                     fullfile(root, 'src', 'Transformations', 'DefineBins'), ...
                     fullfile(root, 'src', 'Support'), fullfile(root, 'tests')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function itOffersTheNumericEventFields(testCase)
            EEG = UnfoldCovariatesTest.recording();

            found = Unfold.eventCovariates(EEG);

            testCase.verifyTrue(ismember('rt', {found.name}), 'A numeric field is a candidate.');
            testCase.verifyEqual(found(strcmp({found.name}, 'rt')).kind, 'linear');
            testCase.verifyFalse(ismember('latency', {found.name}), ...
                'The event''s own position is not a predictor of the data at that position.');
            testCase.verifyFalse(ismember('bini', {found.name}), ...
                'DefineBins'' bookkeeping is not a covariate.');
            testCase.verifyFalse(ismember('constantField', {found.name}), ...
                'A field with one value everywhere has no slope to fit.');
        end

        function aCovariateJoinsTheFormulaAndIsCentred(testCase)
            EEG = UnfoldCovariatesTest.recording();

            plan = Unfold.binModel(EEG, 'Covariates', {'rt'});

            testCase.verifyTrue(all(contains(plan.formulas, 'y ~ 1 + rt')), ...
                'Every modelled type carries the term.');
            testCase.verifyEqual(numel(plan.covariates), 1);
            testCase.verifyEqual(plan.covariates.name, 'rt');
            values = [plan.events.rt];
            testCase.verifyEqual(mean(values), 0, 'AbsTol', 1e-9, ...
                'Centred, so a bin''s waveform is its response at the average value.');
            % Over the events the model actually contains, which is not every
            % event in the recording: a boundary is dropped from the design
            % (it is a cut, not a response), so its value must not move the
            % point the bins' waveforms are reported at either.
            modelled = ~strcmp({EEG.event.type}, 'boundary');
            testCase.verifyEqual(plan.covariates.centre, mean([EEG.event(modelled).rt]), ...
                'AbsTol', 1e-9);
        end

        function withoutACovariateNothingChanges(testCase)
            EEG = UnfoldCovariatesTest.recording();

            plan = Unfold.binModel(EEG);

            testCase.verifyEmpty(plan.covariates);
            testCase.verifyTrue(all(strcmp(plan.formulas, 'y ~ 1')));
        end

        function aTypeMissingTheValueKeepsItsOwnFormula(testCase)
        %ATYPEMISSINGTHEVALUEKEEPSITSOWNFORMULA  Unfold needs a predictor
        %   filled for every event of a type that uses it. Rather than refuse
        %   the model or invent values, each type keeps the covariates its own
        %   events all have, and the difference is named in the notes.
            EEG = UnfoldCovariatesTest.recording();
            for k = 1:numel(EEG.event)
                if strcmp(EEG.event(k).type, 'S2')
                    EEG.event(k).rt = NaN;
                end
            end

            plan = Unfold.binModel(EEG, 'Covariates', {'rt'});

            rare = plan.formulas{strcmp(plan.eventTypes, 'bin_Rare')};
            frequent = plan.formulas{strcmp(plan.eventTypes, 'bin_Frequent')};
            testCase.verifyEqual(rare, 'y ~ 1', 'Its events have no value to fit against.');
            testCase.verifyEqual(frequent, 'y ~ 1 + rt');
            testCase.verifyTrue(any(contains(plan.notes, 'not for')), ...
                'The report says which bins the covariate was left out of.');
        end

        function aCovariateThatNeverVariesWithinATypeIsLeftOut(testCase)
        %ACOVARIATETHATNEVERVARIESWITHINATYPEISLEFTOUT  EYE-EEG fills every
        %   field that does not apply with 0: each fixation carries
        %   sac_amplitude = 0. Taken as values, that entered saccade
        %   amplitude into the fixation model as a constant, which cannot be
        %   told apart from the fixations' own waveform and lets the solver
        %   split it arbitrarily. A type gets a covariate only where it varies.
            EEG = UnfoldCovariatesTest.recording();
            for k = 1:numel(EEG.event)
                if strcmp(EEG.event(k).type, 'S2')
                    EEG.event(k).rt = 0;      % present, and the same everywhere
                end
            end

            plan = Unfold.binModel(EEG, 'Covariates', {'rt'});

            testCase.verifyEqual(plan.formulas{strcmp(plan.eventTypes, 'bin_Rare')}, 'y ~ 1');
            testCase.verifyEqual(plan.formulas{strcmp(plan.eventTypes, 'bin_Frequent')}, 'y ~ 1 + rt');
            testCase.verifyTrue(any(contains(plan.notes, 'all carry the same')));
        end

        function anAbsentFieldIsNotedRatherThanThrown(testCase)
            EEG = UnfoldCovariatesTest.recording();

            plan = Unfold.binModel(EEG, 'Covariates', {'noSuchField'});

            testCase.verifyEmpty(plan.covariates);
            testCase.verifyTrue(any(contains(plan.notes, 'noSuchField')));
        end
    end

    methods (Test, TestTags = {'External'})
        function itSeparatesACovariateFromTheBinItIsConfoundedWith(testCase)
        %ITSEPARATESACOVARIATEFROMTHEBINITISCONFOUNDEDWITH  Two bins whose
        %   true responses are IDENTICAL, and a covariate that scales the
        %   response and happens to be larger for one bin's events than the
        %   other's. Without the covariate the model can only charge that
        %   difference to the bins, and reports a condition effect that does
        %   not exist. With it, the bins come back the same, because each
        %   bin's waveform is then its response at the covariate's average.
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            [EEG, truth] = UnfoldCovariatesTest.confoundedRecording();

            plain = Unfold.fitBins(EEG, 'WindowMs', [-100 400], 'ArtifactThresholdUv', 0);
            adjusted = Unfold.fitBins(EEG, 'WindowMs', [-100 400], 'ArtifactThresholdUv', 0, ...
                'Covariates', {'gain'});

            testCase.verifyEqual(size(adjusted.data), size(plain.data), ...
                'The node keeps its shape: one waveform per bin either way.');
            plainGap = maxDifference(plain, 1, 2);
            adjustedGap = maxDifference(adjusted, 1, 2);
            testCase.verifyGreaterThan(plainGap, 0.5 * truth.peak, ...
                'Uncorrected, the confounded covariate shows up as a bin difference.');
            testCase.verifyLessThan(adjustedGap, 0.2 * plainGap, ...
                'Corrected, the two bins come back as the same response they truly are.');
        end

        function theSlopeIsDroppedNotReported(testCase)
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            EEG = UnfoldCovariatesTest.confoundedRecording();

            [fitted, info] = Unfold.fitBins(EEG, 'WindowMs', [-100 400], ...
                'ArtifactThresholdUv', 0, 'Covariates', {'gain'});

            testCase.verifyEqual(size(fitted.data, 3), numel(EEG.bindesc), ...
                'A covariate adds no bins: its slope is fitted and thrown away.');
            testCase.verifyEqual(info.covariates.name, 'gain');
            testCase.verifyEqual(info.covariates.n, 120);
        end
    end

    methods (Static)
        function EEG = recording()
        %RECORDING  Two bins of events, each carrying a reaction time, plus a
        %   field that never varies and one that is not a number.
            EEG = DeconvolveTest.untaggedRecording();
            rng(5);
            for k = 1:numel(EEG.event)
                EEG.event(k).rt = 400 + 60 * randn();
                EEG.event(k).constantField = 7;
                EEG.event(k).note = 'text';
            end
            EEG = DefineBins(EEG, struct('script', DeconvolveTest.BinScript));
        end

        function [EEG, truth] = confoundedRecording()
        %CONFOUNDEDRECORDING  Both bins have the SAME response, scaled per
        %   event by a covariate whose values are systematically larger for
        %   the second bin. The honest answer is no bin difference.
            srate = 100;
            npnts = 30000;
            t = (0:round(0.3 * srate)) / srate;
            waveform = 6 * sin(pi * t / 0.3) .* exp(-t / 0.2);

            rng(21);
            first = round(linspace(300, 29000, 60) + 30 * randn(1, 60));
            second = round(first + 90 + 30 * rand(1, 60));
            gain = [1 + 0.15 * randn(1, 60), 2.5 + 0.15 * randn(1, 60)];   % confounded with bin

            data = 0.05 * randn(1, npnts);
            latencies = [first second];
            for k = 1:numel(latencies)
                data = UnfoldBinsTest.addResponse(data, latencies(k), gain(k) * waveform);
            end

            event = struct('type', {}, 'latency', {}, 'bini', {}, 'gain', {});
            for k = 1:numel(first)
                event(end + 1) = struct('type', 'A', 'latency', first(k), ...
                    'bini', 1, 'gain', gain(k)); %#ok<AGROW>
            end
            for k = 1:numel(second)
                event(end + 1) = struct('type', 'B', 'latency', second(k), ...
                    'bini', 2, 'gain', gain(60 + k)); %#ok<AGROW>
            end
            [~, order] = sort([event.latency]);
            event = event(order);

            EEG = struct('data', data, 'srate', srate, 'pnts', npnts, 'trials', 1, ...
                'nbchan', 1, 'xmin', 0, 'xmax', (npnts - 1) / srate, ...
                'times', (0:npnts - 1) / srate * 1000, 'DataFormat', 'CONTINUOUS', ...
                'chanlocs', struct('labels', {'Cz'}), 'event', event, ...
                'bindesc', struct('index', {1, 2}, 'label', {'A', 'B'}, 'combo', {[], []}));
            truth = struct('peak', max(waveform) * mean(gain));
        end
    end
end

% ======================================================================= %
function d = maxDifference(fitted, binA, binB)
%MAXDIFFERENCE  The largest gap between two fitted bins, in microvolts.
    d = max(abs(fitted.data(1, :, binA) - fitted.data(1, :, binB)));
end
