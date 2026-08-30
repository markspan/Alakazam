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
            opts = struct('Channel', 'PhotoDiode', 'Mode', 'events', 'EventType', 'diode');

            out = Photodiode(EEG, opts);

            testCase.verifyGreaterThan(numel(out.event), numel(EEG.event));
            testCase.verifyEqual([out.event.latency], sort([out.event.latency]));
            testCase.verifyTrue(any(strcmp({out.event.type}, 'diode')));
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
