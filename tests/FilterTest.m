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

function a = freqAmplitude(sig, t, freq)
%FREQAMPLITUDE  The amplitude of SIG's component at exactly FREQ Hz, via a
%   direct single-frequency DFT (Goertzel-style demodulation) -- exact for
%   any FREQ, independent of any FFT bin-alignment/windowing concerns,
%   used here purely to compare a signal's own content before vs. after
%   filtering at a handful of known frequencies.
    a = 2 * abs(mean(sig .* exp(-2i * pi * freq * t)));
end
