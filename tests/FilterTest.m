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

        % ---- the response the dialog's frequency plot is computed from ----
        function theImpulseResponseIsWhatFilterDoesToAnImpulse(testCase)
        %THEIMPULSERESPONSEISWHATFILTERDOESTOANIMPULSE  The dialog plots the
        %   Fourier transform of filterImpulseResponse; this pins that
        %   response to the step itself.
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
            testCase.verifyError(@() filterFrequencyResponse(filterOptions([125 40], [], []), 250), ...
                'Alakazam:Filter');
        end

        % ---- the frequency response the dialog plots ----------------------
        function theFrequencyResponseIsWhatFilterDoesToASinusoid(testCase)
        %THEFREQUENCYRESPONSEISWHATFILTERDOESTOASINUSOID  The dialog plots
        %   filterFrequencyResponse; this pins that plot to the step itself.
        %   A sum of unit sinusoids is filtered with all three filters, and
        %   the amplitude each keeps must be the plotted gain at its
        %   frequency: in the passband, at each cutoff and in each stopband.
        %   At 256 Hz every probe frequency lies exactly on the response's
        %   grid, and each makes a whole number of cycles in the stretch
        %   measured, which is clear of the filter's reach from either edge,
        %   so the comparison is exact rather than approximate.
            srate = 256;
            opts = filterOptions([1 40], [30 40], [50 40]);
            [f, gain] = filterFrequencyResponse(opts, srate);
            [~, h] = filterImpulseResponse(opts, srate);
            edge = (numel(h) - 1) / 2 + srate;
            window = 10 * srate;
            n = window + 2 * edge;
            t = (0:n - 1) / srate;
            probes = [0.5 1 10 30 50 60 100];
            EEG = struct('data', sum(sin(2 * pi * probes' * t), 1), 'srate', srate, ...
                'nbchan', 1, 'trials', 1, 'pnts', n, ...
                'event', struct('type', {}, 'latency', {}), ...
                'chanlocs', struct('labels', {'Ch1'}));

            result = Filter(EEG, opts);

            measured = edge + (1:window);
            for p = probes
                plotted = gain(abs(f - p) < 1e-9);
                testCase.assertNumElements(plotted, 1, sprintf( ...
                    '%g Hz must lie on the response''s frequency grid.', p));
                kept = freqAmplitude(result.data(measured), t(measured), p);
                testCase.verifyEqual(kept, plotted, 'AbsTol', 1e-9, sprintf( ...
                    'At %g Hz the plotted gain must be what Filter does to a sinusoid.', p));
            end
        end

        function theGainIsOneHalfAtEachCutoff(testCase)
        %THEGAINISONEHALFATEACHCUTOFF  A windowed-sinc filter's cutoff is its
        %   -6 dB point, where the dialog draws its dotted line: a gain of one
        %   half, within the stopband deviation of 40 dB (0.01). A notch has
        %   two cutoffs, the edges of its stop band.
            srate = 256;
            cases = {filterOptions([1 40], [], []), 1; ...
                     filterOptions([], [30 40], []), 30; ...
                     filterOptions([], [], [50 40]), [49 51]};
            for k = 1:size(cases, 1)
                [f, gain] = filterFrequencyResponse(cases{k, 1}, srate);
                for cutoff = cases{k, 2}
                    testCase.verifyEqual(gain(abs(f - cutoff) < 1e-9), 0.5, 'AbsTol', 0.01, ...
                        sprintf('The gain at the %g Hz cutoff should be one half.', cutoff));
                end
            end
        end

        function theFrequencyResponseRunsFromZeroToNyquist(testCase)
            [f, gain] = filterFrequencyResponse(filterOptions([], [30 40], []), 250);
            testCase.verifyEqual(f(1), 0);
            testCase.verifyEqual(f(end), 125, 'AbsTol', 1e-12);
            testCase.verifyTrue(all(diff(f) > 0), 'The frequencies rise.');
            testCase.verifySize(gain, size(f));
        end

        function withNoFilterTheGainIsOneEverywhere(testCase)
            [f, gain] = filterFrequencyResponse(filterOptions([], [], []), 250);
            testCase.verifyEqual(gain, ones(size(f)), 'AbsTol', 1e-12);
        end

        % ---- the design's parameters (filterDesign) ------------------------
        function anAutomaticDesignIsWhatItAlwaysWas(testCase)
        %ANAUTOMATICDESIGNISWHATITALWAYSWAS  Stored settings carry only a
        %   frequency and a dB rating, and must replay exactly as before the
        %   rest of the design could be set: each kernel is compared, to the
        %   last bit, with the former design, copied below.
            % Each bound of the automatic transition band decides one case:
            % a high-pass's 0.9 FREQ cap (0.1 Hz) and 1 Hz floor (2 Hz), a
            % low-pass's FREQ/4 (30 Hz), 2 Hz floor (5 Hz) and Nyquist cap
            % (120 Hz at 250 Hz), and the notch's fixed band.
            cases = {'high', 0.1, 40, 250; 'high', 2, 60, 500; 'high', 1, 60, 500; ...
                'low', 30, 40, 250; 'low', 5, 40, 250; 'low', 120, 40, 250; ...
                'low', 100, 80, 1000; 'notch', 50, 40, 250; 'notch', 60, 30, 512};
            for k = 1:size(cases, 1)
                [type, freq, db, srate] = cases{k, :};
                testCase.verifyEqual(designFilterKernel(type, freq, db, srate), ...
                    formerKernel(type, freq, db, srate), sprintf('%s %g Hz', type, freq));
            end
        end

        function anEditedTransitionBandGivesTheOrderFirfiltComputes(testCase)
            dev = 10 ^ (-60 / 20);
            d = filterDesign('low', struct('freq', 30, 'db', 60, 'auto', false, 'transition', 5), 250);
            testCase.verifyEqual(d.order, firwsord('kaiser', 250, 5, dev));
            testCase.verifyEqual(d.transition, 5);
            testCase.verifyEqual(numel(designFilterKernel('low', 30, 60, 250, d)), d.order + 1);
        end

        function anEditedOrderGivesTheTransitionBandItImplies(testCase)
        %ANEDITEDORDERGIVESTHETRANSITIONBANDITIMPLIES  invfirwsord's
        %   transition band, the attenuation kept; and that transition band,
        %   entered in its turn, gives the same order back.
            dev = 10 ^ (-50 / 20);
            d = filterDesign('low', struct('freq', 30, 'db', 50, 'auto', false, 'order', 100), 250);
            testCase.verifyEqual(d.order, 100);
            testCase.verifyEqual(d.transition, invfirwsord('kaiser', 250, 100, dev), 'RelTol', 1e-12);
            back = filterDesign('low', struct('freq', 30, 'db', 50, 'auto', false, 'transition', d.transition), 250);
            testCase.verifyEqual(back.order, 100);
            odd = filterDesign('low', struct('freq', 30, 'db', 50, 'auto', false, 'order', 101), 250);
            testCase.verifyEqual(odd.order, 102, 'An odd order is rounded up to the even one firws needs.');
        end

        function theRippleIsTheAttenuationInOtherUnits(testCase)
            d = filterDesign('high', struct('freq', 1, 'db', 40), 250);
            testCase.verifyEqual(d.dev, 0.01, 'RelTol', 1e-12);
            testCase.verifyEqual(d.ripple, 20 * log10(1.01), 'RelTol', 1e-12);
            testCase.verifyEqual(d.beta, kaiserbeta(0.01));
        end

        function aManualDesignStillMeetsItsAttenuation(testCase)
        %AMANUALDESIGNSTILLMEETSITSATTENUATION  A low-pass at 30 Hz, 60 dB, a
        %   4 Hz transition band: past the band's far edge the gain stays 60
        %   dB down (to within a dB, the Kaiser formula being an estimate).
            spec = struct('enabled', true, 'freq', 30, 'db', 60, 'auto', false, 'transition', 4, 'order', []);
            opts = filterOptions([], [], []);
            opts.lowpass = spec;
            [f, gain] = filterFrequencyResponse(opts, 250);
            stop = f >= 30 + 2;
            testCase.verifyLessThan(max(20 * log10(gain(stop))), -59);
            testCase.verifyEqual(interp1(f, gain, 30), 0.5, 'AbsTol', 0.01, 'The cutoff stays at -6 dB.');
        end

        function aManualDesignIsWhatFilterApplies(testCase)
            [EEG, ~] = eegFixture([5 40], [1 1]);
            opts = filterOptions([], [], []);
            opts.lowpass = struct('enabled', true, 'freq', 20, 'db', 50, 'auto', false, 'transition', [], 'order', 120);
            out = Filter(EEG, opts);
            testCase.verifyEqual(out.etc.alz.filter.applied{1}.order, 120);
            want = firfilt(EEG, designFilterKernel('low', 20, 50, 250, opts.lowpass));
            testCase.verifyEqual(out.data, want.data, 'AbsTol', 1e-12);
        end

        % ---- a filter from the Filter Designer -----------------------------
        function aDesignedIirIsAppliedForwardAndBackward(testCase)
            [EEG, ~] = eegFixture([5 40], [1 1]);
            d = designfilt('lowpassiir', 'FilterOrder', 6, 'HalfPowerFrequency', 20, 'SampleRate', 250);
            opts = filterOptions([], [], []);
            opts.designed = designedFilterFromObject(d, 'lp');
            out = Filter(EEG, opts);
            testCase.verifyEqual(out.data, filtfilt(d.Coefficients, 1, EEG.data.').', 'AbsTol', 1e-10);
            testCase.verifyEqual(out.etc.alz.filter.applied{end}.passes, 2);
        end

        function aLinearPhaseFirIsAppliedOnceAsTheOthersAre(testCase)
            [EEG, ~] = eegFixture([5 40], [1 1]);
            e = designfilt('lowpassfir', 'FilterOrder', 60, 'CutoffFrequency', 30, 'SampleRate', 250);
            opts = filterOptions([], [], []);
            opts.designed = designedFilterFromObject(e, 'fir');
            out = Filter(EEG, opts);
            want = firfilt(EEG, e.Coefficients);
            testCase.verifyEqual(out.data, want.data, 'AbsTol', 1e-12);
            testCase.verifyEqual(out.etc.alz.filter.applied{end}.passes, 1);
        end

        function aRejectedStretchStaysRejectedAndSplitsTheRest(testCase)
        %AREJECTEDSTRETCHSTAYSREJECTEDANDSPLITSTHEREST  An IIR filter's
        %   response never ends, so a NaN stretch filtered over would take the
        %   rest of the recording with it. It stays NaN, and each side is
        %   filtered on its own.
            [EEG, ~] = eegFixture([5 40], [1 1]);
            EEG.data(1, 400:450) = NaN;
            d = designfilt('lowpassiir', 'FilterOrder', 4, 'HalfPowerFrequency', 20, 'SampleRate', 250);
            opts = filterOptions([], [], []);
            opts.designed = designedFilterFromObject(d, 'lp');
            out = Filter(EEG, opts);
            sos = d.Coefficients;
            testCase.verifyTrue(all(isnan(out.data(1, 400:450))));
            testCase.verifyEqual(out.data(1, 1:399), filtfilt(sos, 1, EEG.data(1, 1:399).').', 'AbsTol', 1e-10);
            testCase.verifyEqual(out.data(1, 451:end), filtfilt(sos, 1, EEG.data(1, 451:end).').', 'AbsTol', 1e-10);
            testCase.verifyEqual(out.data(2, :), filtfilt(sos, 1, EEG.data(2, :).').', 'AbsTol', 1e-10);
        end

        function eachEpochIsFilteredOnItsOwn(testCase)
            [EEG, ~] = eegFixture([5 40], [1 1]);
            EEG.data = reshape(EEG.data, 2, 250, 4);
            EEG.pnts = 250;
            EEG.trials = 4;
            d = designfilt('highpassiir', 'FilterOrder', 4, 'HalfPowerFrequency', 2, 'SampleRate', 250);
            opts = filterOptions([], [], []);
            opts.designed = designedFilterFromObject(d, 'hp');
            out = Filter(EEG, opts);
            for tr = 1:4
                testCase.verifyEqual(out.data(:, :, tr), filtfilt(d.Coefficients, 1, EEG.data(:, :, tr).').', ...
                    'AbsTol', 1e-10, sprintf('Epoch %d.', tr));
            end
        end

        function aFilterForAnotherSampleRateIsRefused(testCase)
            [EEG, ~] = eegFixture(5, 1);
            d = designfilt('lowpassiir', 'FilterOrder', 4, 'HalfPowerFrequency', 20, 'SampleRate', 500);
            opts = filterOptions([], [], []);
            opts.designed = designedFilterFromObject(d, 'lp500');
            testCase.verifyError(@() Filter(EEG, opts), 'Alakazam:Filter');
            normalised = designfilt('lowpassiir', 'FilterOrder', 4, 'HalfPowerFrequency', 0.2);
            testCase.verifyError(@() designedFilterFromObject(normalised, 'n'), 'Alakazam:Filter', ...
                'Without the data''s rate there is nothing to read it at.');
        end

        function aNormalisedDesignIsReadAtTheDataRate(testCase)
        %ANORMALISEDDESIGNISREADATTHEDATARATE  A filter designed in normalised
        %   frequency has the same coefficients at any rate; read at the
        %   data's 250 Hz, a half-power point at 0.16 lies at 20 Hz, and the
        %   filter applied is the one designed in Hz for 20 Hz at 250 Hz.
            [EEG, ~] = eegFixture([5 40], [1 1]);
            normalised = designfilt('lowpassiir', 'FilterOrder', 6, 'HalfPowerFrequency', 20 / 125);
            inHz = designfilt('lowpassiir', 'FilterOrder', 6, 'HalfPowerFrequency', 20, 'SampleRate', 250);
            opts = filterOptions([], [], []);

            opts.designed = designedFilterFromObject(normalised, 'n', 250);

            testCase.verifyTrue(opts.designed.normalised);
            testCase.verifyEqual(opts.designed.srate, 250);
            testCase.verifySubstring(opts.designed.source, 'read at 250 Hz');
            expected = opts;
            expected.designed = designedFilterFromObject(inHz, 'hz');
            testCase.verifyEqual(Filter(EEG, opts).data, Filter(EEG, expected).data, 'AbsTol', 1e-10);
        end

        function aNormalisedDesignKeepsTheRateItWasReadAt(testCase)
        %ANORMALISEDDESIGNKEEPSTHERATEITWASREADAT  Read at 500 Hz, its band
        %   edges are fixed in Hz; replayed onto data at 250 Hz they would
        %   halve, so the replay is refused as for a filter designed in Hz.
            [EEG, ~] = eegFixture(5, 1);
            opts = filterOptions([], [], []);
            opts.designed = designedFilterFromObject( ...
                designfilt('lowpassiir', 'FilterOrder', 4, 'HalfPowerFrequency', 0.2), 'n', 500);

            testCase.verifyError(@() Filter(EEG, opts), 'Alakazam:Filter');
        end

        function theResponseIncludesTheDesignedFilterSquared(testCase)
            d = designfilt('lowpassiir', 'FilterOrder', 6, 'HalfPowerFrequency', 20, 'SampleRate', 250);
            opts = filterOptions([], [], []);
            opts.designed = designedFilterFromObject(d, 'lp');
            [f, gain] = filterFrequencyResponse(opts, 250);
            testCase.verifyEqual(gain, abs(reshape(freqz(d.Coefficients, f, 250), 1, [])) .^ 2, 'AbsTol', 1e-12);
            atCutoff = abs(freqz(d.Coefficients, [20 21], 250)) .^ 2;
            testCase.verifyEqual(atCutoff(1), 0.5, 'AbsTol', 1e-9, ...
                'Applied twice, the half-power point is the -6 dB point.');
        end

        function aDesignedFilterReplaysFromATemplate(testCase)
        %ADESIGNEDFILTERREPLAYSFROMATEMPLATE  A template stores options as
        %   JSON, which brings the coefficients back in other shapes; the
        %   filter applied is the same.
            [EEG, ~] = eegFixture([5 40], [1 1]);
            opts = filterOptions([1 40], [], []);
            opts.designed = designedFilterFromObject(designfilt('lowpassiir', 'FilterOrder', 6, ...
                'HalfPowerFrequency', 20, 'SampleRate', 250), 'lp');
            replayed = jsondecode(jsonencode(opts));
            testCase.verifyEqual(Filter(EEG, replayed).data, Filter(EEG, opts).data, 'AbsTol', 1e-12);
            fir = filterOptions([], [], []);
            fir.designed = designedFilterFromObject(designfilt('lowpassfir', 'FilterOrder', 60, ...
                'CutoffFrequency', 30, 'SampleRate', 250), 'fir');
            testCase.verifyEqual(Filter(EEG, jsondecode(jsonencode(fir))).data, Filter(EEG, fir).data, 'AbsTol', 1e-12);
        end
    end

    methods (Test, TestTags = {'Slow'})
        function theDialogPlotsTheResponseAndFollowsTheSettings(testCase)
        %THEDIALOGPLOTSTHERESPONSEANDFOLLOWSTHESETTINGS  The dialog is modal,
        %   so a timer finds it, reads its one plot (the frequency response
        %   from 0 Hz to Nyquist), unticks the high-pass, reads it again,
        %   unticks the low-pass too, and presses Cancel. The timer repeats
        %   until the dialog is up, so the test does not depend on how long
        %   that takes.
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
            bothFrequencies = filterFrequencyResponse(stored, srate);
            lowOnlyFrequencies = filterFrequencyResponse(filterOptions([], [30 40], []), srate);

            seen = struct('impulseAxes', [], 'span', [], 'bothFrequencies', [], ...
                'lowOnlyFrequencies', [], 'frequencyCaption', '', 'noneCaption', '', 'noneCurves', []);
            timerObj = timer('ExecutionMode', 'fixedSpacing', 'Period', 1, ...
                'TasksToExecute', 60, 'TimerFcn', @(src, ~) drive(src));
            cleanup = onCleanup(@() cleanupTimer(timerObj));
            start(timerObj);
            FilterDialog(srate, {'Ch1', 'Ch2'}, stored);
            clear cleanup;

            testCase.verifyEmpty(seen.impulseAxes, 'Only the frequency response is plotted.');
            testCase.verifyEqual(seen.span, [0, srate / 2], 'AbsTol', 1e-12, ...
                'The frequency response runs from 0 Hz to Nyquist.');
            testCase.verifyEqual(seen.bothFrequencies, numel(bothFrequencies), ...
                'The frequency response is that of both filters together.');
            testCase.verifySubstring(seen.frequencyCaption, sprintf('Nyquist (%g Hz)', srate / 2));
            testCase.verifyEqual(seen.lowOnlyFrequencies, numel(lowOnlyFrequencies), ...
                'Unticking the high-pass redraws the frequency response.');
            testCase.verifySubstring(seen.noneCaption, 'No filter is ticked');
            testCase.verifyEmpty(seen.noneCurves, 'With no filter ticked there is nothing to plot.');

            function drive(src)
                f = findall(groot, 'Type', 'figure', 'Name', 'Filter');
                if isempty(f)
                    return;   % not up yet: the timer comes back
                end
                % The window exists before the dialog is built and its plot
                % drawn, and a timer can run in between: wait for the curve.
                frequencyAxes = findall(f(1), 'Tag', 'FrequencyAxes');
                curve = findobj(frequencyAxes, 'Tag', 'FrequencyResponse');
                if isempty(curve)
                    return;
                end
                stop(src);
                seen.impulseAxes = findall(f(1), 'Tag', 'ResponseAxes');
                seen.span = curve.XData([1 end]);
                seen.bothFrequencies = numel(curve.XData);
                seen.frequencyCaption = findall(f(1), 'Tag', 'FrequencyCaption').Text;
                highPass = findall(f(1), 'Type', 'uicheckbox', 'Text', 'High-pass');
                highPass.Value = false;
                highPass.ValueChangedFcn(highPass, []);
                seen.lowOnlyFrequencies = numel(findobj(frequencyAxes, 'Tag', 'FrequencyResponse').XData);
                lowPass = findall(f(1), 'Type', 'uicheckbox', 'Text', 'Low-pass');
                lowPass.Value = false;
                lowPass.ValueChangedFcn(lowPass, []);
                seen.noneCaption = findall(f(1), 'Tag', 'FrequencyCaption').Text;
                seen.noneCurves = findobj(frequencyAxes, 'Tag', 'FrequencyResponse');
                cancel = findall(f(1), 'Type', 'uibutton', 'Text', 'Cancel');
                cancel(1).ButtonPushedFcn(cancel(1), []);
            end
        end

        function theDialogTiesTheDesignAsFirfiltDoes(testCase)
        %THEDIALOGTIESTHEDESIGNASFIRFILTDOES  With the low-pass's Automatic
        %   unticked, an entered order gives invfirwsord's transition band,
        %   an entered transition band firwsord's order, and an entered ripple
        %   its attenuation; OK returns them.
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
            seen = struct('transitionFromOrder', [], 'orderFromTransition', [], 'dbFromRipple', []);
            timerObj = timer('ExecutionMode', 'fixedSpacing', 'Period', 1, ...
                'TasksToExecute', 60, 'TimerFcn', @(src, ~) drive(src));
            cleanup = onCleanup(@() cleanupTimer(timerObj));
            start(timerObj);
            options = FilterDialog(srate, {'Ch1', 'Ch2'}, filterOptions([], [30 40], []));
            clear cleanup;

            dev = 10 ^ (-40 / 20);
            testCase.verifyEqual(seen.transitionFromOrder, invfirwsord('kaiser', srate, 200, dev), 'RelTol', 1e-9);
            testCase.verifyEqual(seen.orderFromTransition, firwsord('kaiser', srate, 3, dev));
            testCase.verifyEqual(seen.dbFromRipple, -20 * log10(10 ^ (0.01 / 20) - 1), 'RelTol', 1e-9);
            testCase.assertNotEmpty(options, 'OK returns the options.');
            testCase.verifyFalse(options.lowpass.auto);
            testCase.verifyEqual(options.lowpass.db, seen.dbFromRipple, 'RelTol', 1e-9);

            function drive(src)
                f = findall(groot, 'Type', 'figure', 'Name', 'Filter');
                if isempty(f) || isempty(findobj(findall(f(1), 'Tag', 'FrequencyAxes'), 'Tag', 'FrequencyResponse'))
                    return;
                end
                stop(src);
                set1 = @(tag, value) setAndFire(findall(f(1), 'Tag', tag), value);
                set1('lowpassAuto', false);
                set1('lowpassOrder', 200);
                seen.transitionFromOrder = findall(f(1), 'Tag', 'lowpassTransition').Value;
                set1('lowpassTransition', 3);
                seen.orderFromTransition = findall(f(1), 'Tag', 'lowpassOrder').Value;
                set1('lowpassRipple', 0.01);
                seen.dbFromRipple = findall(f(1), 'Tag', 'lowpassDb').Value;
                ok = findall(f(1), 'Type', 'uibutton', 'Text', 'OK');
                ok(1).ButtonPushedFcn(ok(1), []);
            end
        end

        function thePickerTakesAnExportedFilter(testCase)
        %THEPICKERTAKESANEXPORTEDFILTER  A digitalFilter in the workspace, as
        %   the Filter Designer exports one, is listed and comes back as the
        %   coefficients Filter stores.
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'src')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'src', 'Support')));
            try
                probe = uifigure('Visible', 'off');
                delete(probe);
            catch ME
                testCase.assumeFail(['A uifigure could not be created here: ' ME.message]);
            end
            d = designfilt('bandpassiir', 'FilterOrder', 8, 'HalfPowerFrequency1', 1, ...
                'HalfPowerFrequency2', 30, 'SampleRate', 250);
            assignin('base', 'alakazamTestBandpass', d);
            testCase.addTeardown(@() evalin('base', 'clear alakazamTestBandpass'));
            timerObj = timer('ExecutionMode', 'fixedSpacing', 'Period', 1, ...
                'TasksToExecute', 60, 'TimerFcn', @(src, ~) drive(src));
            cleanup = onCleanup(@() cleanupTimer(timerObj));
            start(timerObj);
            spec = pickDesignedFilter(250);
            clear cleanup;

            testCase.assertNotEmpty(spec, 'Use returns the filter.');
            testCase.verifyEqual(spec.sos, d.Coefficients);
            testCase.verifyEqual(spec.srate, 250);
            testCase.verifySubstring(spec.source, 'alakazamTestBandpass');

            function drive(src)
                f = findall(groot, 'Type', 'figure', 'Name', 'Use a designed filter');
                if isempty(f)
                    return;
                end
                choice = findall(f(1), 'Tag', 'DesignedFilterChoice');
                hit = find(contains(choice.Items, 'alakazamTestBandpass'), 1);
                if isempty(hit)
                    return;
                end
                stop(src);
                choice.Value = choice.ItemsData(hit);
                use = findall(f(1), 'Tag', 'UseDesignedFilter');
                use.ButtonPushedFcn(use, []);
            end
        end
    end
end

function setAndFire(control, value)
%SETANDFIRE  Set a dialog control as a user would: the value, then its callback.
    control.Value = value;
    control.ValueChangedFcn(control, []);
end

function b = formerKernel(type, freq, db, srate)
%FORMERKERNEL  designFilterKernel as it was before the rest of the design
%   could be set, copied unchanged, so that an automatic design can be held
%   to it.
    nyq  = srate / 2;
    dev  = 10 ^ (-db / 20);
    beta = kaiserbeta(dev);
    switch type
        case 'high'
            df    = min(max(freq * 0.25, 1), freq * 0.9);
            fc    = freq / nyq;
            ftype = 'high';
        case 'low'
            df    = min(max(freq * 0.25, 2), (nyq - freq) * 0.9);
            fc    = freq / nyq;
            ftype = '';
        case 'notch'
            hbw = 1;
            df  = 1;
            fc    = [(freq - hbw) / nyq, (freq + hbw) / nyq];
            ftype = 'stop';
    end
    m = firwsord('kaiser', srate, df, dev);
    m = m + mod(m, 2);
    w = windows('kaiser', m + 1, beta);
    if isempty(ftype)
        b = firws(m, fc, w);
    else
        b = firws(m, fc, ftype, w);
    end
    b = reshape(b, 1, []);
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
