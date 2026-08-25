classdef SpectralMeasureTest < matlab.unittest.TestCase
%SPECTRALMEASURETEST  Unit tests for
%   src/Transformations/SpectralMeasure/SpectralMeasure.m.
%
%   Most tests here lean on three EXACT mathematical identities rather than
%   an approximate numeric match, so they hold regardless of windowing/
%   leakage details:
%     1. power == amplitude.^2 -- a direct code relationship, true for any
%        signal (see the "power(c,b) = amplitude(c,b)^2" line in the source).
%     2. ITC (inter-trial phase-locking) is EXACTLY 1 for a single trial
%        (a lone unit phasor's own magnitude is 1) and EXACTLY 0 for two
%        trials whose signal is exactly antiphase (their unit phasors are
%        exact negatives, so they cancel to zero on averaging) -- both hold
%        by construction, no signal-specific numerics needed.
%     3. Coherence against a reference that is a POSITIVE REAL SCALAR
%        multiple of the channel itself is EXACTLY 1 (and phase-lag EXACTLY
%        0): if Xref = k*X for real k>0, the coherence formula's cross term
%        and denominator reduce algebraically to exactly 1 -- see this
%        file's own header comment in an earlier draft for the full algebra
%        (cross = k*sum(|X|^2), a positive real number, over
%        den = k^2*sum(|X|^2)^2, which is exactly k^2*sum(|X|^2)^2 too).
%
%   One test (amplitudeMatchesTheDocumentedCalibrationFormula) instead
%   independently re-derives the calibrated amplitude/phase using the same
%   Hann-taper formula the source documents (buildTapers'/tdft's own
%   comments), computed fresh in this test file rather than by calling any
%   internal SpectralMeasure.m function -- this catches wiring/indexing
%   bugs (is the right taper/trial/frequency actually being used?) but,
%   being the same formula, would not catch an error in the formula's own
%   derivation; the identity-based tests above are the stronger checks for
%   that.
%
%   Run with: runtests('tests/SpectralMeasureTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations', 'SpectralMeasure')));
            % SpectralMeasure shares Measure's own channel-spec parser
            % (measureChannelSpecs, which lives in the Measure folder), so
            % that sibling folder has to be on the path too. The running
            % app never notices the dependency because setupDirectories
            % adds Transformations with genpath, i.e. recursively; this
            % fixture adds only the two named folders, so without this the
            % whole class errored with "Undefined function
            % 'measureChannelSpecs'".
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations', 'Measure')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Support')));
        end
    end

    methods (Test)
        function powerEqualsAmplitudeSquared(testCase)
            EEG = toneFixture(10, 3, 0, 1); % 10 Hz, amplitude 3, phase 0, 1 trial
            row = defaultRow();
            m = runSpectralMeasure(EEG, row);
            testCase.verifyEqual(m.power, m.amplitude .^ 2, 'AbsTol', 1e-10);
        end

        function amplitudeMatchesTheDocumentedCalibrationFormula(testCase)
            srate = 250; nsamp = 250; f0 = 10; A = 3; phi = 0.5;
            EEG = toneFixture(f0, A, phi, 1, srate, nsamp);
            row = defaultRow();

            m = runSpectralMeasure(EEG, row);

            t = (0:nsamp - 1) / srate;
            taper = 0.5 - 0.5 * cos(2 * pi * (0:nsamp - 1)' / (nsamp - 1)); % same Hann formula as buildTapers
            V = A * cos(2 * pi * f0 * t + phi);
            X = sum(taper .* V(:) .* exp(-1i * 2 * pi * f0 * t(:)));       % same as tdft, single trial/taper
            expectedAmplitude = (2 / sum(taper)) * abs(X);
            expectedPhase = angle(X);

            testCase.verifyEqual(m.amplitude, expectedAmplitude, 'RelTol', 1e-9);
            testCase.verifyEqual(m.phase, expectedPhase, 'AbsTol', 1e-9);
        end

        function itcIsExactlyOneForASingleTrial(testCase)
            EEG = toneFixture(10, 3, 0, 1); % 1 trial
            row = defaultRow();
            m = runSpectralMeasure(EEG, row);
            testCase.verifyEqual(m.itc, 1, 'AbsTol', 1e-10);
        end

        function itcIsExactlyZeroForTwoAntiphaseTrials(testCase)
        %ITCISEXACTLYZEROFORTWOANTIPHASETRIALS  Trial 2's signal is the
        %   exact negation of trial 1's (phase shifted by pi): their raw
        %   tapered-DFT coefficients are then exact negatives too, so
        %   their unit phasors are exact opposites and cancel to zero on
        %   averaging.
            EEG = toneFixture(10, 3, [0, pi], 2); % 2 trials, phases 0 and pi
            row = defaultRow();
            m = runSpectralMeasure(EEG, row);
            testCase.verifyEqual(m.itc, 0, 'AbsTol', 1e-10);
        end

        function coherenceIsExactlyOneAgainstAPositiveScalarMultiple(testCase)
        %COHERENCEISEXACTLYONEAGAINSTAPOSITIVESCALARMULTIPLE  The
        %   reference channel is exactly 2x the signal channel (same
        %   phase and shape) -- algebraically, magnitude-squared
        %   coherence between a signal and any positive real scalar
        %   multiple of itself is exactly 1, and their phase-lag is
        %   exactly 0.
            EEG = toneFixture(10, 3, 0, 3, 250, 250, 2); % 2x scale on the reference channel
            row = defaultRow();
            opts = spectralOpts(row, 'ChRef');

            [result, ~] = SpectralMeasure(EEG, opts);
            m = result.spectralMeasures{1};

            testCase.verifyEqual(m.coherence, 1, 'AbsTol', 1e-9);
            testCase.verifyEqual(m.phaselag, 0, 'AbsTol', 1e-9);
        end

        function coherenceIsLowWhenReferenceHasIndependentTrialPhase(testCase)
        %COHERENCEISLOWWHENREFERENCEHASINDEPENDENTTRIALPHASE  Coherence
        %   measures trial-to-trial CONSISTENCY of the phase relationship
        %   between two channels, not whether they "look similar" -- with
        %   noiseless, exactly-repeated trials (as in every other test in
        %   this file), coherence between ANY two nonzero channels is
        %   exactly 1 regardless of their content, since there is no
        %   trial-to-trial variability for the cross-spectrum to average
        %   away. A genuinely low-coherence case needs real trial-to-trial
        %   phase variability: Ch1 is phase-locked (phase 0 every trial),
        %   ChRef has an INDEPENDENT random phase each trial. With 40
        %   trials, the expected coherence is ~1/nTrials =~ 0.025 (a
        %   random-walk-of-unit-phasors argument -- see this test's
        %   development notes), giving a very comfortable margin under the
        %   0.5 threshold; a fixed seed keeps the exact draw reproducible.
            rng(42);
            nTrials = 40; srate = 250; nsamp = 250; f0 = 10; A = 3;
            t = (0:nsamp - 1) / srate;
            refPhase = 2 * pi * rand(1, nTrials);
            data = zeros(2, nsamp, nTrials);
            for tr = 1:nTrials
                data(1, :, tr) = A * cos(2 * pi * f0 * t);              % Ch1: phase-locked
                data(2, :, tr) = A * cos(2 * pi * f0 * t + refPhase(tr)); % ChRef: independent phase
            end
            EEG = struct('DataFormat', 'EPOCHED', 'srate', srate, ...
                'chanlocs', struct('labels', {'Ch1', 'ChRef'}), 'data', data, ...
                'bindesc', struct('index', 1, 'label', 'Bin1', 'trials', 1:nTrials));
            row = defaultRow();
            opts = spectralOpts(row, 'ChRef');

            [result, ~] = SpectralMeasure(EEG, opts);
            m = result.spectralMeasures{1};

            testCase.verifyLessThan(m.coherence, 0.5);
        end

        function snrIsLargeForACleanTone(testCase)
        %SNRISLARGEFORACLEANTONE  A pure 10 Hz tone with no other spectral
        %   content should show a large SNR relative to its (near-empty)
        %   neighbouring frequency bins -- robust, not an exact figure.
            EEG = toneFixture(10, 3, 0, 3);
            row = defaultRow();
            m = runSpectralMeasure(EEG, row);
            testCase.verifyGreaterThan(m.snr, 10);
        end

        function rejectsNonEpochedData(testCase)
            EEG = toneFixture(10, 3, 0, 1);
            EEG.DataFormat = 'Averaged';
            row = defaultRow();
            opts = spectralOpts(row, '');
            testCase.verifyError(@() SpectralMeasure(EEG, opts), 'Alakazam:SpectralMeasure');
        end

        function rejectsEmptyRows(testCase)
            EEG = toneFixture(10, 3, 0, 1);
            opts = spectralOpts({}, '');
            testCase.verifyError(@() SpectralMeasure(EEG, opts), 'Alakazam:SpectralMeasure');
        end

        function rejectsUnknownReferenceChannel(testCase)
            EEG = toneFixture(10, 3, 0, 1);
            row = defaultRow();
            opts = spectralOpts(row, 'NoSuchChannel');
            testCase.verifyError(@() SpectralMeasure(EEG, opts), 'Alakazam:SpectralMeasure');
        end

        function rejectsFrequencyAtOrBeyondNyquist(testCase)
            EEG = toneFixture(10, 3, 0, 1, 250, 250); % Nyquist = 125 Hz
            row = defaultRow();
            row.freq = '125';
            opts = spectralOpts(row, '');
            testCase.verifyError(@() SpectralMeasure(EEG, opts), 'Alakazam:SpectralMeasure');
        end
    end
end

function EEG = toneFixture(f0, A, phases, nTrials, srate, nsamp, refScale)
%TONEFIXTURE  A 2-channel (Ch1, ChRef), EPOCHED EEG whose Ch1 is a pure
%   cosine at F0 Hz, amplitude A, one phase per trial (PHASES: either one
%   value applied to every trial, or one value per trial), and whose ChRef
%   is REFSCALE (default 1) times the SAME waveform -- a positive real
%   scalar multiple, used by the coherence tests. All trials fall in a
%   single bin.
    if nargin < 5; srate = 250; end
    if nargin < 6; nsamp = 250; end
    if nargin < 7; refScale = 1; end
    if isscalar(phases); phases = repmat(phases, 1, nTrials); end

    t = (0:nsamp - 1) / srate;
    data = zeros(2, nsamp, nTrials);
    for tr = 1:nTrials
        v = A * cos(2 * pi * f0 * t + phases(tr));
        data(1, :, tr) = v;
        data(2, :, tr) = refScale * v;
    end

    EEG = struct();
    EEG.DataFormat = 'EPOCHED';
    EEG.srate      = srate;
    EEG.chanlocs   = struct('labels', {'Ch1', 'ChRef'});
    EEG.data       = data;
    EEG.bindesc    = struct('index', 1, 'label', 'Bin1', 'trials', 1:nTrials);
end

function row = defaultRow()
    row = struct('label', 'R', 'freq', '10', 'channels', 'Ch1');
end

function opts = spectralOpts(rows, refChannel)
    if isstruct(rows); rows = {rows}; end
    opts = struct('rows', {rows}, 'fundamentals', '', 'refChannel', refChannel, ...
        'method', 'Hann', 'tapers', 3, 'snrNeighbours', 10, 'snrGuard', 1);
end

function m = runSpectralMeasure(EEG, row)
    opts = spectralOpts(row, '');
    [result, ~] = SpectralMeasure(EEG, opts);
    m = result.spectralMeasures{1};
end
