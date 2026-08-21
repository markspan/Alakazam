classdef MeasureTest < matlab.unittest.TestCase
%MEASURETEST  Unit tests for src/Transformations/Measure/Measure.m.
%
%   Every signal here is a small, hand-picked waveform (a flat line, a
%   linear ramp, a symmetric bump) chosen so the expected amplitude/
%   latency/area can be computed by hand (trapezoidal area, linear
%   interpolation) and checked exactly -- not a realistic ERP shape, but a
%   shape whose correct answer is unambiguous.
%
%   Run with: runtests('tests/MeasureTest.m').
%
%   See also MEASUREDERIVATIONS, MEASURECHANNELSPECS.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations', 'Measure')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations')));
        end
    end

    methods (Test)
        function meanAmplitudeOfAFlatSignal(testCase)
            EEG = measureFixture({'Ch1'}, [5 5 5 5 5], [0 4 8 12 16]);
            win = defaultWindow();
            win.start = 0; win.stop = 16; win.measure = 'Mean Amplitude';

            result = runMeasure(EEG, win);

            testCase.verifyEqual(result.amplitude, 5, 'AbsTol', 1e-10);
        end

        function peakFindsTheAbsoluteExtremeByDefault(testCase)
        %PEAKFINDSTHEABSOLUTEEXTREMEBYDEFAULT  With localPoints = 0, Peak
        %   is the plain global extreme -- here, the very first sample.
            data = [50 45 40 35 30 10 12 15 12 10 5 3 2 1 0];
            times = (0:14) * 4;
            EEG = measureFixture({'Ch1'}, data, times);
            win = defaultWindow();
            win.start = times(1); win.stop = times(end); win.measure = 'Peak';

            result = runMeasure(EEG, win);

            testCase.verifyEqual(result.amplitude, 50, 'AbsTol', 1e-10);
            testCase.verifyEqual(result.latency, 0, 'AbsTol', 1e-10);
        end

        function peakWithLocalPointsFindsALocalExtremumInstead(testCase)
        %PEAKWITHLOCALPOINTSFINDSALOCALEXTREMUMINSTEAD  Same data as
        %   above: with localPoints = 2, sample 1 (the global max, 50) is
        %   not even an eligible local-peak candidate (too close to the
        %   window edge), and the ONLY sample satisfying "at least as
        %   extreme as its 2 neighbours each side" is index 8 (value 15) --
        %   hand-verified by checking every other interior index fails
        %   that condition. See this file's own header on how these
        %   numbers were chosen.
            data = [50 45 40 35 30 10 12 15 12 10 5 3 2 1 0];
            times = (0:14) * 4;
            EEG = measureFixture({'Ch1'}, data, times);
            win = defaultWindow();
            win.start = times(1); win.stop = times(end); win.measure = 'Peak';
            win.localPoints = 2;

            result = runMeasure(EEG, win);

            testCase.verifyEqual(result.amplitude, 15, 'AbsTol', 1e-10);
            testCase.verifyEqual(result.latency, times(8), 'AbsTol', 1e-10);
        end

        function areaModesMatchHandComputedTrapezoids(testCase)
        %AREAMODESMATCHHANDCOMPUTEDTRAPEZOIDS  A symmetric [0 10 0 -10 0]
        %   bump-then-dip: signed area cancels to 0; rectified sums both
        %   lobes' magnitude; positive/negative isolate one lobe each.
            times = [0 4 8 12 16];
            EEG = measureFixture({'Ch1'}, [0 10 0 -10 0], times);

            expected = struct('signed', 0, 'rectified', 80, 'positive', 40, 'negative', -40);
            modes = fieldnames(expected);
            for i = 1:numel(modes)
                win = defaultWindow();
                win.start = 0; win.stop = 16; win.measure = 'Area';
                win.areaMode = modes{i};
                result = runMeasure(EEG, win);
                testCase.verifyEqual(result.area, expected.(modes{i}), 'AbsTol', 1e-10, ...
                    sprintf('areaMode "%s"', modes{i}));
            end
        end

        function peakLockedBandAreaClampsToTheRequestedWidth(testCase)
        %PEAKLOCKEDBANDAREACLAMPSTOTHEREQUESTEDWIDTH  A symmetric bump
        %   peaking at t=12 (value 10); an 8 ms band around it covers
        %   samples at t=8,12,16 (values 9,10,9), whose trapezoidal area
        %   is 76 -- hand-computed in this file's own development notes,
        %   reproduced in the assertion below.
            times = [0 4 8 12 16 20 24];
            EEG = measureFixture({'Ch1'}, [2 6 9 10 9 6 2], times);
            win = defaultWindow();
            win.start = times(1); win.stop = times(end);
            win.measure = 'Area'; win.width = 8; win.areaMode = 'signed';

            result = runMeasure(EEG, win);

            testCase.verifyEqual(result.amplitude, 10, 'AbsTol', 1e-10);
            testCase.verifyEqual(result.latency, 12, 'AbsTol', 1e-10);
            testCase.verifyEqual(result.area, 76, 'AbsTol', 1e-10); % (9+10)/2*4 + (10+9)/2*4
        end

        function fractionalPeakLatencyInterpolatesBetweenSamples(testCase)
        %FRACTIONALPEAKLATENCYINTERPOLATESBETWEENSAMPLES  A ramp [0 3 6 9
        %   10] peaking at t=16 (value 10); the 50% threshold (5) is
        %   crossed between samples at t=4 (value 3) and t=8 (value 6),
        %   linearly interpolating to 4 + (5-3)/(6-3)*4 = 20/3 ms.
            times = [0 4 8 12 16];
            EEG = measureFixture({'Ch1'}, [0 3 6 9 10], times);
            win = defaultWindow();
            win.start = times(1); win.stop = times(end);
            win.measure = 'Fractional Peak Latency'; win.fraction = 0.5;

            result = runMeasure(EEG, win);

            testCase.verifyEqual(result.latency, 20 / 3, 'AbsTol', 1e-9);
        end

        function fractionalAreaLatencyOnAConstantSignalIsTheMidpoint(testCase)
        %FRACTIONALAREALATENCYONACONSTANTSIGNALISTHEMIDPOINT  A constant
        %   signal accumulates area linearly with time, so its 50% area
        %   latency is exactly the midpoint of the window (t=8 of 0..16).
            times = [0 4 8 12 16];
            EEG = measureFixture({'Ch1'}, [5 5 5 5 5], times);
            win = defaultWindow();
            win.start = times(1); win.stop = times(end);
            win.measure = 'Fractional Area Latency'; win.fraction = 0.5;

            result = runMeasure(EEG, win);

            testCase.verifyEqual(result.latency, 8, 'AbsTol', 1e-10);
        end

        function referenceChannelSharesItsPeakSampleWithOtherChannels(testCase)
        %REFERENCECHANNELSHARESITSPEAKSAMPLEWITHOTHERCHANNELS  ChA (the
        %   reference) peaks at t=4; with refChannel='ChA', ChB's reported
        %   latency must be ChA's own peak latency (t=4), and its reported
        %   amplitude must be CHB's OWN value at that sample (2) -- NOT
        %   ChB's own true maximum (20 at t=12).
            times = [0 4 8 12 16];
            EEG = measureFixture({'ChA', 'ChB'}, [0 10 0 0 0; 0 2 0 20 0], times);
            win = defaultWindow();
            win.start = times(1); win.stop = times(end);
            win.measure = 'Peak'; win.refChannel = 'ChA';

            result = runMeasure(EEG, win);

            testCase.verifyEqual(result.amplitude(1), 10, 'AbsTol', 1e-10); % ChA's own peak
            testCase.verifyEqual(result.latency(1), 4, 'AbsTol', 1e-10);
            testCase.verifyEqual(result.amplitude(2), 2, 'AbsTol', 1e-10);  % ChB at ChA's sample, not ChB's own max
            testCase.verifyEqual(result.latency(2), 4, 'AbsTol', 1e-10);
        end

        function roiPoolingMeasuresTheMeanOfItsMembers(testCase)
        %ROIPOOLINGMEASURESTHEMEANOFITSMEMBERS  {ChA ChB} pools to the
        %   mean of two constant channels (10 and 20 -> 15), and the
        %   output channel label reflects the pool.
            EEG = measureFixture({'ChA', 'ChB'}, [10 10 10; 20 20 20], [0 4 8]);
            win = defaultWindow();
            win.start = 0; win.stop = 8; win.measure = 'Mean Amplitude';
            win.channels = '{ChA ChB}';

            result = runMeasure(EEG, win);

            testCase.verifyEqual(result.amplitude, 15, 'AbsTol', 1e-10);
            testCase.verifyEqual(result.channels{1}, '{ChA+ChB}');
        end

        function derivedChannelIsMeasurableLikeAnyOther(testCase)
        %DERIVEDCHANNELISMEASURABLELIKEANYOTHER  A "let Diff = ChA - ChB"
        %   derivation (10 - 3 = 7, both constant) should be measurable by
        %   name, same as a real channel.
            EEG = measureFixture({'ChA', 'ChB'}, [10 10 10; 3 3 3], [0 4 8]);
            win = defaultWindow();
            win.start = 0; win.stop = 8; win.measure = 'Mean Amplitude';
            win.channels = 'Diff';

            opts = struct('windows', {{win}}, 'derivations', 'let Diff = ChA - ChB');
            [result, ~] = Measure(EEG, opts);

            testCase.verifyEqual(result.measurements{1}.amplitude, 7, 'AbsTol', 1e-10);
        end

        function baselineSubtractsThePreWindowMean(testCase)
        %BASELINESUBTRACTSTHEPREWINDOWMEAN  A 10 uV baseline segment
        %   (t = -8 to -4) followed by a 15 uV main window: after baseline
        %   correction, Mean Amplitude reads 15 - 10 = 5.
            times = [-8 -4 0 4 8 12];
            EEG = measureFixture({'Ch1'}, [10 10 15 15 15 15], times);
            win = defaultWindow();
            win.start = 0; win.stop = 12; win.measure = 'Mean Amplitude';
            win.baseline = [-8, -4];

            result = runMeasure(EEG, win);

            testCase.verifyEqual(result.amplitude, 5, 'AbsTol', 1e-10);
        end

        function rejectsNonAveragedData(testCase)
            EEG = measureFixture({'Ch1'}, [1 2 3], [0 4 8]);
            EEG.DataFormat = 'Epoched';
            win = defaultWindow();
            opts = struct('windows', {{win}}, 'derivations', '');
            testCase.verifyError(@() Measure(EEG, opts), 'Alakazam:Measure');
        end

        function rejectsEmptyWindows(testCase)
            EEG = measureFixture({'Ch1'}, [1 2 3], [0 4 8]);
            opts = struct('windows', {{}}, 'derivations', '');
            testCase.verifyError(@() Measure(EEG, opts), 'Alakazam:Measure');
        end

        function rejectsFractionOutOfRange(testCase)
            EEG = measureFixture({'Ch1'}, [1 2 3], [0 4 8]);
            win = defaultWindow();
            win.start = 0; win.stop = 8;
            win.measure = 'Fractional Peak Latency'; win.fraction = 1.5;
            opts = struct('windows', {{win}}, 'derivations', '');
            testCase.verifyError(@() Measure(EEG, opts), 'Alakazam:Measure');
        end

        function rejectsPeakAreaWithNoPositiveWidth(testCase)
            EEG = measureFixture({'Ch1'}, [1 2 3], [0 4 8]);
            win = defaultWindow();
            win.start = 0; win.stop = 8; win.measure = 'Peak Area'; % legacy name, forces band mode
            win.width = [];
            opts = struct('windows', {{win}}, 'derivations', '');
            testCase.verifyError(@() Measure(EEG, opts), 'Alakazam:Measure');
        end

        function rejectsUnknownReferenceChannel(testCase)
            EEG = measureFixture({'Ch1'}, [1 2 3], [0 4 8]);
            win = defaultWindow();
            win.start = 0; win.stop = 8; win.measure = 'Peak'; win.refChannel = 'NoSuchChannel';
            opts = struct('windows', {{win}}, 'derivations', '');
            testCase.verifyError(@() Measure(EEG, opts), 'Alakazam:Measure');
        end
    end
