classdef PrepTest < matlab.unittest.TestCase
%PREPTEST  PREP: line noise, a robust average reference, and the bad
%   channels interpolated.
%
%   The choice of line frequencies is Alakazam's and is tested on its own.
%   The transformation is tested on a synthetic recording on a real montage
%   (makeScalpEEG) with 50 Hz mains on every channel, one channel far
%   noisier than the rest, a VEOG and an ECG: the noisy channel must be
%   found and interpolated, the mains removed, the scalp put on an average
%   reference, the VEOG cleaned and referenced with it, and the ECG left
%   exactly as it was. Those cases need EEGLAB and the PREP pipeline, and
%   are skipped without them (PREP is installed on first use of the
%   transformation, after consent).
%
%   Run with: runtests('tests/PrepTest.m').
%
%   See also PREP, PREPLINEFREQUENCIES, PREPTOOLBOX.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Transformations', 'PREP'), ...
                     fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        % ---- the line frequencies -----------------------------------------
        function theMainsAndItsHarmonicsBelowNyquist(testCase)
            testCase.verifyEqual(prepLineFrequencies('50', 500), [50 100 150 200], ...
                '250 Hz is the Nyquist frequency itself, where no sinusoid has a phase.');
            testCase.verifyEqual(prepLineFrequencies('60', 250), [60 120]);
            testCase.verifyEqual(prepLineFrequencies(50, 1000), 50:50:450);
        end

        function noneMeansNoLineNoiseRemoval(testCase)
            testCase.verifyEmpty(prepLineFrequencies('none', 500));
        end

        function anUnknownFrequencyIsRefused(testCase)
            testCase.verifyError(@() prepLineFrequencies('mains', 500), 'Alakazam:PREP');
        end

        function thePinnedVersionIsTheOneDescribed(testCase)
        %THEPINNEDVERSIONISTHEONEDESCRIBED  The archive, the version the
        %   consent dialog names, and the manual's toolbox table agree.
            spec = prepToolbox();
            testCase.verifySubstring(spec.Url, ['v' spec.Version '.zip']);
            root = fileparts(fileparts(mfilename('fullpath')));
            manual = fileread(fullfile(root, 'manual', 'chapters', '_02-installation.qmd'));
            testCase.verifySubstring(manual, spec.Version, ...
                'The manual''s table of toolboxes should name the pinned PREP version.');
        end

        % ---- the transformation ------------------------------------------
        function aNoisyChannelIsInterpolated(testCase)
            testCase.requirePrep();
            [EEG, noisy] = testCase.recording();

            out = PREP(EEG, testCase.options());

            testCase.verifyTrue(ismember(EEG.chanlocs(noisy).labels, out.etc.alz.prep.interpolated));
            testCase.verifyLessThan(std(out.data(noisy, :)), 0.5 * std(EEG.data(noisy, :)), ...
                'The interpolated channel carries its neighbours'' signal, not its own noise.');
        end

        function theMainsIsRemoved(testCase)
            testCase.requirePrep();
            EEG = testCase.recording();
            cz = strcmp({EEG.chanlocs.labels}, 'Cz');

            out = PREP(EEG, testCase.options());

            testCase.verifyLessThan(powerAt(out.data(cz, :), 50, EEG.srate), ...
                0.1 * powerAt(EEG.data(cz, :), 50, EEG.srate));
        end

        function theScalpIsOnAnAverageReference(testCase)
            testCase.requirePrep();
            EEG = testCase.recording();

            out = PREP(EEG, testCase.options());

            scalp = 1:19;
            testCase.verifyLessThan(max(abs(mean(out.data(scalp, :), 1))), 1e-6 * max(abs(out.data(scalp, :)), [], 'all') + 1e-9, ...
                'The robust reference is the average of the channels once the bad ones are interpolated.');
            testCase.verifyEqual(out.ref, 'average');
        end

        function theEogIsReferencedButTheEcgIsUntouched(testCase)
            testCase.requirePrep();
            EEG = testCase.recording();
            veog = strcmp({EEG.chanlocs.labels}, 'VEOG');
            ecg = strcmp({EEG.chanlocs.labels}, 'ECG');

            out = PREP(EEG, testCase.options());

            testCase.verifyEqual(out.data(ecg, :), double(EEG.data(ecg, :)));
            testCase.verifyNotEqual(out.data(veog, :), double(EEG.data(veog, :)));
            testCase.verifyFalse(ismember('VEOG', out.etc.alz.prep.referenceChannels), ...
                'An eye channel is referenced, but does not shape the reference.');
        end

        function aReplayReproducesTheResult(testCase)
            testCase.requirePrep();
            EEG = testCase.recording();

            [first, options] = PREP(EEG, testCase.options());
            second = PREP(EEG, options);

            testCase.verifyEqual(second.data, first.data);
        end

        function epochedDataIsRefused(testCase)
            testCase.requirePrep();
            testCase.verifyError(@() PREP(makeTestEEG(), testCase.options()), 'Alakazam:PREP');
        end
    end

    methods (Access = private)
        function requirePrep(testCase)
            try
                EEGLabEnvironment.ensure();
            catch
            end
            testCase.assumeTrue(exist('pop_chanedit', 'file') == 2, 'EEGLAB is not on the path.');
            testCase.assumeTrue(TransTools.ToolboxAvailable(prepToolbox()), ...
                'The PREP pipeline is not installed (PREP installs it on first use, after consent).');
        end

        function [EEG, noisy] = recording(~)
        %RECORDING  Two minutes at 256 Hz on the 10-20 channels plus a VEOG
        %   and an ECG, 50 Hz mains of 20 uV on every channel, and T8 twenty
        %   times noisier than the rest.
            EEG = makeScalpEEG('DataFormat', 'CONTINUOUS', 'seconds', 120, 'srate', 256, ...
                'extra', {'VEOG', 'ECG'}, 'seed', 31);
            t = (0:EEG.pnts - 1) / EEG.srate;
            EEG.data = EEG.data + 20 * sin(2 * pi * 50 * t);
            noisy = find(strcmp({EEG.chanlocs.labels}, 'T8'));
            stream = RandStream('mt19937ar', 'Seed', 32);
            EEG.data(noisy, :) = EEG.data(noisy, :) + 200 * randn(stream, 1, EEG.pnts);
        end

        function opts = options(~)
            opts = struct('LineFrequency', '50', 'DeviationThreshold', 5, ...
                'HighFrequencyThreshold', 5, 'CorrelationThreshold', 0.4, 'Ransac', true, ...
                'IgnoreBoundaries', false);
        end
    end
end

% ======================================================================= %
function p = powerAt(x, frequency, srate)
%POWERAT  The power of X at one frequency, from a single DFT coefficient.
    t = (0:numel(x) - 1) / srate;
    p = abs(sum(x .* exp(-2i * pi * frequency * t))) ^ 2 / numel(x);
end
