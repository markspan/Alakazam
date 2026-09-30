classdef ArtefactDetectFlatLineTest < matlab.unittest.TestCase
%ARTEFACTDETECTFLATLINETEST  ArtefactDetect's flat-line detector: a
%   channel whose voltage stays within a small range for too long.
%
%   A disconnected electrode, a saturated amplifier and a dropout all look
%   the same in the data: a stretch with (almost) no variation. The other
%   four detectors look for too much signal and cannot see too little. The
%   cases below pin what "flat" means (the range of the voltage itself, at
%   any offset, for at least the duration asked), what it does not (normal
%   EEG, a stretch shorter than asked, an already rejected stretch), and the
%   one flat channel that is not an artefact at all: the reference, exactly
%   zero throughout, which would otherwise reject every epoch.
%
%   Run with: runtests('tests/ArtefactDetectFlatLineTest.m').
%
%   See also ARTEFACTDETECT, ARTEFACTDETECTTEST.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Transformations', 'ArtefactDetect'), ...
                     fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function ordinaryEegIsNotFlat(testCase)
            EEG = testCase.noisyEEG();

            out = ArtefactDetect(EEG, testCase.options('Whole epoch'));

            testCase.verifyEqual(out.data, EEG.data);
        end

        function aFlatStretchRejectsItsEpoch(testCase)
            EEG = testCase.noisyEEG();
            EEG.data(2, 50:120, 3) = 0.2;      % 284 ms at 250 Hz, dead still

            out = ArtefactDetect(EEG, testCase.options('Whole epoch'));

            testCase.verifyTrue(all(isnan(out.data(:, :, 3)), 'all'));
            others = setdiff(1:size(EEG.data, 3), 3);
            testCase.verifyEqual(out.data(:, :, others), EEG.data(:, :, others));
        end

        function flatAtAnOffsetIsStillFlat(testCase)
        %FLATATANOFFSETISSTILLFLAT  The range of the voltage is tested, not
        %   the voltage against a band around zero: an electrode stuck at
        %   +40 uV records nothing just as surely as one stuck at zero.
            EEG = testCase.noisyEEG();
            EEG.data(1, 30:150, 2) = 40 + 0.1 * sin(1:121);

            out = ArtefactDetect(EEG, testCase.options('This channel only'));

            testCase.verifyTrue(all(isnan(out.data(1, :, 2))));
            testCase.verifyFalse(any(isnan(out.data(2:end, :, 2)), 'all'));
        end

        function aStretchShorterThanTheDurationIsNotFlat(testCase)
            EEG = testCase.noisyEEG();
            EEG.data(2, 50:70, 3) = 0.2;       % 84 ms, under the 200 ms asked

            out = ArtefactDetect(EEG, testCase.options('Whole epoch'));

            testCase.verifyEqual(out.data, EEG.data);
        end

        function aSmallButLiveSignalIsNotFlat(testCase)
        %ASMALLBUTLIVESIGNALISNOTFLAT  Quiet is not flat. A channel moving
        %   by 3 uV peak to peak is recording; the 1 uV default tolerance is
        %   below any real EEG.
            EEG = testCase.noisyEEG();
            EEG.data(2, :, 3) = 1.5 * sin(2 * pi * 10 * (1:size(EEG.data, 2)) / 250);

            out = ArtefactDetect(EEG, testCase.options('Whole epoch'));

            testCase.verifyEqual(out.data, EEG.data);
        end

        function theReferenceChannelIsSpared(testCase)
        %THEREFERENCECHANNELISSPARED  A channel that is exactly zero
        %   throughout is the reference, which ReRef keeps or reconstructs
        %   as zeros. Flat in every epoch by construction, it would reject
        %   every epoch under 'Whole epoch'.
            EEG = testCase.noisyEEG();
            EEG.data(3, :, :) = 0;

            out = ArtefactDetect(EEG, testCase.options('Whole epoch'));

            testCase.verifyEqual(out.data, EEG.data);
            testCase.verifyEqual(out.etc.alz.artefactDetectors.totalEpochs, 0);
        end

        function aDropoutToZeroIsNotMistakenForTheReference(testCase)
        %ADROPOUTTOZEROISNOTMISTAKENFORTHEREFERENCE  Zero in some epochs is
        %   a dropout, not a reference, and is flagged.
            EEG = testCase.noisyEEG();
            EEG.data(3, :, 2) = 0;

            out = ArtefactDetect(EEG, testCase.options('Whole epoch'));

            testCase.verifyTrue(all(isnan(out.data(:, :, 2)), 'all'));
            testCase.verifyEqual(out.etc.alz.artefactDetectors.totalEpochs, 1);
        end

        function theReferenceIsFoundPastEarlierRejections(testCase)
        %THEREFERENCEISFOUNDPASTEARLIERREJECTIONS  An epoch rejected by an
        %   earlier pass is NaN on every channel, the reference included;
        %   that must not stop the reference being recognised.
            EEG = testCase.noisyEEG();
            EEG.data(3, :, :) = 0;
            EEG.data(:, :, 4) = NaN;

            out = ArtefactDetect(EEG, testCase.options('Whole epoch'));

            testCase.verifyTrue(isequaln(out.data, EEG.data), ...
                'Nothing beyond the earlier rejection should be rejected.');
        end

        function anAlreadyRejectedStretchIsNotCountedAgain(testCase)
            EEG = testCase.noisyEEG();
            EEG.data(2, :, 3) = NaN;           % rejected by an earlier pass

            out = ArtefactDetect(EEG, testCase.options('This channel only'));

            testCase.verifyEqual(out.etc.alz.artefactDetectors.channelEpochs, 0);
        end

        function theBreakdownNamesTheDetector(testCase)
            EEG = testCase.noisyEEG();
            EEG.data(2, 50:120, 3) = 0.2;

            out = ArtefactDetect(EEG, testCase.options('Whole epoch'));

            d = out.etc.alz.artefactDetectors;
            testCase.verifyEqual(d.methods, {'Flat line'});
            testCase.verifyEqual(d.epochs, 1);
        end

        function anOldOptionsStructGetsTheDefaults(testCase)
        %ANOLDOPTIONSSTRUCTGETSTHEDEFAULTS  A node stored before the flat-line
        %   fields existed replays: 1 uV for 200 ms.
            EEG = testCase.noisyEEG();
            EEG.data(2, 50:120, 3) = 0.2;
            opts = struct('Method', {{'Flat line'}}, 'Scope', 'Whole epoch');

            out = ArtefactDetect(EEG, opts);

            testCase.verifyTrue(all(isnan(out.data(:, :, 3)), 'all'));
        end
    end

    methods (Access = private)
        function EEG = noisyEEG(~)
        %NOISYEEG  Three channels of 20 uV noise at 250 Hz, six epochs:
        %   nowhere near flat, anywhere.
            EEG = makeTestEEG('nbchan', 3, 'trials', 6);
            rng(7, 'twister');
            EEG.data = 20 * randn(size(EEG.data));
        end

        function opts = options(~, scope)
            opts = struct('Method', {{'Flat line'}}, 'FlatTolerance', 1, ...
                'FlatDuration', 200, 'TestStart', 0, 'TestStop', 0, 'Scope', scope);
        end
    end
end
