classdef FilterTest < matlab.unittest.TestCase
%FILTERTEST  Unit tests for src/Transformations/Filter/Filter.m.
%
%   THE LEAST-VERIFIED FILE IN THIS TEST SUITE: unlike Baseline/Average/
%   ArtefactDetect/DefineBins/Fourier (pure Alakazam-authored code this
%   session read in full), Filter.m calls straight into EEGLAB's own
%   `firfilt` plugin (firwsord/windows/firws/firfilt/kaiserbeta), whose
%   source was not read here -- its exact minimal EEG-struct requirements
%   (does it need .event present even if empty? .nbchan? .trials?) are
%   inferred from general EEGLAB convention, not confirmed against its
%   actual code. If eegFixture() below is missing a field firfilt expects,
%   that will surface as a clear error on first run, not a wrong result --
%   still worth treating this file's first run as a real validation pass.
%
%   Every filter-type test measures attenuation via a direct single-
%   frequency DFT (freqAmplitude, an exact `abs(mean(sig.*exp(-2i*pi*f*t)))`
%   demodulation at one exact, known frequency) rather than expecting a
%   precise numeric output from the Kaiser FIR design -- robust to exactly
%   how firws/firwsord size the filter, since it only checks "the targeted
%   frequency dropped a lot; a frequency well clear of the transition band
%   did not", not an exact attenuation figure.
%
%   Needs EEGLAB actually initialised in this MATLAB session (eeglab() run
%   at least once, same requirement Alakazam itself has -- see
%   EEGLabEnvironment.ensureEEGLabInitialized). If EEGLAB is not on the
%   path at all, every test here is marked Incomplete (skipped), not
%   Failed -- see the assumeTrue call below.
%
%   Run with: runtests('tests/FilterTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations', 'Filter')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations')));
        end

        function ensureEeglab(testCase)
        %ENSUREEEGLAB  Skip (not fail) this whole test class if EEGLAB is
        %   not on the path/not yet initialised in this session, rather
        %   than every test failing on the first firfilt call with a
        %   confusing "undefined function" error.
            testCase.assumeTrue(~isempty(which('eeglab')), ...
                'EEGLAB not found on the MATLAB path -- skipping FilterTest.');
            if isempty(which('firfilt'))
                eeglab('nogui');
            end
            testCase.assumeFalse(isempty(which('firfilt')), ...
                'EEGLAB''s firfilt plugin is not available -- skipping FilterTest.');
        end
    end

    methods (Test)
        function highpassAttenuatesSlowDriftButKeepsMidband(testCase)
        %HIGHPASSATTENUATESSLOWDRIFTBUTKEEPSMIDBAND  A 0.5 Hz "drift" plus
        %   a 20 Hz signal, high-pass filtered at 2 Hz: the drift should
        %   be strongly attenuated, the 20 Hz content left largely intact.
            [EEG, t] = eegFixture([0.5, 20], [10, 1]);
            opts = struct('highpass', struct('enabled', true, 'freq', 2, 'db', 40), ...
                'lowpass', struct('enabled', false, 'freq', 0, 'db', 0), ...
                'notch', struct('enabled', false, 'freq', 0, 'db', 0));

            before = EEG.data;
            [result, ~] = Filter(EEG, opts);

            lowBefore = freqAmplitude(before(1, :), t, 0.5);
            lowAfter  = freqAmplitude(result.data(1, :), t, 0.5);
            midBefore = freqAmplitude(before(1, :), t, 20);
            midAfter  = freqAmplitude(result.data(1, :), t, 20);

            testCase.verifyLessThan(lowAfter, lowBefore * 0.1, ...
                'The 0.5 Hz drift should be attenuated by at least 10x by a 2 Hz high-pass.');
            testCase.verifyGreaterThan(midAfter, midBefore * 0.5, ...
                'The 20 Hz content should survive a 2 Hz high-pass largely intact.');
        end

        function lowpassAttenuatesHighFrequencyButKeepsLowband(testCase)
        %LOWPASSATTENUATESHIGHFREQUENCYBUTKEEPSLOWBAND  A 5 Hz signal plus
        %   60 Hz noise, low-pass filtered at 20 Hz.
            [EEG, t] = eegFixture([5, 60], [1, 5]);
            opts = struct('highpass', struct('enabled', false, 'freq', 0, 'db', 0), ...
                'lowpass', struct('enabled', true, 'freq', 20, 'db', 40), ...
                'notch', struct('enabled', false, 'freq', 0, 'db', 0));

            before = EEG.data;
            [result, ~] = Filter(EEG, opts);

            highBefore = freqAmplitude(before(1, :), t, 60);
            highAfter  = freqAmplitude(result.data(1, :), t, 60);
            lowBefore  = freqAmplitude(before(1, :), t, 5);
            lowAfter   = freqAmplitude(result.data(1, :), t, 5);

            testCase.verifyLessThan(highAfter, highBefore * 0.1, ...
                '60 Hz content should be strongly attenuated by a 20 Hz low-pass.');
            testCase.verifyGreaterThan(lowAfter, lowBefore * 0.5, ...
                '5 Hz content should survive a 20 Hz low-pass largely intact.');
        end

        function notchAttenuatesJustTheTargetedFrequency(testCase)
        %NOTCHATTENUATESJUSTTHETARGETEDFREQUENCY  A 50 Hz "line noise"
        %   component plus a 20 Hz signal, notched at 50 Hz: 50 Hz should
        %   drop sharply, 20 Hz (well clear of the notch) should survive.
            [EEG, t] = eegFixture([20, 50], [1, 5]);
            opts = struct('highpass', struct('enabled', false, 'freq', 0, 'db', 0), ...
                'lowpass', struct('enabled', false, 'freq', 0, 'db', 0), ...
                'notch', struct('enabled', true, 'freq', 50, 'db', 40));

            before = EEG.data;
            [result, ~] = Filter(EEG, opts);

            notchBefore = freqAmplitude(before(1, :), t, 50);
            notchAfter  = freqAmplitude(result.data(1, :), t, 50);
            keepBefore  = freqAmplitude(before(1, :), t, 20);
            keepAfter   = freqAmplitude(result.data(1, :), t, 20);

            testCase.verifyLessThan(notchAfter, notchBefore * 0.1, ...
                '50 Hz content should be strongly attenuated by a 50 Hz notch.');
            testCase.verifyGreaterThan(keepAfter, keepBefore * 0.5, ...
                '20 Hz content should survive a 50 Hz notch largely intact.');
        end

        function perChannelModeOnlyTouchesTheNamedChannel(testCase)
        %PERCHANNELMODEONLYTOUCHESTHENAMEDCHANNEL  With options.perChannel
        %   true, a row naming only channel "Ch1" (a nonzero hpFreq) should
        %   leave channel "Ch2" byte-identical (applyPerChannel never
        %   calls applyFir for a row/filter combination whose frequency is
        %   0 or that is not present in the row list at all).
            [EEG, ~] = eegFixture([0.5, 0.5], [10, 10]); % same signal shape on both channels
            opts = struct('perChannel', true, 'perChannelRows', struct( ...
                'label', 'Ch1', 'hpFreq', 2, 'hpDb', 40, ...
                'lpFreq', 0, 'lpDb', 0, 'notchFreq', 0, 'notchDb', 0));

            before = EEG.data;
            [result, ~] = Filter(EEG, opts);

            testCase.verifyNotEqual(result.data(1, :), before(1, :), ...
                'Channel 1 (named in perChannelRows) should have been filtered.');
            testCase.verifyEqual(result.data(2, :), before(2, :), ...
                'Channel 2 (not named in perChannelRows) should be untouched.');
        end

        function perFilterEnabledFlagsActIndependently(testCase)
        %PERFILTERENABLEDFLAGSACTINDEPENDENTLY  Each filter has its own
        %   tickbox (hpEnabled/lpEnabled/notchEnabled) -- disabling one must
        %   not disable the others on the same channel. Ch1's high-pass is
        %   ticked (should run) while its notch is unticked despite a real
        %   notchFreq/notchDb (should not run).
            [EEG, t] = eegFixture([0.5, 50], [10, 5]);
            opts = struct('perChannel', true, 'perChannelRows', struct( ...
                'label', 'Ch1', ...
                'hpEnabled', true, 'hpFreq', 2, 'hpDb', 40, ...
                'lpEnabled', true, 'lpFreq', 0, 'lpDb', 0, ...
                'notchEnabled', false, 'notchFreq', 50, 'notchDb', 40));

            before = EEG.data;
            [result, ~] = Filter(EEG, opts);

            lowBefore   = freqAmplitude(before(1, :), t, 0.5);
            lowAfter    = freqAmplitude(result.data(1, :), t, 0.5);
            notchBefore = freqAmplitude(before(1, :), t, 50);
            notchAfter  = freqAmplitude(result.data(1, :), t, 50);

            testCase.verifyLessThan(lowAfter, lowBefore * 0.1, ...
                'High-pass (enabled) should have attenuated the 0.5 Hz drift.');
            % Loosely, not bit-exactly: the enabled high-pass still runs
            % over the whole signal (its own passband ripple is not
            % perfectly flat at 50 Hz), so "the notch did not run" is
            % "50 Hz mostly survived", the same largely-intact standard
            % this file's other tests use for a frequency well clear of a
            % filter's own transition band -- not exact equality.
            testCase.verifyGreaterThan(notchAfter, notchBefore * 0.9, ...
                'Notch (disabled, despite a real notchFreq/notchDb) must not have run.');
        end

        function aChannelWithAllThreeFiltersDisabledIsLeftUntouched(testCase)
        %ACHANNELWITHALLTHREEFILTERSDISABLEDISLEFTUNTOUCHED
        %   hpEnabled/lpEnabled/notchEnabled all false must leave the
        %   channel bit-identical, even though it still carries real
        %   frequency/dB numbers for all three -- the direct "this channel
        %   does not need filtering" case, not achieved by zeroing every
        %   frequency by hand.
            [EEG, ~] = eegFixture([0.5, 0.5], [10, 10]); % same signal shape on both channels
            opts = struct('perChannel', true, 'perChannelRows', [ ...
                struct('label', 'Ch1', ...
                    'hpEnabled', true, 'hpFreq', 2, 'hpDb', 40, ...
                    'lpEnabled', true, 'lpFreq', 0, 'lpDb', 0, ...
                    'notchEnabled', true, 'notchFreq', 0, 'notchDb', 0), ...
                struct('label', 'Ch2', ...
                    'hpEnabled', false, 'hpFreq', 2, 'hpDb', 40, ...
                    'lpEnabled', false, 'lpFreq', 40, 'lpDb', 40, ...
                    'notchEnabled', false, 'notchFreq', 50, 'notchDb', 40)]);

            before = EEG.data;
            [result, ~] = Filter(EEG, opts);

            testCase.verifyNotEqual(result.data(1, :), before(1, :), ...
                'Channel 1 (high-pass enabled) should have been filtered.');
            testCase.verifyEqual(result.data(2, :), before(2, :), ...
                'Channel 2 (all three filters disabled) must be bit-identical to the input.');
        end

        function aRowWithNoEnabledFieldDefaultsToFiltered(testCase)
        %AROWWITHNOENABLEDFIELDDEFAULTSTOFILTERED  Backward compatibility: a
        %   perChannelRows entry saved before these tickboxes existed has no
        %   .hpEnabled/.lpEnabled/.notchEnabled field at all, and must still
        %   filter normally (default true), not be silently skipped.
            [EEG, ~] = eegFixture([0.5, 20], [10, 1]);
            opts = struct('perChannel', true, 'perChannelRows', struct( ...
                'label', 'Ch1', 'hpFreq', 2, 'hpDb', 40, ...
                'lpFreq', 0, 'lpDb', 0, 'notchFreq', 0, 'notchDb', 0));

            before = EEG.data;
            [result, ~] = Filter(EEG, opts);

            testCase.verifyNotEqual(result.data(1, :), before(1, :), ...
                'A row with no .enabled field should default to filtered.');
        end

        function filtersEveryBinOfAnAveragedDataset(testCase)
        %FILTERSEVERYBINOFANAVERAGEDDATASET  An averaged dataset (Average or
        %   GrandAverage) holds one waveform per bin in the third dimension
        %   of .data while still reporting trials == 1. Every bin must be
        %   filtered, not just the first: firfilt on its own reads such a
        %   dataset as continuous and filters bin 1 only, which is the bug
        %   this covers. Each bin starts as the same waveform, so after
        %   filtering each must be attenuated, and all must still match.
            nbin = 3;
            [EEG, t] = averagedFixture([0.5, 20], [10, 1], nbin);
            opts = struct('highpass', struct('enabled', true, 'freq', 2, 'db', 40), ...
                'lowpass', struct('enabled', false, 'freq', 0, 'db', 0), ...
                'notch', struct('enabled', false, 'freq', 0, 'db', 0));

            before = EEG.data;
            [result, ~] = Filter(EEG, opts);

            testCase.verifySize(result.data, size(before), ...
                'Filtering must not change the shape of an averaged dataset.');

            for k = 1:nbin
                lowBefore = freqAmplitude(before(1, :, k), t, 0.5);
                lowAfter  = freqAmplitude(result.data(1, :, k), t, 0.5);
                testCase.verifyLessThan(lowAfter, lowBefore * 0.1, sprintf( ...
                    'Bin %d: the 0.5 Hz drift should be attenuated by the 2 Hz high-pass.', k));
            end

            for k = 2:nbin
                testCase.verifyEqual(result.data(:, :, k), result.data(:, :, 1), ...
                    'AbsTol', 1e-9, sprintf( ...
                    'Bin %d held the same waveform as bin 1, so it should filter identically.', k));
            end
        end

        function rejectsOutOfRangeFrequency(testCase)
        %REJECTSOUTOFRANGEFREQUENCY  A cutoff at or above Nyquist cannot
        %   be designed and should throw a friendly, identifiable error.
            [EEG, ~] = eegFixture(10, 1);
            opts = struct('highpass', struct('enabled', true, 'freq', EEG.srate / 2, 'db', 40), ...
                'lowpass', struct('enabled', false, 'freq', 0, 'db', 0), ...
                'notch', struct('enabled', false, 'freq', 0, 'db', 0));
            testCase.verifyError(@() Filter(EEG, opts), 'Alakazam:Filter');
        end

        function rejectsMissingSampleRate(testCase)
            EEG = struct('data', zeros(1, 100)); % no .srate at all
            opts = struct('highpass', struct('enabled', true, 'freq', 2, 'db', 40), ...
                'lowpass', struct('enabled', false, 'freq', 0, 'db', 0), ...
                'notch', struct('enabled', false, 'freq', 0, 'db', 0));
            testCase.verifyError(@() Filter(EEG, opts), 'Alakazam:Filter');
        end

        % ---- the impulse response the dialog plots ------------------------
        function theImpulseResponseIsWhatFilterDoesToAnImpulse(testCase)
        %THEIMPULSERESPONSEISWHATFILTERDOESTOANIMPULSE  The dialog plots
        %   filterImpulseResponse; this pins that plot to the step itself.
        %   Filtering a single impulse with all three filters must give
        %   exactly that response, centred on the impulse.
            srate = 250;
            n = 3001;
            centre = 1501;
            EEG = struct('data', zeros(1, n), 'srate', srate, 'nbchan', 1, 'trials', 1, ...
                'pnts', n, 'event', struct('type', {}, 'latency', {}), ...
                'chanlocs', struct('labels', {'Ch1'}));
            EEG.data(centre) = 1;
            opts = filterOptions([1 40], [30 40], [50 40]);

            [t, h] = filterImpulseResponse(opts, srate);
            half = (numel(h) - 1) / 2;
            testCase.assertLessThan(numel(h), n, 'The fixture must be longer than the response.');
            result = Filter(EEG, opts);

            testCase.verifyEqual(result.data(centre - half:centre + half), h, 'AbsTol', 1e-9, ...
                'The plotted response must be what Filter does to an impulse.');
            testCase.verifyEqual(t(half + 1), 0, 'AbsTol', 1e-12, 'The response is centred on the impulse.');
            testCase.verifyEqual(h, fliplr(h), 'AbsTol', 1e-12, 'Zero-phase: the response is symmetric.');
        end

        function aLowPassPassesDCAndAHighPassBlocksIt(testCase)
        %ALOWPASSPASSESDCANDAHIGHPASSBLOCKSIT  The sum of an impulse response
        %   is its gain at 0 Hz: about 1 for a low-pass, about 0 for a
        %   high-pass, within the stopband deviation of 40 dB (0.01).
            [~, low] = filterImpulseResponse(filterOptions([], [30 40], []), 250);
            [~, high] = filterImpulseResponse(filterOptions([1 40], [], []), 250);
            testCase.verifyEqual(sum(low), 1, 'AbsTol', 0.02);
            testCase.verifyEqual(sum(high), 0, 'AbsTol', 0.02);
        end

        function withNoFilterTheResponseIsTheImpulse(testCase)
            [t, h] = filterImpulseResponse(filterOptions([], [], []), 250);
            testCase.verifyEqual(h, 1);
            testCase.verifyEqual(t, 0);
        end

        function aSettingFilterRefusesIsRefusedHereToo(testCase)
            testCase.verifyError(@() filterImpulseResponse(filterOptions([125 40], [], []), 250), ...
                'Alakazam:Filter');
        end
    end

    methods (Test, TestTags = {'Slow'})
        function theDialogPlotsTheResponseAndFollowsTheSettings(testCase)
        %THEDIALOGPLOTSTHERESPONSEANDFOLLOWSTHESETTINGS  The dialog is modal,
        %   so a timer finds it, reads the plot, unticks the high-pass, reads
        %   it again, and presses Cancel. The timer repeats until the dialog
        %   is up, so the test does not depend on how long that takes.
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'src')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'src', 'Support')));
            try
                probe = uifigure('Visible', 'off');
                delete(probe);
            catch ME
                testCase.assumeFail(['A uifigure could not be created here: ' ME.message]);
            end
            srate = 250;
            stored = filterOptions([1 40], [30 40], []);
            [~, both] = filterImpulseResponse(stored, srate);
            [~, lowOnly] = filterImpulseResponse(filterOptions([], [30 40], []), srate);

            seen = struct('both', [], 'lowOnly', [], 'caption', '');
            timerObj = timer('ExecutionMode', 'fixedSpacing', 'Period', 1, ...
                'TasksToExecute', 60, 'TimerFcn', @(src, ~) drive(src));
            cleanup = onCleanup(@() cleanupTimer(timerObj));
            start(timerObj);
            FilterDialog(srate, {'Ch1', 'Ch2'}, stored);
            clear cleanup;

            testCase.verifyEqual(seen.both, numel(both), 'The plot shows both filters together.');
            testCase.verifySubstring(seen.caption, sprintf('%d samples', numel(both)));
            testCase.verifyEqual(seen.lowOnly, numel(lowOnly), 'Unticking the high-pass redraws it.');

            function drive(src)
                f = findall(groot, 'Type', 'figure', 'Name', 'Filter');
                if isempty(f)
                    return;   % not up yet: the timer comes back
                end
                stop(src);
                axesOf = findall(f(1), 'Tag', 'ResponseAxes');
                seen.both = numel(findobj(axesOf, 'Type', 'line').XData);
                seen.caption = findall(f(1), 'Tag', 'ResponseCaption').Text;
                highPass = findall(f(1), 'Type', 'uicheckbox', 'Text', 'High-pass');
                highPass.Value = false;
                highPass.ValueChangedFcn(highPass, []);
                seen.lowOnly = numel(findobj(axesOf, 'Type', 'line').XData);
                cancel = findall(f(1), 'Type', 'uibutton', 'Text', 'Cancel');
                cancel(1).ButtonPushedFcn(cancel(1), []);
            end
        end
    end
