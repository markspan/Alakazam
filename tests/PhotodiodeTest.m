classdef PhotodiodeTest < matlab.unittest.TestCase
%PHOTODIODETEST  Photodiode onset detection and display-delay measurement.
%
%   THE FIXTURE IS BUILT FROM MEASURED CHARACTERISTICS, NOT INVENTED. The
%   background here is 50 Hz flicker of about 2400 units peak to peak on a
%   baseline near 5000, because that is what a real photodiode channel from
%   this lab looks like when no patch is presented: measured across four
%   recordings in Data/BCN2025, which also contained a dead channel sitting
%   at zero and one isolated fifteen-fold artefact spike. Those are the
%   three shapes the detector has to survive, so those are the three shapes
%   it is tested against.
%
%   Testing against a clean synthetic square wave would have passed
%   trivially and shipped a detector that fires fifty times a second on real
%   data. The recordings themselves cannot be a test dependency: Data/ is
%   gitignored and must never be published, so their measured PARAMETERS are
%   encoded here instead.
%
%   What is still unvalidated, and should be checked against a recording
%   that has real patches: the shape of a genuine patch edge. Its rise time,
%   any overshoot, and how long the patch stays lit are guesses here.
%
%   Run with: runtests('tests/PhotodiodeTest.m').

    properties (Constant)
        Srate = 1000        % as recorded
        Baseline = 5000     % measured: median of the real diode channel
        Flicker = 1200      % measured: amplitude, giving ~2400 peak to peak
        FlickerHz = 50      % measured: mains
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations', 'Photodiode')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations')));
        end
    end

    methods (Test)
        % ---- refusing to see what is not there --------------------------
        function flickerAloneProducesNoOnsets(testCase)
        %FLICKERALONEPRODUCESNOONSETS  The test this detector exists to
        %   pass. A plain threshold at the midpoint of this signal yields
        %   fifty onsets a second, forever, and looks like it is working.
            signal = testCase.flickerOnly(60);

            [onsets, info] = detectDiodeOnsets(signal, testCase.Srate);

            testCase.verifyEmpty(onsets, ...
                sprintf('%d onsets invented from pure flicker.', numel(onsets)));
            testCase.verifyLessThan(info.separation, 3);
            testCase.verifySubstring(info.reason, 'two states');
        end

        function aDeadChannelProducesNoOnsets(testCase)
        %ADEADCHANNELPRODUCESNOONSETS  One real recording had the diode
        %   unplugged: the channel sat at zero with a few units of noise.
            rng(7);
            signal = randn(1, 60 * testCase.Srate) * 60;

            testCase.verifyEmpty(detectDiodeOnsets(signal, testCase.Srate));
        end

        function anIsolatedSpikeIsNotAnOnset(testCase)
        %ANISOLATEDSPIKEISNOTANONSET  Another real recording carried a
        %   single fifteen-fold excursion matching no trigger. A patch that
        %   lasts one millisecond is not a patch.
            signal = testCase.flickerOnly(60);
            signal(20000) = testCase.Baseline * 15;

            testCase.verifyEmpty(detectDiodeOnsets(signal, testCase.Srate));
        end

        % ---- finding what is there ---------------------------------------
        function patchesInRealisticFlickerAreFound(testCase)
            [signal, truth] = testCase.withPatches(60, 20000, 100);

            onsets = detectDiodeOnsets(signal, testCase.Srate);

            testCase.verifyEqual(numel(onsets), numel(truth), ...
                sprintf('Found %d of %d patches.', numel(onsets), numel(truth)));
        end

        function onsetTimingIsUnbiased(testCase)
        %ONSETTIMINGISUNBIASED  The property that matters most, and the one
        %   that was wrong first. Smoothing turns a step into a ramp, and
        %   thresholding that ramp put every onset a consistent 7 ms early.
        %   An instrument for measuring display delay must not have a delay
        %   of its own, so detection is coarse but timing is refined against
        %   the unsmoothed channel.
            [signal, truth] = testCase.withPatches(60, 20000, 100);

            onsets = detectDiodeOnsets(signal, testCase.Srate);

            testCase.assertEqual(numel(onsets), numel(truth));
            err = onsets(:)' - truth(:)';
            testCase.verifyEqual(median(err), 0, 'AbsTol', 1, ...
                sprintf('Systematic timing bias of %+.1f ms.', median(err)));
            testCase.verifyLessThanOrEqual(max(abs(err)), 3);
        end

        function anOnsetIsTimedToTheFootOfTheRamp(testCase)
        %ANONSETISTIMEDTOTHEFOOTOFTHERAMP  A real display does not step, it
        %   ramps: the panel takes a few milliseconds to reach full
        %   brightness. The moment being measured is when it STARTED, since
        %   the climb after that is the monitor's own pixel response, not
        %   anything the presentation software did.
        %
        %   The tolerance is not zero, and the reason is in refineOnsets: on
        %   a channel carrying this much flicker, the foot cannot be called
        %   until the ramp has climbed clear of the noise, which on a 10 ms
        %   ramp is a millisecond or so. Late by a known millisecond beats
        %   late by half the panel's rise time.
            rampMs = 10;
            [signal, truth] = testCase.withRampedPatches(60, 20000, 100, rampMs);

            onsets = detectDiodeOnsets(signal, testCase.Srate);

            testCase.assertEqual(numel(onsets), numel(truth), ...
                sprintf('Found %d of %d patches.', numel(onsets), numel(truth)));
            err = onsets(:)' - truth(:)';
            testCase.verifyLessThanOrEqual(median(err), 3, ...
                sprintf(['Onsets sit %+.1f ms after the foot of the ramp; half height ' ...
                    'would be %+.1f.'], median(err), rampMs / 2));
            testCase.verifyGreaterThanOrEqual(median(err), -1, ...
                'Onsets sit before the ramp even began.');
        end

        function aSlowPanelIsNotChargedToTheTimingChain(testCase)
        %ASLOWPANELISNOTCHARGEDTOTHETIMINGCHAIN  The point of timing to the
        %   foot. Two recordings identical but for the panel's rise time, 4
        %   ms against 16 ms, must report nearly the same onset: that
        %   difference belongs to the monitor.
        %
        %   Timing to half height would separate them by exactly half the
        %   difference in rise time, 6 ms, and that is the number this case
        %   is really testing against. It does not demand zero, because the
        %   noise floor makes the callable foot a little later on the slower
        %   ramp, but it does demand a large improvement on 6.
            [fast, truth] = testCase.withRampedPatches(60, 20000, 100, 4);
            slow = testCase.withRampedPatches(60, 20000, 100, 16);

            fastOnsets = detectDiodeOnsets(fast, testCase.Srate);
            slowOnsets = detectDiodeOnsets(slow, testCase.Srate);

            testCase.assertEqual(numel(fastOnsets), numel(truth));
            testCase.assertEqual(numel(slowOnsets), numel(truth));

            drift = median(slowOnsets(:)' - truth(:)') - median(fastOnsets(:)' - truth(:)');
            atHalfHeight = (16 - 4) / 2;

            testCase.verifyLessThan(abs(drift), atHalfHeight / 2, ...
                sprintf(['A panel three times slower moved the reported onset by %.1f ms. ' ...
                    'Timing to half height would move it %.1f, so the rise time is still ' ...
                    'largely being measured.'], drift, atHalfHeight));
        end

        function aPatchSmallerThanTheFlickerIsRefused(testCase)
        %APATCHSMALLERTHANTHEFLICKERISREFUSED  Where the detector gives up
        %   is worth pinning: a step well under the flicker amplitude cannot
        %   be told from the flicker, and guessing would be worse than
        %   declining. The dialog offers a manual threshold for this case.
            [signal, ~] = testCase.withPatches(60, 400, 100);

            testCase.verifyEmpty(detectDiodeOnsets(signal, testCase.Srate));
        end

        function aManualThresholdOverridesTheRefusal(testCase)
            [signal, truth] = testCase.withPatches(60, 3000, 100);
            opts = struct('Threshold', testCase.Baseline + 2000);

            onsets = detectDiodeOnsets(signal, testCase.Srate, opts);

            testCase.verifyGreaterThan(numel(onsets), numel(truth) * 0.8);
        end

        % ---- the measurement ----------------------------------------------
        function theDelayIsMeasuredFromTheTriggerBefore(testCase)
        %THEDELAYISMEASUREDFROMTHETRIGGERBEFORE  A screen cannot change
        %   before it was told to, so an onset pairs with the nearest
        %   PRECEDING trigger. Pairing to the nearest in either direction
        %   would report negative lags and average them in as though real.
            onsets = [1050, 3050, 5050];
            events = struct('type', {'S', 'S', 'S'}, 'latency', {1000, 3000, 5000});

            report = diodeTriggerDelay(onsets, events, testCase.Srate);

            testCase.verifyEqual(report.n, 3);
            testCase.verifyEqual(report.medianMs, 50, 'AbsTol', 1e-9);
            testCase.verifySubstring(report.summary, 'shift these triggers by +50 ms');
        end

        function anOnsetWithNoTriggerNearbyIsLeftOut(testCase)
            onsets = [1050, 90000];
            events = struct('type', {'S'}, 'latency', {1000});

            report = diodeTriggerDelay(onsets, events, testCase.Srate, ...
                struct('MaxLagMs', 200));

            testCase.verifyEqual(report.n, 1);
            testCase.verifyEqual(report.unpaired, 1);
            testCase.verifySubstring(report.summary, 'left out');
        end

        function theMedianIsReportedAlongsideTheMean(testCase)
        %THEMEDIANISREPORTEDALONGSIDETHEMEAN  Display lag is near-constant
        %   plus refresh quantisation, but a dropped frame is a whole-frame
        %   outlier that moves a mean and not a median. Both are reported so
        %   a gap between them is visible.
            % One trial late by three frames at 60 Hz. Deliberately within
            % the 200 ms pairing window: an outlier further out than that is
            % not a dropped frame, it is a mis-pairing, and diodeTriggerDelay
            % correctly declines to pair it at all rather than averaging it
            % in. (This test asserted a 300 ms outlier at first, and was
            % wrong for exactly that reason.)
            onsets = [1050, 2050, 3050, 4050, 5100];
            events = struct('type', repmat({'S'}, 1, 5), ...
                'latency', {1000, 2000, 3000, 4000, 5000});

            report = diodeTriggerDelay(onsets, events, testCase.Srate);

            testCase.verifyEqual(report.medianMs, 50, 'AbsTol', 1e-9);
            testCase.verifyGreaterThan(report.meanMs, report.medianMs);
        end

        function noOnsetsIsReportedNotCrashed(testCase)
            report = diodeTriggerDelay([], struct('type', {'S'}, 'latency', {100}), 1000);

            testCase.verifyEqual(report.n, 0);
            testCase.verifySubstring(report.summary, 'nothing to compare');
        end

        % ---- the transformation --------------------------------------------
        function measureModeChangesNothing(testCase)
        %MEASUREMODECHANGESNOTHING  Measuring is an observation. The events
        %   must come back untouched, or the correction that follows would
        %   be applied to something already altered.
            EEG = testCase.eegWithPatches();
            opts = struct('Channel', 'PhotoDiode', 'Mode', 'measure');

            out = testCase.verifyWarning(@() Photodiode(EEG, opts), ...
                'Alakazam:Photodiode:delay');

            testCase.verifyEqual(out.event, EEG.event);
            testCase.verifyGreaterThan(out.DiodeReport.n, 0);
        end

        function eventsModeAddsThemInLatencyOrder(testCase)
        %EVENTSMODEADDSTHEMINLATENCYORDER  EEGLAB assumes EEG.event is
        %   sorted by latency; appending at the end would break that.
            EEG = testCase.eegWithPatches();
            opts = struct('Channel', 'PhotoDiode', 'Mode', 'events');

            out = Photodiode(EEG, opts);

            testCase.verifyGreaterThan(numel(out.event), numel(EEG.event));
            testCase.verifyEqual([out.event.latency], sort([out.event.latency]));
        end

        function anAddedEventIsNamedAfterItsOwnTrigger(testCase)
        %ANADDEDEVENTISNAMEDAFTERITSOWNTRIGGER  One name for every diode
        %   onset would say only that the screen changed, leaving every step
        %   downstream to work out which change it was. Carrying the
        %   trigger's own name means these can be binned and epoched exactly
        %   like the triggers they stand in for.
            EEG = testCase.eegWithPatches();   % every trigger is "S1"

            out = Photodiode(EEG, struct('Channel', 'PhotoDiode', 'Mode', 'events'));

            added = setdiff({out.event.type}, {EEG.event.type});
            testCase.verifyEqual(sort(added), {'S1PD'}, ...
                'A diode onset answering "S1" should be added as "S1PD".');
        end

        function theSuffixKeepsTheTwoInstantsApart(testCase)
        %THESUFFIXKEEPSTHETWOINSTANTSAPART  The diode event and its trigger
        %   are tens of milliseconds apart. Naming them identically would
        %   leave nobody able to tell which timing they had epoched to.
            EEG = testCase.eegWithPatches();

            out = Photodiode(EEG, struct('Channel', 'PhotoDiode', 'Mode', 'events'));

            triggers = strcmp({out.event.type}, 'S1');
            diodes = strcmp({out.event.type}, 'S1PD');
            testCase.assertGreaterThan(sum(diodes), 0);
            testCase.verifyEqual(sum(triggers), numel(EEG.event), ...
                'The original triggers should still be there, under their own name.');

            % And the diode events really are the later of the two.
            testCase.verifyGreaterThan(min([out.event(diodes).latency]), ...
                min([out.event(triggers).latency]));
        end

        function theSuffixCanBeChanged(testCase)
            EEG = testCase.eegWithPatches();

            out = Photodiode(EEG, struct('Channel', 'PhotoDiode', 'Mode', 'events', ...
                'EventSuffix', '_screen'));

            testCase.verifyTrue(any(strcmp({out.event.type}, 'S1_screen')));
        end

        function anInterveningMarkerStealsThePairing(testCase)
        %ANINTERVENINGMARKERSTEALSTHEPAIRING  Reported from real data: 31
        %   s106 triggers but only 30 s106PD, and one s52 that had somehow
        %   acquired an s52PD despite never putting anything on screen.
        %
        %   Those are one event, not two faults. An onset is paired with the
        %   nearest event BEFORE it, and with no restriction on type that
        %   means any event at all, so a marker landing between a stimulus
        %   trigger and its screen change takes the onset from the trigger
        %   that caused it. The stimulus type comes up one short and the
        %   interloper gains one, which is exactly the arithmetic reported.
            [EEG, nTrials] = testCase.eegWithAnInterveningMarker();

            out = Photodiode(EEG, struct('Channel', 'PhotoDiode', 'Mode', 'events'));
            types = {out.event.type};

            testCase.verifyEqual(sum(strcmp(types, 's106')), nTrials);
            testCase.verifyEqual(sum(strcmp(types, 's106PD')), nTrials - 1, ...
                'The stimulus type should be one short, which is the symptom.');
            testCase.verifyEqual(sum(strcmp(types, 's52PD')), 1, ...
                'And the intervening marker should be the one that took it.');
        end

        function namingTheTriggersStopsTheTheft(testCase)
        %NAMINGTHETRIGGERSSTOPSTHETHEFT  The cure for the case above, and
        %   the reason Types is worth exposing: restrict which event types
        %   may own an onset and the marker is no longer a candidate, so
        %   every onset goes back to the trigger that caused it.
            [EEG, nTrials] = testCase.eegWithAnInterveningMarker();

            out = Photodiode(EEG, struct('Channel', 'PhotoDiode', 'Mode', 'events', ...
                'Types', {{'s106'}}));
            types = {out.event.type};

            testCase.verifyEqual(sum(strcmp(types, 's106PD')), nTrials, ...
                'Every onset should now belong to the trigger that caused it.');
            testCase.verifyEqual(sum(strcmp(types, 's52PD')), 0, ...
                'The marker should no longer be able to take one.');
        end

        function aTriggerSentAtTheFlipStillOwnsItsOnset(testCase)
        %ATRIGGERSENTATTHEFLIPSTILLOWNSITSONSET  From a real recording. One
        %   lab's stimulus markers are sent AT the flip rather than before
        %   it: median lag 2.0 ms, minimum 0.0. At that distance a single
        %   sample of movement in where the edge is called puts the onset in
        %   front of its own trigger, and a strict "trigger must come first"
        %   rule then drops the pair. The symptom is a count one short, 30
        %   diode events for 31 triggers, that comes and goes as smoothing
        %   or threshold changes.
            srate = testCase.Srate;
            [signal, truth] = testCase.withPatches(30, 20000, 100);

            % Every trigger one sample AFTER the screen change.
            events = struct('type', repmat({'s106'}, 1, numel(truth)), ...
                'latency', num2cell(double(truth) + 1));

            onsets = detectDiodeOnsets(signal, srate);
            report = diodeTriggerDelay(onsets, events, srate, struct());

            testCase.verifyEqual(report.n, numel(truth), ...
                'A trigger a sample late should still own the onset it caused.');
            testCase.verifyLessThan(report.medianMs, 0, ...
                'And the lag it reports should be the small negative one it is.');
        end

        function aTriggerWellAfterAnOnsetDoesNotOwnIt(testCase)
        %ATRIGGERWELLAFTERANONSETDOESNOTOWNIT  The tolerance is for jitter,
        %   not for pairing an onset with whatever comes next. A trigger
        %   fifty milliseconds after a screen change did not cause it.
            srate = testCase.Srate;
            [signal, truth] = testCase.withPatches(30, 20000, 100);
            events = struct('type', repmat({'s106'}, 1, numel(truth)), ...
                'latency', num2cell(double(truth) + 50));

            onsets = detectDiodeOnsets(signal, srate);
            report = diodeTriggerDelay(onsets, events, srate, struct());

            testCase.verifyEqual(report.n, 0, ...
                'A trigger 50 ms after the screen change should own nothing.');
        end

        function aRealLagStillPairsTheOldWay(testCase)
        %AREALLAGSTILLPAIRSTHEOLDWAY  The strict rule is tried first and
        %   wins wherever it applies, so a genuine display lag is unchanged
        %   by the tolerance existing.
            EEG = testCase.eegWithPatches();   % triggers 50 ms before

            out = testCase.verifyWarning(@() Photodiode(EEG, ...
                struct('Channel', 'PhotoDiode', 'Mode', 'measure')), ...
                'Alakazam:Photodiode:delay');

            testCase.verifyEqual(out.DiodeReport.medianMs, 50, 'AbsTol', 2);
        end

        function eventsModeKeepsItsReport(testCase)
        %EVENTSMODEKEEPSITSREPORT  It used to be emptied, which made the
        %   result unexaminable: asked later why a dataset has 30 diode
        %   events for 31 triggers, the node could not say, and the lags had
        %   to be reconstructed from the event table by hand.
            EEG = testCase.eegWithPatches();

            out = Photodiode(EEG, struct('Channel', 'PhotoDiode', 'Mode', 'events'));

            testCase.assertTrue(isfield(out, 'DiodeReport'));
            testCase.verifyNotEmpty(out.DiodeReport, ...
                'Events mode computes the pairing; it should keep it.');
            testCase.verifyGreaterThan(out.DiodeReport.n, 0);
            testCase.verifyNotEmpty(out.DiodeReport.pairs, ...
                'The pairs are what "which trigger lost its onset" is answered from.');
        end

        function theReportBreaksTheLagDownByTriggerType(testCase)
        %THEREPORTBREAKSTHELAGDOWNBYTRIGGERTYPE  One row per code, because
        %   they do not all measure the same thing.
            srate = testCase.Srate;
            [signal, truth] = testCase.withPatches(30, 20000, 100);

            % Alternate codes, both sent 50 ms before their patch.
            codes = repmat({'s50', 's51'}, 1, ceil(numel(truth)/2));
            events = struct('type', codes(1:numel(truth)), ...
                'latency', num2cell(double(truth) - 50));

            onsets = detectDiodeOnsets(signal, srate);
            report = diodeTriggerDelay(onsets, events, srate, struct());

            testCase.assertNumElements(report.byType, 2);
            testCase.verifyEqual(sort({report.byType.type}), {'s50', 's51'});
            testCase.verifyEqual(sum([report.byType.n]), report.n, ...
                'Every pair should be counted under exactly one type.');
            for k = 1:numel(report.byType)
                testCase.verifyEqual(report.byType(k).medianMs, 50, 'AbsTol', 3);
            end
        end

        function oneShiftIsAdvisedOnlyWhenTheTriggersAgree(testCase)
        %ONESHIFTISADVISEDONLYWHENTHETRIGGERSAGREE  The advice used to be
        %   unconditional: shift these triggers by the median. On a real
        %   recording two families of marker sat 21.5 ms and 2.0 ms from the
        %   screen change, and following that advice would have applied a
        %   twenty millisecond monitor correction to markers that never had
        %   one. Here they agree, so the single shift is still offered.
            srate = testCase.Srate;
            [signal, truth] = testCase.withPatches(30, 20000, 100);
            codes = repmat({'s50', 's51'}, 1, ceil(numel(truth)/2));
            events = struct('type', codes(1:numel(truth)), ...
                'latency', num2cell(double(truth) - 50));

            onsets = detectDiodeOnsets(signal, srate);
            report = diodeTriggerDelay(onsets, events, srate, struct());

            testCase.verifySubstring(report.summary, 'shift these triggers');
            testCase.verifyEmpty(strfind(report.summary, 'do NOT share one lag')); %#ok<STREMP>
        end

        function twoFamiliesOfTriggerAreCalledOut(testCase)
        %TWOFAMILIESOFTRIGGERARECALLEDOUT  The case that prompted this. One
        %   type sent 50 ms before its patch, another sent AT it, in the
        %   same recording. Pooling them gives a median that describes
        %   neither, and the summary has to say so rather than offer it.
            srate = testCase.Srate;
            [signal, truth] = testCase.withPatches(30, 20000, 100);

            early = true(1, numel(truth));
            early(2:2:end) = false;
            codes = cell(1, numel(truth));
            lats = zeros(1, numel(truth));
            for k = 1:numel(truth)
                if early(k)
                    codes{k} = 's50';  lats(k) = truth(k) - 50;   % a real display lag
                else
                    codes{k} = 's106'; lats(k) = truth(k);        % sent at the flip
                end
            end
            events = struct('type', codes, 'latency', num2cell(double(lats)));

            onsets = detectDiodeOnsets(signal, srate);
            report = diodeTriggerDelay(onsets, events, srate, struct());

            testCase.verifySubstring(report.summary, 'do NOT share one lag');
            testCase.verifySubstring(report.summary, 's50');
            testCase.verifySubstring(report.summary, 's106');
            testCase.verifyEmpty(strfind(report.summary, 'shift these triggers'), ...
                'It must not offer one shift for triggers that disagree.'); %#ok<STREMP>
        end

        function theSpreadWithinATypeIsReportedToo(testCase)
        %THESPREADWITHINATYPEISREPORTEDTOO  An offset can be corrected;
        %   scatter cannot. A type whose onsets disagree with each other is
        %   the row worth reading, so its IQR and range are carried.
            srate = testCase.Srate;
            [signal, truth] = testCase.withPatches(30, 20000, 100);
            events = struct('type', repmat({'s50'}, 1, numel(truth)), ...
                'latency', num2cell(double(truth) - 50));

            onsets = detectDiodeOnsets(signal, srate);
            report = diodeTriggerDelay(onsets, events, srate, struct());

            row = report.byType(1);
            for f = {'iqrMs', 'minMs', 'maxMs'}
                testCase.verifyTrue(isfield(row, f{1}));
                testCase.verifyTrue(isfinite(row.(f{1})));
            end
            testCase.verifyGreaterThanOrEqual(row.maxMs, row.minMs);
        end

        function anUnpairedOnsetGetsTheSuffixAlone(testCase)
        %ANUNPAIREDONSETGETSTHESUFFIXALONE  A screen change nobody asked
        %   for, or one whose trigger was lost. There is no name to borrow,
        %   and it should stand out in the event table rather than be
        %   dropped or given a name it has not earned.
            EEG = testCase.eegWithPatches();
            EEG.event = EEG.event(1);          % leave all but one onset unpaired

            out = Photodiode(EEG, struct('Channel', 'PhotoDiode', 'Mode', 'events'));

            testCase.verifyTrue(any(strcmp({out.event.type}, 'PD')), ...
                'An onset with no trigger before it should be added as "PD".');
            testCase.verifyTrue(any(strcmp({out.event.type}, 'S1PD')), ...
                'The one that does have a trigger should still be named after it.');
        end

        function theLabelUsesTheSamePairingAsTheReport(testCase)
        %THELABELUSESTHESAMEPAIRINGASTHEREPORT  Max lag is the analyst's to
        %   set, and it decides which onsets count as answered. If the
        %   labelling recomputed the pairing with its own defaults, the
        %   event table and the measured lag would be describing different
        %   sets of trials.
            EEG = testCase.eegWithPatches();   % triggers sit 50 ms before

            tight = Photodiode(EEG, struct('Channel', 'PhotoDiode', 'Mode', 'events', ...
                'MaxLagMs', 10));              % too tight to pair anything

            testCase.verifyFalse(any(strcmp({tight.event.type}, 'S1PD')), ...
                'A max lag that pairs nothing should leave every onset unpaired.');
            testCase.verifyTrue(any(strcmp({tight.event.type}, 'PD')));
        end

        function theChannelIsResolvedByLabel(testCase)
        %THECHANNELISRESOLVEDBYLABEL  Replay is why. The diode is
        %   conventionally the LAST channel, which is exactly the position
        %   that moves when a channel is dropped; a label survives that.
            EEG = testCase.eegWithPatches();
            shifted = EEG;
            shifted.data = EEG.data([end, 1:end-1], :);          % diode now first
            shifted.chanlocs = EEG.chanlocs([end, 1:end-1]);
            opts = struct('Channel', 'PhotoDiode', 'Mode', 'measure');

            a = testCase.verifyWarning(@() Photodiode(EEG, opts), 'Alakazam:Photodiode:delay');
            b = testCase.verifyWarning(@() Photodiode(shifted, opts), 'Alakazam:Photodiode:delay');

            testCase.verifyEqual(b.DiodeOnsets, a.DiodeOnsets, ...
                'Moving the diode channel changed the result, so it was found by index.');
        end

        function anAbsentChannelIsRefusedClearly(testCase)
            EEG = testCase.eegWithPatches();

            testCase.verifyError(@() Photodiode(EEG, ...
                struct('Channel', 'NoSuchChannel', 'Mode', 'measure')), ...
                'Alakazam:Photodiode');
        end
    end

    methods (Access = private)
        function [EEG, nTrials] = eegWithAnInterveningMarker(testCase)
        %EEGWITHANINTERVENINGMARKER  The reported situation: a stimulus
        %   trigger on every trial, a screen change 50 ms later, and on ONE
        %   trial another marker 20 ms after the trigger, in between the
        %   two.
            srate = testCase.Srate;
            nTrials = 31;
            spacing = 2000;
            lag = 50;
            n = (nTrials + 2) * spacing;

            rng(7);
            t = (0:n-1) / srate;
            diode = testCase.Baseline ...
                + testCase.Flicker * sin(2*pi*testCase.FlickerHz*t) ...
                + randn(1, n) * 90;

            types = {};
            lats = [];
            for k = 1:nTrials
                trigger = 1000 + (k - 1) * spacing;
                types{end+1} = 's106'; %#ok<AGROW>
                lats(end+1) = trigger; %#ok<AGROW>
                if k == 17
                    types{end+1} = 's52'; %#ok<AGROW>
                    lats(end+1) = trigger + 20; %#ok<AGROW>
                end
                patch = trigger + lag;
                diode(patch:patch + 99) = diode(patch:patch + 99) + 20000;
            end

            EEG = struct('srate', srate, 'pnts', n, 'nbchan', 2, ...
                'data', [randn(1, n) * 10; diode], ...
                'chanlocs', struct('labels', {'Cz', 'PhotoDiode'}), ...
                'event', struct('type', types, 'latency', num2cell(double(lats))), ...
                'DataType', 'TIMEDOMAIN');
        end

        function [signal, truth] = withRampedPatches(testCase, seconds, amp, durMs, rampMs)
        %WITHRAMPEDPATCHES  withPatches, but each patch ramps up over RAMPMS
        %   instead of stepping, which is what a panel actually does. TRUTH
        %   is where each ramp BEGINS, which is the instant being measured.
            signal = testCase.flickerOnly(seconds);
            truth = 1000 : 2000 : (numel(signal) - durMs - 10);
            ramp = linspace(0, amp, rampMs);
            for t = truth
                signal(t:t + rampMs - 1) = signal(t:t + rampMs - 1) + ramp;
                signal(t + rampMs:t + durMs - 1) = signal(t + rampMs:t + durMs - 1) + amp;
            end
        end

        function signal = flickerOnly(testCase, seconds)
        %FLICKERONLY  The real thing: mains flicker on a steady baseline,
        %   with a little drift and noise, and no patch anywhere.
            rng(42);
            n = seconds * testCase.Srate;
            t = (0:n-1) / testCase.Srate;
            signal = testCase.Baseline ...
                + testCase.Flicker * sin(2*pi*testCase.FlickerHz*t) ...
                + 120 * sin(2*pi*0.05*t) ...          % slow drift
                + randn(1, n) * 90;
        end

        function [signal, truth] = withPatches(testCase, seconds, amp, durMs)
            signal = testCase.flickerOnly(seconds);
            truth = 1000 : 2000 : (numel(signal) - durMs - 10);
            for t = truth
                signal(t:t+durMs-1) = signal(t:t+durMs-1) + amp;
            end
        end

        function EEG = eegWithPatches(testCase)
        %EEGWITHPATCHES  Two EEG channels and a diode, with a trigger 50 ms
        %   before each patch: a display lag of exactly 50 ms to recover.
            [diode, truth] = testCase.withPatches(30, 20000, 100);
            n = numel(diode);
            EEG = struct();
            EEG.srate = testCase.Srate;
            EEG.pnts = n;
            EEG.data = [randn(2, n) * 10; diode];
            EEG.nbchan = 3;
            EEG.chanlocs = struct('labels', {'Cz', 'Pz', 'PhotoDiode'});
            EEG.event = struct('type', repmat({'S1'}, 1, numel(truth)), ...
                'latency', num2cell(double(truth) - 50));
        end
    end
end
