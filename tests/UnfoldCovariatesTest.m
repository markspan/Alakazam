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

        function aTwoDimensionalSplineIsAFormulaToo(testCase)
        %ATWODIMENSIONALSPLINEISAFORMULATOO  Unfold's 2dspl(x, z, n), a
        %   smooth surface over two fields, was read as a field called
        %   "dspl". Its two fields travel with their events, and are pooled
        %   as pairs, since the surface is evaluated at both at once.
            EEG = UnfoldCovariatesTest.withPositions(UnfoldCovariatesTest.recording());

            plan = Unfold.binModel(EEG, 'Formulas', struct('bin', 'Rare', 'formula', 'y ~ 1 + 2dspl(x, z, 4)'));

            rare = strcmp({plan.events.type}, 'bin_Rare');
            testCase.verifyEqual([plan.events(rare).x], [EEG.event(plan.eventSource(rare)).x]);
            testCase.verifyEqual([plan.events(rare).z], [EEG.event(plan.eventSource(rare)).z]);
            surface = plan.pooled(strcmp({plan.pooled.name}, 'xz'));
            testCase.assertNumElements(surface, 1, 'The surface is pooled under the toolbox''s own name.');
            testCase.verifyEqual(surface.pair, {'x', 'z'});
            testCase.verifyEqual(surface.values, [[plan.events(rare).x]; [plan.events(rare).z]]);
        end

        function aTwoDimensionalSplineNamesTheFieldItLacks(testCase)
            EEG = UnfoldCovariatesTest.withPositions(UnfoldCovariatesTest.recording());

            try
                Unfold.binModel(EEG, 'Formulas', struct('bin', 'Rare', 'formula', 'y ~ 1 + 2dspl(x, depth, 4)'));
                err = MException('none:none', 'no error');
            catch err
            end

            testCase.verifyEqual(err.identifier, 'Alakazam:Unfold:NoSuchField');
            testCase.verifySubstring(err.message, '"depth"');
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

        function theTermsInterceptAveragesOverACircularSpline(testCase)
        %THETERMSINTERCEPTAVERAGESOVERACIRCULARSPLINE  With Marginal 'AME' the
        %   terms' intercept carries every other term as its average marginal
        %   effect, the spline averaged over the events' own values, as the
        %   waveform per bin does.
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            [EEG, formulas] = UnfoldCovariatesTest.anglesNearNorth();

            waveforms = Unfold.fitBins(EEG, 'WindowMs', UnfoldBinsTest.WindowMs, ...
                'ArtifactThresholdUv', 0, 'BaselineMs', [], 'Formulas', formulas);
            [terms, info] = Unfold.fitBins(EEG, 'WindowMs', UnfoldBinsTest.WindowMs, ...
                'ArtifactThresholdUv', 0, 'BaselineMs', [], 'Formulas', formulas, 'Output', 'terms', ...
                'Marginal', 'AME');

            intercept = strcmp({terms.bindesc.label}, 'Frequent: (Intercept)');
            testCase.assertEqual(nnz(intercept), 1);
            testCase.verifyEqual(terms.data(:, :, intercept), waveforms.data(:, :, 1), 'AbsTol', 1e-6, ...
                'The intercept with the spline averaged over the events is the bin''s waveform.');
            testCase.verifyEqual(info.marginal, 'AME');
        end

        function theTermsTakeTheMeanValueByDefaultAsTheToolboxDoes(testCase)
        %THETERMSTAKETHEMEANVALUEBYDEFAULTASTHETOOLBOXDOES  uf_addmarginal's
        %   own default, 'MEM': the intercept carries the spline at its mean
        %   value, which for angles near 0 and 360 degrees is one no event
        %   had, so it is not the bin's waveform. That is the toolbox's
        %   choice, and the default here.
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            [EEG, formulas] = UnfoldCovariatesTest.anglesNearNorth();

            [byDefault, info] = Unfold.fitBins(EEG, 'WindowMs', UnfoldBinsTest.WindowMs, ...
                'ArtifactThresholdUv', 0, 'Formulas', formulas, 'Output', 'terms');
            averaged = Unfold.fitBins(EEG, 'WindowMs', UnfoldBinsTest.WindowMs, ...
                'ArtifactThresholdUv', 0, 'Formulas', formulas, 'Output', 'terms', 'Marginal', 'AME');

            testCase.verifyEqual(info.marginal, 'MEM');
            intercept = strcmp({byDefault.bindesc.label}, 'Frequent: (Intercept)');
            testCase.assertEqual(nnz(intercept), 1);
            difference = byDefault.data(:, :, intercept) - averaged.data(:, :, intercept);
            testCase.verifyGreaterThan(max(abs(difference(:))), 1e-6, ...
                'At the mean angle, not averaged over the events'' own angles.');
        end

        % ---- missing numbers: the toolbox's uf_imputeMissing ------------- %
        function aMissingNumberIsFilledInByTheToolboxsMedian(testCase)
        %AMISSINGNUMBERISFILLEDINBYTHETOOLBOXSMEDIAN  By default an event
        %   without a number is given the median of its bin's others, by
        %   uf_imputeMissing: the same model as filling it in by hand. Fifteen
        %   of the 120 events is over the toolbox's 5%, which it warns about.
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            EEG = UnfoldCovariatesTest.confoundedRecording();
            [holed, gaps, known] = UnfoldCovariatesTest.withGaps(EEG, 'gain', 15);
            filled = EEG;
            [filled.event(gaps).gain] = deal(median(known));
            args = {'WindowMs', [-100 400], 'ArtifactThresholdUv', 0, 'Output', 'terms', ...
                'EvaluateAt', 'gain = 1 2', 'Formulas', struct('bin', 'A', 'formula', 'y ~ 1 + gain')};

            [imputed, info] = Unfold.fitBins(holed, args{:});
            byHand = Unfold.fitBins(filled, args{:}, 'MissingValues', 'refuse');

            testCase.verifyEqual(imputed.data, byHand.data, 'AbsTol', 1e-9);
            testCase.verifyEqual(info.missingValues, 'median');
            testCase.verifyEqual([info.missing.n], 15);
            testCase.verifyTrue(any(contains(info.notes, 'uf_imputeMissing')), 'The notes say so.');
            testCase.verifyTrue(any(contains(info.notes, 'The Unfold toolbox warns')), ...
                'Its own warning about more than 5% missing is kept.');
        end

        function eventsMissingANumberCanBeLeftOut(testCase)
        %EVENTSMISSINGANUMBERCANBELEFTOUT  'drop': uf_imputeMissing zeroes
        %   their rows of the design, which is the model without those events,
        %   and the bins count, average and cut trials without them too. They
        %   have a second field, extra, which is not pooled either.
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            EEG = UnfoldCovariatesTest.confoundedRecording();
            rng(6);
            for k = 1:numel(EEG.event)
                EEG.event(k).extra = 3 * randn();
            end
            [holed, gaps] = UnfoldCovariatesTest.withGaps(EEG, 'gain', 5);
            [holed.event(gaps).extra] = deal(40);   % far from the others, if it were pooled
            removed = EEG;
            removed.event(gaps) = [];
            args = {'WindowMs', [-100 400], 'ArtifactThresholdUv', 0, ...
                'Formulas', struct('bin', {'A', 'B'}, 'formula', 'y ~ 1 + gain + extra')};

            [dropped, info] = Unfold.fitBins(holed, args{:}, 'MissingValues', 'drop');
            byHand = Unfold.fitBins(removed, args{:}, 'MissingValues', 'refuse');
            [~, trials] = Unfold.fitBins(holed, args{:}, 'MissingValues', 'drop', 'Output', 'trials');
            [~, handTrials] = Unfold.fitBins(removed, args{:}, 'Output', 'trials');

            testCase.verifyEqual(dropped.data, byHand.data, 'AbsTol', 1e-6, ...
                'Held at the values of the events kept, from the events kept.');
            testCase.verifyEqual([dropped.bindesc.n], [byHand.bindesc.n]);
            testCase.verifyEqual(info.dropped, 5);
            testCase.verifyEqual(trials.trialCandidates, handTrials.trialCandidates, ...
                'A dropped event is not a trial: nothing of its own was fitted.');
        end

        function aMissingNumberIsRefusedWhenAskedNamingTheBin(testCase)
            EEG = UnfoldCovariatesTest.confoundedRecording();
            holed = UnfoldCovariatesTest.withGaps(EEG, 'gain', 2);
            formulas = struct('bin', 'A', 'formula', 'y ~ 1 + gain');

            err = UnfoldCovariatesTest.refusal(@() Unfold.binModel(holed, 'Formulas', formulas, ...
                'MissingValues', 'refuse'));

            testCase.verifyEqual(err.identifier, 'Alakazam:Unfold:MissingValue');
            testCase.verifySubstring(err.message, '2 of the 60 events of "A"');
            testCase.verifySubstring(err.message, 'Missing values');
        end

        function aFactorWithoutALevelIsRefusedWhateverTheChoice(testCase)
        %AFACTORWITHOUTALEVELISREFUSEDWHATEVERTHECHOICE  uf_designmat cannot
        %   build a factor with an event that has no level, and
        %   uf_imputeMissing fills in numbers, so there is nothing to choose.
            EEG = UnfoldCovariatesTest.confoundedRecording();
            sides = {'left', 'right'};
            for k = 1:numel(EEG.event)
                EEG.event(k).side = sides{mod(k, 2) + 1};
            end
            A = find(arrayfun(@(e) isequal(e.bini, 1), EEG.event));
            EEG.event(A(4)).side = '';
            formulas = struct('bin', 'A', 'formula', 'y ~ 1 + cat(side)');

            err = UnfoldCovariatesTest.refusal(@() Unfold.binModel(EEG, 'Formulas', formulas, ...
                'MissingValues', 'median'));

            testCase.verifyEqual(err.identifier, 'Alakazam:Unfold:MissingValue');
            testCase.verifySubstring(err.message, 'cannot build a factor');
        end

        function marginalDrawsForOneFieldButNotForTwoMissingDifferently(testCase)
        %MARGINALDRAWSFORONEFIELDBUTNOTFORTWOMISSINGDIFFERENTLY  A toolbox
        %   behaviour kept as it is: uf_imputeMissing's 'marginal' reuses
        %   one list of drawn values from predictor to predictor, so two
        %   predictors missing different numbers of values stop it. That is
        %   refused, saying so; one field is drawn for as the toolbox does.
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            EEG = UnfoldCovariatesTest.confoundedRecording();
            rng(4);
            for k = 1:numel(EEG.event)
                EEG.event(k).extra = randn();
            end
            oneField = UnfoldCovariatesTest.withGaps(EEG, 'gain', 3);
            twoFields = UnfoldCovariatesTest.withGaps(oneField, 'extra', 1);
            args = {'WindowMs', [-100 400], 'ArtifactThresholdUv', 0, 'MissingValues', 'marginal'};

            [~, info] = Unfold.fitBins(oneField, args{:}, ...
                'Formulas', struct('bin', 'A', 'formula', 'y ~ 1 + gain'));
            err = UnfoldCovariatesTest.refusal(@() Unfold.fitBins(twoFields, args{:}, ...
                'Formulas', struct('bin', 'A', 'formula', 'y ~ 1 + gain + extra')));

            testCase.verifyEqual(info.missingValues, 'marginal');
            testCase.verifyEqual(err.identifier, 'Alakazam:Unfold:Marginal');
            testCase.verifySubstring(err.message, 'draws into the same list');
        end

        function aTermNotNamedIsDrawnAtTheToolboxsTenQuantiles(testCase)
        %ATERMNOTNAMEDISDRAWNATTHETOOLBOXSTENQUANTILES  Without values in
        %   EvaluateAt, uf_predictContinuous's own default: ten quantiles.
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            EEG = UnfoldCovariatesTest.confoundedRecording();
            formulas = struct('bin', {'A'}, 'formula', {'y ~ 1 + gain'});

            terms = Unfold.fitBins(EEG, 'WindowMs', [-100 400], 'ArtifactThresholdUv', 0, ...
                'Formulas', formulas, 'Output', 'terms');

            testCase.verifyEqual(nnz(startsWith({terms.bindesc.label}, 'A: gain = ')), 10);
        end

        function aTwoDimensionalSplineIsFittedAndEvaluated(testCase)
        %ATWODIMENSIONALSPLINEISFITTEDANDEVALUATED  A response that scales
        %   with the product of two fields, g * h: the bin's waveform is its
        %   events' average response, mean(g .* h), which only comes out if
        %   the surface is evaluated at each event's own pair; and the terms
        %   are the surface at pairs of values, named by both fields.
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            [EEG, truth] = UnfoldCovariatesTest.surfaceRecording();
            formulas = struct('bin', 'A', 'formula', 'y ~ 1 + 2dspl(g, h, 4)');

            fitted = Unfold.fitBins(EEG, 'WindowMs', [-100 400], 'ArtifactThresholdUv', 0, ...
                'BaselineMs', [], 'Formulas', formulas);
            terms = Unfold.fitBins(EEG, 'WindowMs', [-100 400], 'ArtifactThresholdUv', 0, ...
                'BaselineMs', [], 'Formulas', formulas, 'Output', 'terms', 'EvaluateAt', 'g = 1 2; h = 1.5');

            testCase.verifyEqual(max(fitted.data(1, :, 1)), truth.peakA, 'RelTol', 0.03, ...
                'A''s waveform is the mean of g * h over its events, times the response.');
            labels = {terms.bindesc.label};
            testCase.verifyEqual(labels(startsWith(labels, 'A: g')), ...
                {'A: g = 1, h = 1.5', 'A: g = 2, h = 1.5'});
            peak = @(label) max(terms.data(1, :, strcmp(labels, label)));
            testCase.verifyEqual(peak('A: g = 1, h = 1.5'), 1.5 * truth.waveformPeak, 'RelTol', 0.05);
            testCase.verifyEqual(peak('A: g = 2, h = 1.5'), 3 * truth.waveformPeak, 'RelTol', 0.05);
        end

        function anInteractionIsHeldAtThePooledValuesToo(testCase)
        %ANINTERACTIONISHELDATTHEPOOLEDVALUESTOO  cat(side) * g: the main
        %   effect of g was held at the pooled mean, but the interaction
        %   column kept the bin's own mean, so a bin whose "R" events had
        %   larger g than the pool still showed that as a bin difference.
        %   Every column with g in it is now at the pooled mean.
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            [EEG, truth] = UnfoldCovariatesTest.interactionRecording();
            formulas = struct('bin', {'A', 'B'}, 'formula', {'y ~ 1 + cat(side) * g', 'y ~ 1 + g'});

            fitted = Unfold.fitBins(EEG, 'WindowMs', [-100 400], 'ArtifactThresholdUv', 0, ...
                'BaselineMs', [], 'Formulas', formulas);

            testCase.verifyEqual(max(fitted.data(1, :, 1)), truth.peakA, 'RelTol', 0.03, ...
                'A at the pooled g: half its events at g, half (side R) at twice g.');
            testCase.verifyEqual(max(fitted.data(1, :, 2)), truth.peakB, 'RelTol', 0.03);
        end

        function aOneLetterFactorIsExplainedAsTheToolboxBuildsIt(testCase)
        %AONELETTERFACTORISEXPLAINEDASTHETOOLBOXBUILDSIT  Unfold 1.3.1 cannot
        %   build a factor with one-letter levels once another event type
        %   lacks the field (see Unfold.designMatrix). The toolbox is called
        %   as it is, and the message says why: it names the factor and what
        %   to rename.
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            EEG = UnfoldCovariatesTest.interactionRecording({'L', 'R'});
            formulas = struct('bin', {'A', 'B'}, 'formula', {'y ~ 1 + cat(side)', 'y ~ 1'});

            try
                Unfold.fitBins(EEG, 'WindowMs', [-100 400], 'ArtifactThresholdUv', 0, 'Formulas', formulas);
                err = MException('none:none', 'no error');
            catch err
            end

            testCase.verifyEqual(err.identifier, 'Alakazam:Unfold:Formula');
            testCase.verifySubstring(err.message, 'reads the levels as characters rather than as text');
            testCase.verifySubstring(err.message, '"side"');
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

        function [EEG, gaps, known] = withGaps(EEG, field, count)
        %WITHGAPS  EEG with COUNT events of bin A, spread over the
        %   recording, given no number for FIELD (NaN). GAPS are their rows
        %   of EEG.event, KNOWN the values bin A's other events keep.
            A = find(arrayfun(@(e) isequal(e.bini, 1), EEG.event));
            gaps = A(round(linspace(2, numel(A) - 1, count)));
            known = [EEG.event(setdiff(A, gaps)).(field)];
            [EEG.event(gaps).(field)] = deal(NaN);
        end

        function err = refusal(call)
        %REFUSAL  The error CALL throws, or a failure if it throws none.
            err = MException('Test:NoError', 'No error was thrown.');
            try
                call();
            catch err
            end
        end

        function [EEG, formulas] = anglesNearNorth()
        %ANGLESNEARNORTH  UnfoldBinsTest's recording with an angle on every
        %   event, near 0 or near 360 degrees, so the mean angle (about 180)
        %   is one no event has; Frequent is fitted with a circular spline of
        %   it.
            EEG = UnfoldBinsTest.recording();
            rng(5);
            for k = 1:numel(EEG.event)
                EEG.event(k).ang = mod(10 * sign(randn()) + 4 * randn(), 360);
            end
            formulas = struct('bin', 'Frequent', 'formula', 'y ~ 1 + circspl(ang, 5, 0, 360)');
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
            truth = struct('peak', max(waveform) * mean(gain), 'waveformPeak', max(waveform));
        end

        function EEG = withPositions(EEG)
        %WITHPOSITIONS  Two numeric fields, x and z, on every event, unrelated
        %   to the data: the two coordinates a 2D spline is made of.
            rng(9);
            for k = 1:numel(EEG.event)
                EEG.event(k).x = rand();
                EEG.event(k).z = rand();
            end
        end

        function [EEG, truth] = surfaceRecording()
        %SURFACERECORDING  Bin A's events scale with g * h, two independent
        %   fields from 0.5 to 2.5; bin B's events are a plain response. The
        %   mean of g * h (about 2.25) differs from the mean of g * g (about
        %   2.58), so a surface evaluated at the wrong pairs shows.
            srate = 100;
            npnts = 60000;
            t = (0:round(0.3 * srate)) / srate;
            waveform = 6 * sin(pi * t / 0.3) .* exp(-t / 0.2);

            rng(41);
            n = 150;
            first = round(linspace(300, 59000, n) + 30 * randn(1, n));
            second = round(first + 90 + 30 * rand(1, n));
            g = 0.5 + 2 * rand(1, n);
            h = 0.5 + 2 * rand(1, n);

            data = 0.05 * randn(1, npnts);
            for k = 1:n
                data = UnfoldBinsTest.addResponse(data, first(k), g(k) * h(k) * waveform);
                data = UnfoldBinsTest.addResponse(data, second(k), waveform);
            end

            event = struct('type', {}, 'latency', {}, 'bini', {}, 'g', {}, 'h', {});
            for k = 1:n
                event(end + 1) = struct('type', 'A', 'latency', first(k), 'bini', 1, ...
                    'g', g(k), 'h', h(k)); %#ok<AGROW>
                event(end + 1) = struct('type', 'B', 'latency', second(k), 'bini', 2, ...
                    'g', 0, 'h', 0); %#ok<AGROW>
            end
            [~, order] = sort([event.latency]);
            event = event(order);

            EEG = struct('data', data, 'srate', srate, 'pnts', npnts, 'trials', 1, ...
                'nbchan', 1, 'xmin', 0, 'xmax', (npnts - 1) / srate, ...
                'times', (0:npnts - 1) / srate * 1000, 'DataFormat', 'CONTINUOUS', ...
                'chanlocs', struct('labels', {'Cz'}), 'event', event, ...
                'bindesc', struct('index', {1, 2}, 'label', {'A', 'B'}, 'combo', {[], []}));
            truth = struct('peakA', max(waveform) * mean(g .* h), 'waveformPeak', max(waveform));
        end

        function [EEG, truth] = interactionRecording(sides)
        %INTERACTIONRECORDING  Bin A's events scale with g on side left and
        %   with twice g on side right; bin B's scale with g. A's right
        %   events have the largest g (2.5 to 3.5, against 0.5 to 1.5 on the
        %   left and 1.5 to 2.5 in B), so A held at its own g would look
        %   larger than A held at the pooled g, which is the one a control
        %   compares at. INTERACTIONRECORDING({'L', 'R'}) names the sides
        %   with one letter each, which Unfold 1.3.1 cannot build (see
        %   Unfold.designMatrix).
            if nargin < 1
                sides = {'left', 'right'};
            end
            srate = 100;
            npnts = 40000;
            t = (0:round(0.3 * srate)) / srate;
            waveform = 6 * sin(pi * t / 0.3) .* exp(-t / 0.2);

            rng(31);
            n = 80;
            first = round(linspace(300, 39000, n) + 30 * randn(1, n));
            second = round(first + 90 + 30 * rand(1, n));
            right = mod(1:n, 2) == 0;
            g = [0.5 + rand(1, n), 1.5 + rand(1, n)];      % A on side L, then B
            g(right) = g(right) + 2;                        % A on side R: 2.5 to 3.5
            amplitude = g;
            amplitude(right) = 2 * g(right);

            data = 0.05 * randn(1, npnts);
            latencies = [first second];
            for k = 1:numel(latencies)
                data = UnfoldBinsTest.addResponse(data, latencies(k), amplitude(k) * waveform);
            end

            event = struct('type', {}, 'latency', {}, 'bini', {}, 'g', {}, 'side', {});
            for k = 1:n
                event(end + 1) = struct('type', 'A', 'latency', first(k), 'bini', 1, ...
                    'g', g(k), 'side', sides{1 + right(k)}); %#ok<AGROW>
            end
            for k = 1:n
                event(end + 1) = struct('type', 'B', 'latency', second(k), 'bini', 2, ...
                    'g', g(n + k), 'side', sides{1}); %#ok<AGROW>
            end
            [~, order] = sort([event.latency]);
            event = event(order);

            EEG = struct('data', data, 'srate', srate, 'pnts', npnts, 'trials', 1, ...
                'nbchan', 1, 'xmin', 0, 'xmax', (npnts - 1) / srate, ...
                'times', (0:npnts - 1) / srate * 1000, 'DataFormat', 'CONTINUOUS', ...
                'chanlocs', struct('labels', {'Cz'}), 'event', event, ...
                'bindesc', struct('index', {1, 2}, 'label', {'A', 'B'}, 'combo', {[], []}));
            pooled = mean(g);
            truth = struct('peakA', max(waveform) * 1.5 * pooled, 'peakB', max(waveform) * pooled);
        end
    end
end

% ======================================================================= %
function d = maxDifference(fitted, binA, binB)
%MAXDIFFERENCE  The largest gap between two fitted bins, in microvolts.
    d = max(abs(fitted.data(1, :, binA) - fitted.data(1, :, binB)));
end