end

function opts = filterOptions(highpass, lowpass, notch)
%FILTEROPTIONS  Filter's global options: each argument [freq db] enables that
%   filter, [] leaves it off.
    opts = struct();
    names = {'highpass', 'lowpass', 'notch'};
    given = {highpass, lowpass, notch};
    for k = 1:3
        if isempty(given{k})
            opts.(names{k}) = struct('enabled', false, 'freq', 0, 'db', 0);
        else
            opts.(names{k}) = struct('enabled', true, 'freq', given{k}(1), 'db', given{k}(2));
        end
    end
end

function cleanupTimer(t)
    try
        stop(t);
        delete(t);
    catch
        % Already gone.
    end
end

function [EEG, t] = eegFixture(freqs, amps)
%EEGFIXTURE  A minimal, continuous (2-channel) EEGLAB-shaped struct: both
%   channels carry the SAME sum-of-sinusoids signal (sum of FREQS at AMPS),
%   long enough (4 s at 250 Hz = 1000 samples) for the filter orders used
%   in this file's tests. .event is an empty but properly-fielded struct
%   array (firfilt is boundary-aware; an absent .event field is a bigger
%   risk than an empty-but-present one -- see this file's own header
%   comment on what is/isn't confirmed about firfilt's requirements).
    srate = 250;
    t = (0:999) / srate;
    sig = zeros(size(t));
    for i = 1:numel(freqs)
        sig = sig + amps(i) * sin(2 * pi * freqs(i) * t);
    end
    EEG = struct();
    EEG.data   = [sig; sig];
    EEG.srate  = srate;
    EEG.nbchan = 2;
    EEG.trials = 1;
    EEG.pnts   = numel(t);
    EEG.event  = struct('type', {}, 'latency', {});
    EEG.chanlocs = struct('labels', {'Ch1', 'Ch2'});
