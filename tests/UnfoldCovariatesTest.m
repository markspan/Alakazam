classdef UnfoldCovariatesTest < matlab.unittest.TestCase
%UNFOLDCOVARIATESTEST  What explains a bin's response: formulas and the
%   older covariates, in the deconvolution model.
%
%   EACH BIN HAS A FORMULA in Unfold's notation ('y ~ 1' by default), and the
%   older Covariates option still adds its fields as linear terms to every
%   bin without one. Unfold.binModel checks every field a formula names
%   against the bin's own events before the toolbox sees it, and
%   Unfold.designMatrix names the bin when the toolbox refuses a formula.
%
%   A TERM IS A CONTROL, and the case that shows it is a covariate
%   UNBALANCED BETWEEN BINS: if the rare events happen to have larger values
%   than the frequent ones, a model without the covariate charges that
%   difference to the bins and reports a condition effect that is not one.
%   itSeparatesACovariateFromTheBinItIsConfoundedWith is that case, with two
%   bins whose true responses are identical. It works because every bin's
%   waveform is the prediction at the SAME values of the term (the pooled
%   values, Unfold.binModel's plan.pooled), not at each bin's own; for a
%   spline, over the values the bins share, since outside a bin's own values
%   its spline is extrapolating (aSplineControlsTheConfoundToo).
%
%   THE TERMS OUTPUT is the model's own view (uf_predictContinuous, then
%   uf_addmarginal): one waveform per term, at chosen values.
%
%   Run with: runtests('tests/UnfoldCovariatesTest.m').
%
%   See also UNFOLD.BINMODEL, UNFOLD.FITBINS, UNFOLD.DESIGNMATRIX,
%   UNFOLD.EVENTCOVARIATES, DECONVOLVE.

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

        function aCovariateJoinsTheFormulaAndIsPooled(testCase)
        %ACOVARIATEJOINSTHEFORMULAANDISPOOLED  The older option: a linear
        %   term in every type's formula, the events carrying their own
        %   values, and the values pooled over the events the model contains,
        %   which is where Unfold.fitBins evaluates every bin's waveform.
            EEG = UnfoldCovariatesTest.recording();

            plan = Unfold.binModel(EEG, 'Covariates', {'rt'});

            testCase.verifyTrue(all(contains(plan.formulas, 'y ~ 1 + rt')), ...
                'Every modelled type carries the term.');
            source = [EEG.event(plan.eventSource).rt];
            testCase.verifyEqual([plan.events.rt], source, ...
                'The values go to Unfold as they are; nothing is centred any more.');
            testCase.verifyEqual({plan.pooled.name}, {'rt'});
            % Over the events the model actually contains, which is not every
            % event in the recording: a boundary is dropped from the design
            % (it is a cut, not a response), so its value must not move the
            % point the bins' waveforms are reported at either.
            modelled = ~strcmp({EEG.event.type}, 'boundary');
            testCase.verifyEqual(mean(plan.pooled.values), mean([EEG.event(modelled).rt]), ...
                'AbsTol', 1e-9);
        end

        function withoutACovariateNothingChanges(testCase)
            EEG = UnfoldCovariatesTest.recording();

            plan = Unfold.binModel(EEG);

            testCase.verifyEmpty(plan.pooled);
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

        function aValueIsReadFromItsOwnEventNotFromOneAtTheSameSample(testCase)
        %AVALUEISREADFROMITSOWNEVENTNOTFROMONEATTHESAMESAMPLE  The values
        %   used to be looked up by latency, so an event sharing its sample
        %   with another took the other's value. In Ehinger & Dimigen's face
        %   data three stimulus onsets coincide with a saccade: the stimuli
        %   (all 0) picked up three saccade amplitudes, counted as varying,
        %   and were fitted with a covariate that was nearly their own
        %   intercept. Here one Rare event (rt all 0) shares its sample with
        %   a response whose rt is not.
            EEG = UnfoldCovariatesTest.recording();
            rare = find(strcmp({EEG.event.type}, 'S2'));
            for k = rare
                EEG.event(k).rt = 0;
            end
            twin = EEG.event(rare(3));
            twin.type = 'response';
            twin.bini = [];
            twin.rt = 512;
            EEG.event(end + 1) = twin;                 % after the Rare event, at its sample
            [~, order] = sort([EEG.event.latency]);    % stable: the twin stays after it
            EEG.event = EEG.event(order);

            plan = Unfold.binModel(EEG, 'Covariates', {'rt'});

            testCase.verifyEqual(plan.formulas{strcmp(plan.eventTypes, 'bin_Rare')}, 'y ~ 1', ...
                'Every Rare event carries rt = 0; the response''s 512 is not theirs.');
            rareRows = strcmp({plan.events.type}, 'bin_Rare');
            testCase.verifyEqual(unique([plan.events(rareRows).rt]), 0);
        end

        function anAbsentFieldIsNotedRatherThanThrown(testCase)
            EEG = UnfoldCovariatesTest.recording();

            plan = Unfold.binModel(EEG, 'Covariates', {'noSuchField'});

            testCase.verifyEmpty(plan.pooled);
            testCase.verifyTrue(all(strcmp(plan.formulas, 'y ~ 1')));
            testCase.verifyTrue(any(contains(plan.notes, 'noSuchField')));
        end

        % ---- formulas ------------------------------------------------------ %
        function eachBinTakesItsOwnFormula(testCase)
        %EACHBINTAKESITSOWNFORMULA  A formula names its bin by label, may be
        %   written without its 'y ~', and a bin without one is 'y ~ 1'.
            EEG = UnfoldCovariatesTest.recording();
            formulas = struct('bin', {'Rare'}, 'formula', {'1 + spl(rt, 4)'});

            plan = Unfold.binModel(EEG, 'Formulas', formulas);

            testCase.verifyEqual(plan.formulas{strcmp(plan.eventTypes, 'bin_Rare')}, 'y ~ 1 + spl(rt, 4)');
            testCase.verifyEqual(plan.formulas{strcmp(plan.eventTypes, 'bin_Frequent')}, 'y ~ 1');
            rare = strcmp({plan.events.type}, 'bin_Rare');
            testCase.verifyEqual([plan.events(rare).rt], [EEG.event(plan.eventSource(rare)).rt], ...
                'The field a formula uses travels with its events.');
            testCase.verifyEqual(numel(plan.pooled.values), nnz(rare), ...
                'Pooled over the bins that use it, and only those.');
        end

        function aFormulaOverridesTheOlderCovariates(testCase)
            EEG = UnfoldCovariatesTest.recording();
            formulas = struct('bin', {'Rare'}, 'formula', {'y ~ 1'});

            plan = Unfold.binModel(EEG, 'Formulas', formulas, 'Covariates', {'rt'});

            testCase.verifyEqual(plan.formulas{strcmp(plan.eventTypes, 'bin_Rare')}, 'y ~ 1');
            testCase.verifyEqual(plan.formulas{strcmp(plan.eventTypes, 'bin_Frequent')}, 'y ~ 1 + rt');
        end

        function aFactorTravelsAsText(testCase)
            EEG = UnfoldCovariatesTest.recording();
            for k = 1:numel(EEG.event)
                EEG.event(k).hand = char('L' + 6 * (mod(k, 2) == 0));   % 'L' or 'R'
            end

            plan = Unfold.binModel(EEG, 'Formulas', struct('bin', 'Frequent', 'formula', 'y ~ 1 + cat(hand)'));

            frequent = strcmp({plan.events.type}, 'bin_Frequent');
            testCase.verifyEqual(sort(unique({plan.events(frequent).hand})), {'L', 'R'});
            testCase.verifyEmpty(plan.pooled, 'A factor is not pooled: each bin keeps its own mix.');
        end

        function aMisspeltFieldIsRefusedNamingTheBin(testCase)
        %AMISSPELTFIELDISREFUSEDNAMINGTHEBIN  uf_designmat's own message for
        %   this is "Function is not defined for 'cell' inputs".
            EEG = UnfoldCovariatesTest.recording();

            try
                Unfold.binModel(EEG, 'Formulas', struct('bin', 'Rare', 'formula', 'y ~ 1 + rtt'));
                err = MException('none:none', 'no error');
            catch err
            end

            testCase.verifyEqual(err.identifier, 'Alakazam:Unfold:NoSuchField');
            testCase.verifySubstring(err.message, '"Rare"');
            testCase.verifySubstring(err.message, '"rtt"');
        end

        function aTermThatNeverVariesIsRefused(testCase)
        %ATERMTHATNEVERVARIESISREFUSED  Written explicitly, a constant term is
        %   refused rather than dropped: the user asked for it, and it would be
        %   a copy of the bin's own intercept (EYE-EEG's zero-filled fields).
            EEG = UnfoldCovariatesTest.recording();

            try
                Unfold.binModel(EEG, 'Formulas', struct('bin', 'Rare', 'formula', 'y ~ 1 + constantField'));
                err = MException('none:none', 'no error');
            catch err
            end

            testCase.verifyEqual(err.identifier, 'Alakazam:Unfold:NeverVaries');
            testCase.verifySubstring(err.message, 'EYE-EEG');
        end

        function aFactorWithOneLevelIsRefused(testCase)
            EEG = UnfoldCovariatesTest.recording();
            [EEG.event.hand] = deal('L');

            testCase.verifyError(@() Unfold.binModel(EEG, 'Formulas', ...
                struct('bin', 'Rare', 'formula', 'y ~ 1 + cat(hand)')), 'Alakazam:Unfold:OneLevel');
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
            testCase.verifyTrue(all(contains({info.formulas.formula}, 'gain')));
        end

        function aSplineControlsTheConfoundToo(testCase)
        %ASPLINECONTROLSTHECONFOUNDTOO  The same test with the covariate as a
        %   spline: both bins are evaluated over the gains they share, so the
        %   confound still does not show up as a bin difference, and the note
        %   says which range that was.
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            EEG = UnfoldCovariatesTest.confoundedRecording('overlap');
            formulas = struct('bin', {'A', 'B'}, 'formula', {'y ~ 1 + spl(gain, 4)', 'y ~ 1 + spl(gain, 4)'});

            plain = Unfold.fitBins(EEG, 'WindowMs', [-100 400], 'ArtifactThresholdUv', 0);
            [adjusted, info] = Unfold.fitBins(EEG, 'WindowMs', [-100 400], 'ArtifactThresholdUv', 0, ...
                'Formulas', formulas);

            testCase.verifyLessThan(maxDifference(adjusted, 1, 2), 0.2 * maxDifference(plain, 1, 2));
            testCase.verifyTrue(any(contains(info.notes, 'the range every bin using it shares')), ...
                'Cutting the pooled values to the shared range is said, not done silently.');
        end

        function binsWithNoSharedValuesAreEachEvaluatedOverTheirOwn(testCase)
        %BINSWITHNOSHAREDVALUESAREEACHEVALUATEDOVERTHEIROWN  Where the bins'
        %   gains do not overlap, a spline cannot compare them anywhere
        %   without extrapolating, so each bin keeps its own values and the
        %   note says the confound is still in the difference.
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            EEG = UnfoldCovariatesTest.confoundedRecording();
            formulas = struct('bin', {'A', 'B'}, 'formula', {'y ~ 1 + spl(gain, 4)', 'y ~ 1 + spl(gain, 4)'});

            [fitted, info] = Unfold.fitBins(EEG, 'WindowMs', [-100 400], 'ArtifactThresholdUv', 0, ...
                'Formulas', formulas);

            testCase.verifyTrue(any(contains(info.notes, 'share no values')));
            testCase.verifyTrue(all(isfinite(fitted.data(:))));
        end

        function aFormulaTheToolboxRefusesNamesItsBin(testCase)
        %AFORMULATHETOOLBOXREFUSESNAMESITSBIN  A spline without its number of
        %   splines names a field the events have, so binModel passes it, and
        %   uf_designmat's parser refuses it without saying which formula it
        %   was reading. The error names the bin and quotes its formula.
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            EEG = UnfoldCovariatesTest.recording();
            plan = Unfold.binModel(EEG, 'Formulas', struct('bin', 'Rare', 'formula', 'y ~ 1 + spl(rt)'));

            try
                Unfold.designMatrix(EEG, plan);
                err = [];
            catch err
            end

            testCase.assertNotEmpty(err, 'The toolbox accepted a spline without its size.');
            testCase.verifyEqual(err.identifier, 'Alakazam:Unfold:Formula');
            testCase.verifySubstring(err.message, '"Rare", y ~ 1 + spl(rt)');
        end

        function aModelOfOneEventTypeIsFitted(testCase)
        %AMODELOFONEEVENTTYPEISFITTED  One bin and no other events modelled
        %   is a list of one formula, which uf_designmat does not split the
        %   way it splits two or more; it has to be handed over as the
        %   formula itself.
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            EEG = DefineBins(UnfoldCovariatesTest.recording(), struct('script', 'bin 1 "Frequent" "S1"'));

            [fitted, info] = Unfold.fitBins(EEG, 'WindowMs', [-100 400], 'ArtifactThresholdUv', 0, ...
                'OtherEvents', {}, 'Formulas', struct('bin', 'Frequent', 'formula', 'y ~ 1 + rt'));

            testCase.verifyEqual({info.formulas.formula}, {'y ~ 1 + rt'});
            testCase.verifyTrue(all(isfinite(fitted.data(:))));
        end

        function theTermsAreTheModelsOwnView(testCase)
        %THETERMSARETHEMODELSOWNVIEW  Output 'terms': per bin, the intercept
        %   and the spline at each value asked for, labelled, each a whole
        %   waveform (uf_addmarginal), and the response grows with the gain
        %   as the recording was built.
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            EEG = UnfoldCovariatesTest.confoundedRecording();
            formulas = struct('bin', {'A'}, 'formula', {'y ~ 1 + gain'});

            [terms, info] = Unfold.fitBins(EEG, 'WindowMs', [-100 400], 'ArtifactThresholdUv', 0, ...
                'Formulas', formulas, 'Output', 'terms', 'EvaluateAt', 'gain = 0.8 1.2');

            labels = {terms.bindesc.label};
            testCase.verifyEqual(labels, {'A: (Intercept)', 'A: gain = 0.8', 'A: gain = 1.2', ...
                'B: (Intercept)'});
            testCase.verifyEqual(char(string(terms.DataFormat)), 'Averaged');
            testCase.verifyEqual(info.output, 'terms');
            peak = @(k) max(terms.data(1, :, k));
            testCase.verifyGreaterThan(peak(3), peak(2), 'A larger gain, a larger response.');
            testCase.verifyEqual(peak(3) / peak(2), 1.2 / 0.8, 'RelTol', 0.1);
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

        function [EEG, truth] = confoundedRecording(overlap)
        %CONFOUNDEDRECORDING  Both bins have the SAME response, scaled per
        %   event by a covariate whose values are systematically larger for
        %   the second bin. The honest answer is no bin difference.
        %   CONFOUNDEDRECORDING('overlap') draws the gains from ranges that
        %   overlap (A 0.6 to 2.4, B 1.2 to 3.0), which a spline needs to
        %   compare the bins at values both of them have; without it they do
        %   not overlap at all.
            srate = 100;
            npnts = 30000;
            t = (0:round(0.3 * srate)) / srate;
            waveform = 6 * sin(pi * t / 0.3) .* exp(-t / 0.2);

            rng(21);
            first = round(linspace(300, 29000, 60) + 30 * randn(1, 60));
            second = round(first + 90 + 30 * rand(1, 60));
            gain = [1 + 0.15 * randn(1, 60), 2.5 + 0.15 * randn(1, 60)];   % confounded with bin
            if nargin > 0 && strcmp(overlap, 'overlap')
                gain = [0.6 + 1.8 * rand(1, 60), 1.2 + 1.8 * rand(1, 60)];
            end

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