end

function EEG = measureFixture(labels, data, times)
%MEASUREFIXTURE  A minimal Averaged EEG: DATA is nChan x nSamp (2-D, i.e.
%   unbinned -- size(data,3) is then 1 automatically, matching Measure.m's
%   own "1 for an unbinned average" convention).
    EEG = struct();
    EEG.DataFormat = 'Averaged';
    EEG.chanlocs   = struct('labels', labels);
    EEG.data       = data;
    EEG.times      = times;
    EEG.nbchan     = numel(labels);
end

function win = defaultWindow()
%DEFAULTWINDOW  A window struct with every field Measure.m reads directly
%   (not through one of its own tolerant winX accessors) set to a sane
%   default; each test overrides only the fields it cares about.
    win = struct('label', 'W', 'start', 0, 'stop', 0, 'measure', 'Mean Amplitude', ...
        'polarity', 'Positive', 'width', [], 'localPoints', 0, 'fraction', [], ...
        'areaMode', 'signed', 'baseline', [], 'refChannel', '', 'channels', '');
end

function m = runMeasure(EEG, win)
%RUNMEASURE  Run Measure on EEG with a single window WIN and return that
%   window's own measurement struct directly (skipping the
%   opts/EEG.measurements{1} boilerplate every test would otherwise repeat).
    opts = struct('windows', {{win}}, 'derivations', '');
    [result, ~] = Measure(EEG, opts);
    m = result.measurements{1};
end
