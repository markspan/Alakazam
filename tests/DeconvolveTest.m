classdef DeconvolveTest < matlab.unittest.TestCase
%DECONVOLVETEST  The Deconvolve transformation: the plugin contract around
%   the fit, rather than the fit itself (that is UnfoldBinsTest's job).
%
%   THE CASE THAT MATTERS MOST HERE is a plain continuous recording with no
%   bins on it at all, because that is the only node a user can actually run
%   this on. Deconvolve needs continuous data AND bins, and until it defined
%   its own bins those two demands could not both be met: a DefineBins node
%   with an epoch window has had its continuous data replaced by the epoch
%   stack, and the continuous node it came from carries no bins, so each was
%   refused for lacking what the other had. A dataset that does already carry
%   tags (DefineBins with both epoch fields left blank) still works, and both
%   routes are pinned below.
%
%   THE REFUSAL ORDER IS THE OTHER THING. A dataset that cannot be
%   deconvolved at all (epoched) has to be refused on sight, before any
%   dialog: these tests call the interactive form for that case, so the test
%   hanging on a dialog would be the failure.
%
%   Run with: runtests('tests/DeconvolveTest.m').
%
%   See also DECONVOLVE, DECONVOLVEDIALOG, UNFOLDBINSTEST, UNFOLD.FITBINS.

    properties (Constant)
        % Distinguishes the fixture's two stimulus markers by name, which is
        % what a bin script has to work from. The fixture's own events are all
        % typed 'stim' and told apart by a pre-set .bini, which is precisely
        % what an untagged recording does not have.
        BinScript = ['bin 1 "Frequent" "S1"' newline 'bin 2 "Rare" "S2"']
    end

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
        function epochedDataIsRefusedBeforeAnyDialog(testCase)
        %EPOCHEDDATAISREFUSEDBEFOREANYDIALOG  Called with no options, this
        %   would normally open a dialog. It must not get that far, and the
        %   test completing rather than hanging is the proof that it did not.
            EEG = UnfoldBinsTest.recording();
            EEG.DataFormat = 'EPOCHED';

            testCase.verifyError(@() Deconvolve(EEG), 'Alakazam:Unfold:NeedsContinuous');
        end

        function theRefusalSaysWhichNodeToUseInstead(testCase)
        %THEREFUSALSAYSWHICHNODETOUSEINSTEAD  The message is the whole point
        %   of the refusal: an epoched dataset can never be made to work, so
        %   it has to name the node that can.
            EEG = UnfoldBinsTest.recording();
            EEG.DataFormat = 'EPOCHED';

            try
                Deconvolve(EEG);
                message = '';
            catch err
                message = err.message;
            end

            testCase.verifySubstring(message, 'continuous recording');
            testCase.verifySubstring(message, 'asks for the bins');
        end

        function aScriptTurnsAnUntaggedRecordingIntoTheBinsToFit(testCase)
        %ASCRIPTTURNSANUNTAGGEDRECORDINGINTOTHEBINSTOFIT  The mapping the
        %   transformation relies on, checked without the toolbox: the script
        %   Deconvolve is given produces exactly the bins it will fit.
            EEG = DeconvolveTest.untaggedRecording();
            testCase.verifyFalse(isfield(EEG, 'bindesc'), 'The fixture starts with no bins.');

            plan = Unfold.binModel(DefineBins(EEG, struct('script', DeconvolveTest.BinScript)));

            testCase.verifyEqual(plan.binLabels, {'Frequent', 'Rare'});
            testCase.verifyEqual(plan.binCounts, [90 30], ...
                'Every S1 and S2 event is matched, and none of them twice.');
            testCase.verifyEqual(plan.nuisanceTypes, {'evt_response'}, ...
                'The unbinned response events are still modelled.');
        end

        function withNeitherBinsNorAScriptItSaysSo(testCase)
        %WITHNEITHERBINSNORASCRIPTITSAYSSO  The replay path with nothing to
        %   fit into. Interactively the dialog asks; given options that name
        %   no bins, there is nothing left to ask and it has to refuse.
            EEG = DeconvolveTest.untaggedRecording();
            options = struct('windowMs', [-100 500]);

            testCase.verifyError(@() Deconvolve(EEG, options), 'Alakazam:Unfold:NoBins');
        end

        function binsWithoutTagsAreRefusedOnReplay(testCase)
            EEG = UnfoldBinsTest.recording();
            EEG.event = rmfield(EEG.event, 'bini');
            options = struct('windowMs', [-100 500]);

            testCase.verifyError(@() Deconvolve(EEG, options), 'Alakazam:Unfold:NoBinTags');
        end

        function aDcOffsetIsRefusedWithItsRemedy(testCase)
        %ADCOFFSETISREFUSEDWITHITSREMEDY  The Chapter3 case: DC-coupled data
        %   sitting 11 mV from zero. It averages perfectly (Baseline removes
        %   the offset per epoch) and deconvolves into thousands of
        %   microvolts of nothing, because a time-expanded design has no
        %   constant term to absorb a standing voltage. Refused by name,
        %   before the fit, rather than plotted.
            EEG = DeconvolveTest.untaggedRecording();
            EEG.data = EEG.data - 11463;
            options = DeconvolveTest.options();

            try
                Deconvolve(EEG, options);
                err = MException('none:none', 'no error');
            catch err
            end

            testCase.verifyEqual(err.identifier, 'Alakazam:Unfold:DcOffset');
            testCase.verifySubstring(err.message, 'DCDetrend');
        end

        function theOptionsSurviveATemplateRoundTrip(testCase)
        %THEOPTIONSSURVIVEATEMPLATEROUNDTRIP  Saved templates and the
        %   exported analysis script both carry options through JSON, so a
        %   struct that does not survive that is a transformation that
        %   cannot be replayed on another dataset. The bin script is the
        %   field with something to lose here: it is multi-line text.
            options = DeconvolveTest.options();

            restored = jsondecode(jsonencode(options));

            testCase.verifyEqual(restored.binScript, options.binScript, ...
                'The newlines in the bin script came back as they went in.');
            testCase.verifyEqual(restored.windowMs(:)', options.windowMs);
            testCase.verifyEqual(restored.modelOtherEvents, options.modelOtherEvents);
            testCase.verifyEqual(restored.artifactThresholdUv, options.artifactThresholdUv);
        end
    end

    methods (Test, TestTags = {'External'})
        function itFitsAContinuousRecordingItBinsItself(testCase)
        %ITFITSACONTINUOUSRECORDINGITBINSITSELF  The whole point, end to end:
        %   in goes a continuous recording with events and no bins, out comes
        %   one waveform per bin in Average's shape.
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            EEG = DeconvolveTest.untaggedRecording();

            fitted = Deconvolve(EEG, DeconvolveTest.options());

            testCase.verifyEqual(char(string(fitted.DataFormat)), 'Averaged');
            testCase.verifyEqual(size(fitted.data, 3), 2, 'One waveform per bin.');
            testCase.verifyEqual({fitted.bindesc.label}, {'Frequent', 'Rare'});
            testCase.verifyEqual(fitted.etc.alz.unfold.binCounts, [90 30]);
        end

        function replayingStoredOptionsNeedsNoDialog(testCase)
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            EEG = UnfoldBinsTest.recording();
            options = DeconvolveTest.options('binScript', '', 'windowMs', [-100 500]);

            [fitted, used] = Deconvolve(EEG, options);

            testCase.verifyEqual(char(string(fitted.DataFormat)), 'Averaged');
            testCase.verifyEqual(size(fitted.data, 3), numel(EEG.bindesc), ...
                'With no script of its own it fitted the bins already on the dataset.');
            testCase.verifyEqual(used, options, 'Replay returns the options it was given.');
            testCase.verifyGreaterThanOrEqual(fitted.times(1), -100 - 1000 / EEG.srate, ...
                'The stored window is the one that was used, not the default.');
            testCase.verifyLessThanOrEqual(fitted.times(end), 500 + 1000 / EEG.srate);
        end

        function anOffsetSmallerThanTheSignalStillFits(testCase)
        %ANOFFSETSMALLERTHANTHESIGNALSTILLFITS  The offset guard is scale-free,
        %   judged on the median channel against its own variation, so it must
        %   not fire on a recording that merely fails to average exactly zero.
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            EEG = DeconvolveTest.untaggedRecording();
            EEG.data = EEG.data + 0.2 * std(EEG.data(1, :));

            fitted = Deconvolve(EEG, DeconvolveTest.options());

            testCase.verifyTrue(all(isfinite(fitted.data), 'all'));
        end

        function theBaselineWindowIsHonoured(testCase)
        %THEBASELINEWINDOWISHONOURED  A beta's zero is wherever the model put
        %   it, so the correction is what makes it readable beside an average.
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            EEG = DeconvolveTest.untaggedRecording();

            corrected = Deconvolve(EEG, DeconvolveTest.options('baselineMs', [-200 0]));
            asFitted = Deconvolve(EEG, DeconvolveTest.options('baselineMs', []));

            pre = corrected.times >= -200 & corrected.times <= 0;
            for b = 1:size(corrected.data, 3)
                testCase.verifyEqual(mean(corrected.data(:, pre, b), 2), ...
                    zeros(size(corrected.data, 1), 1), 'AbsTol', 1e-9, ...
                    'Every corrected waveform averages zero over the baseline window.');
            end
            testCase.verifyEqual(corrected.etc.alz.unfold.baseline, [-200 0]);
            testCase.verifyEmpty(asFitted.etc.alz.unfold.baseline);
            shift = corrected.data - asFitted.data;
            testCase.verifyEqual(shift, repmat(mean(shift, 2), 1, size(shift, 2), 1), ...
                'AbsTol', 1e-9, 'The correction is a shift per waveform and nothing else.');
        end

        function aThresholdThatMarksEverythingIsRefused(testCase)
        %ATHRESHOLDTHATMARKSEVERYTHINGISREFUSED  Refused before the fit rather
        %   than after minutes of not converging, which is how the Chapter3
        %   run produced a plot of NaN.
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            EEG = DeconvolveTest.untaggedRecording();
            options = DeconvolveTest.options('artifactThresholdUv', 0.001);

            try
                Deconvolve(EEG, options);
                err = MException('none:none', 'no error');
            catch err
            end

            testCase.verifyEqual(err.identifier, 'Alakazam:Unfold:TooMuchExcluded');
            testCase.verifySubstring(err.message, 'absolute limit');
        end

        function aCutInTheRecordingIsNotModelledAcross(testCase)
        %ACUTINTHERECORDINGISNOTMODELLEDACROSS  A boundary is a join between
        %   two moments that were never adjacent, so a response window
        %   spanning one is being fitted across an edit. The toolbox keeps
        %   boundary events out of the design but knows nothing about the data
        %   around them, so the interval is excluded here.
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            EEG = DeconvolveTest.untaggedRecording();
            cut = 10000;
            EEG.event(end + 1) = struct('type', 'boundary', 'latency', cut);
            [~, order] = sort([EEG.event.latency]);
            EEG.event = EEG.event(order);

            fitted = Deconvolve(EEG, DeconvolveTest.options('artifactThresholdUv', 0));

            intervals = fitted.etc.alz.unfold.excludedIntervals;
            spans = intervals(:, 1) <= cut & intervals(:, 2) >= cut;
            testCase.verifyTrue(any(spans), 'The cut itself is inside an excluded interval.');
            testCase.verifyGreaterThanOrEqual(intervals(spans, 2) - intervals(spans, 1), ...
                EEG.srate, 'It reaches a response window either side of the cut.');
            testCase.verifyTrue(all(isfinite(fitted.data), 'all'));
        end

        function theChosenEventCodesSurviveBeingStored(testCase)
        %THECHOSENEVENTCODESSURVIVEBEINGSTORED  A stored template goes through
        %   JSON, where an empty list comes back as [] and one code comes
        %   back as a cell of one. "None" must still mean none after that,
        %   not quietly revert to modelling everything.
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            EEG = DeconvolveTest.untaggedRecording();
            none = jsondecode(jsonencode(DeconvolveTest.options('otherEvents', {})));
            some = jsondecode(jsonencode(DeconvolveTest.options('otherEvents', {'response'})));

            fittedNone = Deconvolve(EEG, none);
            fittedSome = Deconvolve(EEG, some);

            testCase.verifyEmpty(fittedNone.etc.alz.unfold.nuisanceTypes, ...
                'An empty choice, stored and restored, still models no unbinned code.');
            testCase.verifyEqual(fittedSome.etc.alz.unfold.nuisanceTypes, {'evt_response'});
        end

        function theResultCarriesItsOwnProvenance(testCase)
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            EEG = DeconvolveTest.untaggedRecording();
            options = DeconvolveTest.options('modelOtherEvents', false);

            fitted = Deconvolve(EEG, options);

            info = fitted.etc.alz.unfold;
            testCase.verifyEqual(info.binLabels, {'Frequent', 'Rare'});
            testCase.verifyEmpty(info.nuisanceTypes, ...
                'Asked not to model the other events, it did not model them.');
            testCase.verifyEqual(info.window, options.windowMs);
            testCase.verifyFalse(info.hasStandardError);
        end
    end

    methods (Static)
        function EEG = untaggedRecording()
        %UNTAGGEDRECORDING  UnfoldBinsTest's recording as it would arrive from
        %   an importer: the same data and events, but the two stimulus classes
        %   told apart by their markers ('S1', 'S2') instead of by bin tags,
        %   and no bins on it at all. This is the node a user selects.
            EEG = UnfoldBinsTest.recording();
            for k = 1:numel(EEG.event)
                if any(EEG.event(k).bini == 1)
                    EEG.event(k).type = 'S1';
                elseif any(EEG.event(k).bini == 2)
                    EEG.event(k).type = 'S2';
                end
            end
            EEG.event = rmfield(EEG.event, 'bini');
            EEG = rmfield(EEG, 'bindesc');
        end

        function options = options(varargin)
        %OPTIONS  A full options struct, with any field overridden by name.
            options = struct('binScript', DeconvolveTest.BinScript, ...
                'windowMs', [-200 800], 'modelOtherEvents', true, ...
                'artifactThresholdUv', 0, 'artifactWindowMs', 2000, 'artifactStepMs', 100);
            for k = 1:2:numel(varargin)
                options.(varargin{k}) = varargin{k + 1};
            end
        end
    end
end