end

function [EEG, t] = averagedFixture(freqs, amps, nbin)
%AVERAGEDFIXTURE  A minimal Averaged dataset: the same sum-of-sinusoids
%   waveform in each of NBIN bins, held as nchan x npnts x nbin with
%   trials == 1 -- the shape Average.m and GrandAverage.m both produce. Its
%   .event deliberately carries a boundary event at a latency past the end
%   of any single bin, as an averaged dataset inheriting the events of the
%   epoched dataset it came from really does; a bin-aware filter must not
%   let that stale latency split a bin.
    [EEG, t] = eegFixture(freqs, amps);
    EEG.data       = repmat(EEG.data, [1, 1, nbin]);
    EEG.DataFormat = 'Averaged';
    EEG.trials     = 1;
    EEG.ntrials    = 40;
    EEG.event      = struct('type', {'boundary'}, 'latency', {numel(t) * nbin - 10});
    EEG.bindesc    = repmat( ...
        struct('index', 0, 'label', '', 'n', 0, 'combo', [], 'trials', []), 1, nbin);
    for k = 1:nbin
        EEG.bindesc(k).index = k;
        EEG.bindesc(k).label = sprintf('bin %d', k);
        EEG.bindesc(k).n     = 20;
    end
end

function a = freqAmplitude(sig, t, freq)
%FREQAMPLITUDE  The amplitude of SIG's component at exactly FREQ Hz, via a
%   direct single-frequency DFT (Goertzel-style demodulation) -- exact for
%   any FREQ, independent of any FFT bin-alignment/windowing concerns,
%   used here purely to compare a signal's own content before vs. after
%   filtering at a handful of known frequencies.
    a = 2 * abs(mean(sig .* exp(-2i * pi * freq * t)));
end
