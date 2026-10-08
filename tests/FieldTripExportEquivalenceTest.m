classdef FieldTripExportEquivalenceTest < matlab.unittest.TestCase
%FIELDTRIPEXPORTEQUIVALENCETEST  A step the FieldTrip export calls exact must
%   give, in FieldTrip, what the transformation gives in Alakazam.
%
%   The same rule as NativeExportEquivalenceTest, for the other export: a
%   script that runs without Alakazam is only worth having if its numbers
%   are Alakazam's, and "it produced a script" is no evidence of that. Each
%   case runs the transformation on a recording and the lines
%   fieldtripTransformCall emits on the same recording as FieldTrip data,
%   and compares every channel of every sample. The emitter's own lines are
%   evaluated, never a version re-typed here, and the helper the script
%   carries (addChannel) is taken from a generated script.
%
%   THE RECORDING: 20 s of four channels at 250 Hz, sines in noise from a
%   fixed seed, with an event every 0.8 s alternating between codes 11 and
%   22, long enough for a 1 Hz high-pass.
%
%   Needs EEGLAB (pop_reref, firfilt) and FieldTrip; skips without either.
%
%   See also FIELDTRIPTRANSFORMCALL, EXPORTFIELDTRIPSCRIPT,
%   NATIVEEXPORTEQUIVALENCETEST.

    properties (Constant)
        Labels = {'Fz', 'Cz', 'Pz', 'Oz'}
    end

    properties
        HelperFolder
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'src')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations'), 'IncludeSubfolders', true));
            for p = {fullfile(root, 'src', 'IO'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
            try
                EEGLabEnvironment.ensure();
            catch
                % The assumption below says what is missing.
            end
            testCase.assumeTrue(exist('pop_reref', 'file') == 2 && exist('firfilt', 'file') == 2 && ...
                exist('eeg_emptyset', 'file') == 2, 'EEGLAB with firfilt is not on the path.');
            FieldTripFixtures.require(testCase);
        end

        function writeTheScriptsHelper(testCase)
        %WRITETHESCRIPTSHELPER  addChannel, as a generated script carries it.
            subject = struct('name', 'probe', 'rawFile', 'probe.vhdr', 'steps', ...
                struct('transformId', 'DeriveChannels', 'params', ...
                    struct('derivations', 'let d = Fz - Cz'), 'parent', -1), ...
                'contexts', struct('srate', 250, 'labels', {testCase.Labels}, ...
                    'format', 'CONTINUOUS', 'decision', []));
            code = exportFieldTripScript(subject);
            at = strfind(code, 'function data = addChannel(');
            testCase.assertNotEmpty(at, 'The generated script carries no addChannel.');
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            fid = fopen(fullfile(folder, 'addChannel.m'), 'w');
            fwrite(fid, code(at:end), 'char');
            fclose(fid);
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(folder));
            testCase.HelperFolder = folder;
        end
    end

    methods (Test)
        function anAverageReference(testCase)
            testCase.verifyStep('ReRef', struct('mode', 'Average', 'refChannels', {{}}, ...
                'exclude', {{}}, 'keepref', false, 'implicitRef', ''));
        end

        function linkedReferencesWithTheImplicitOneRebuilt(testCase)
        %LINKEDREFERENCESWITHTHEIMPLICITONEREBUILT  As FieldTrip's ERP
        %   tutorial references its recording: LM was the reference and is
        %   rebuilt, then the mean of LM and Oz is the new one, both kept.
            testCase.verifyStep('ReRef', struct('mode', 'Specific channels', ...
                'refChannels', {{'LM', 'Oz'}}, 'exclude', {{}}, 'keepref', true, 'implicitRef', 'LM'));
        end

        function aReferenceChannelIsDroppedUnlessKept(testCase)
            [alakazam, fieldtrip] = testCase.verifyStep('ReRef', struct('mode', 'Specific channels', ...
                'refChannels', {{'Oz'}}, 'exclude', {{}}, 'keepref', false, 'implicitRef', ''));
            testCase.verifyEqual(fieldtrip.label(:)', {alakazam.chanlocs.labels});
        end

        function eachOfFiltersWindowedSincs(testCase)
        %EACHOFFILTERSWINDOWEDSINCS  A high-pass, a low-pass, a notch and all
        %   three at once, with automatic designs and one set by hand: the
        %   same kernel in FieldTrip's firws, applied the same way.
            off = struct('enabled', false, 'freq', 1, 'db', 40, 'auto', true, 'transition', [], 'order', []);
            on = @(freq, db) struct('enabled', true, 'freq', freq, 'db', db, 'auto', true, ...
                'transition', [], 'order', []);
            base = struct('highpass', off, 'lowpass', off, 'notch', off, 'perChannel', false);
            cases = {struct('highpass', on(1, 40)), struct('lowpass', on(30, 60)), ...
                struct('notch', setfield(on(50, 40), 'width', 2)), ...
                struct('highpass', on(0.5, 40), 'lowpass', on(40, 40), 'notch', setfield(on(50, 40), 'width', 2)), ...
                struct('lowpass', struct('enabled', true, 'freq', 20, 'db', 50, 'auto', false, ...
                    'transition', [], 'order', 120))};
            for c = 1:numel(cases)
                params = base;
                for f = fieldnames(cases{c})'
                    params.(f{1}) = cases{c}.(f{1});
                end
                testCase.verifyStep('Filter', params);
            end
        end

        function aFilterOnTrials(testCase)
        %AFILTERONTRIALS  Filtered after the trials are cut: each trial on its
        %   own, in both.
            off = struct('enabled', false, 'freq', 1, 'db', 40, 'auto', true, 'transition', [], 'order', []);
            params = struct('highpass', off, 'lowpass', struct('enabled', true, 'freq', 30, 'db', 40, ...
                'auto', true, 'transition', [], 'order', []), 'notch', off, 'perChannel', false);
            [EEG, data] = testCase.trials();
            testCase.verifyStep('Filter', params, EEG, data);
        end

        function aWeightedSumOfChannels(testCase)
            testCase.verifyStep('DeriveChannels', struct('derivations', ...
                sprintf('let front = Fz - 0.5*Cz + Pz/4\nlet back = -(Oz - front)')));
        end

        function aSelectionOfChannels(testCase)
            testCase.verifyStep('SelectData', struct('channels', struct('mode', 'Remove', ...
                'labels', {{'Cz'}}), 'time', struct('mode', '(off)', 'range', []), ...
                'points', struct('mode', '(off)', 'range', []), 'trials', struct('mode', '(off)', 'indices', [])));
            testCase.verifyStep('SelectData', struct('channels', struct('mode', 'Keep', ...
                'labels', {{'Pz', 'Fz'}}), 'time', struct('mode', '(off)', 'range', []), ...
                'points', struct('mode', '(off)', 'range', []), 'trials', struct('mode', '(off)', 'indices', [])));
        end

        function theTrialsDefineBinsCut(testCase)
        %THETRIALSDEFINEBINSCUT  Read back as FieldTrip's trl: the same
        %   samples in every trial, and the bins in its trialinfo.
            [EEG, data, ctx] = testCase.trials();
            testCase.verifyEqual(numel(data.trial), EEG.trials);
            for t = 1:EEG.trials
                testCase.verifyEqual(data.trial{t}, double(EEG.data(:, :, t)), 'AbsTol', 1e-12, ...
                    sprintf('Trial %d.', t));
            end
            testCase.verifyEqual(data.time{1} * 1000, EEG.times, 'AbsTol', 1e-9);
            testCase.verifyEqual(logical(data.trialinfo(:, 1:2)), ctx.decision.membership);
        end

        function aBaselineOnTrials(testCase)
            [EEG, data] = testCase.trials();
            testCase.verifyStep('Baseline', struct('Start', -200, 'Stop', 0), EEG, data);
        end

        function anAverageWithADifferenceBin(testCase)
            [EEG, data, defined] = testCase.trials();
            averaged = Average(EEG, struct('Param', 'Init'));
            ctx = fieldtripStepContext('Average', EEG, averaged);
            names = struct('in', 'data', 'out', 'erp', 'trials', 'trials', 'step', 2, ...
                'binColumns', [defined.decision.bins.index]);
            step = fieldtripTransformCall('Average', struct('Param', 'Init'), ctx, names);
            testCase.assertEqual(step.status, 'exact');
            erp = runEmitted(step.lines, data, 'erp');
            testCase.assertNumElements(erp, 3);
            for b = 1:3
                testCase.verifyEqual(erp{b}.avg, double(averaged.data(:, :, b)), 'AbsTol', 1e-10, ...
                    sprintf('Bin %d (%s).', b, averaged.bindesc(b).label));
            end
        end
    end

    methods (Access = private)
        function [alakazam, fieldtrip] = verifyStep(testCase, transformId, params, EEG, data)
        %VERIFYSTEP  The transformation and its emitted FieldTrip lines on the
        %   same recording (the continuous one unless EEG and DATA are given):
        %   the same channels, in order, and the same samples.
            if nargin < 4
                EEG = testCase.recording();
                data = asFieldTrip(EEG);
            end
            ctx = fieldtripStepContext(transformId, EEG, EEG);
            names = struct('in', 'data', 'out', 'data', 'trials', 'trials', 'step', 1, 'binColumns', []);
            step = fieldtripTransformCall(transformId, params, ctx, names);
            testCase.assertEqual(step.status, 'exact', sprintf('%s: %s', transformId, step.summary));
            alakazam = feval(transformId, EEG, params);
            fieldtrip = runEmitted(step.lines, data, 'data');
            testCase.assertEqual(fieldtrip.label(:)', {alakazam.chanlocs.labels}, ...
                sprintf('%s: the channels, in order.', transformId));
            for t = 1:numel(fieldtrip.trial)
                expected = double(alakazam.data(:, :, t));
                testCase.verifyEqual(fieldtrip.trial{t}, expected, 'AbsTol', 1e-9 * max(1, max(abs(expected(:)))), ...
                    sprintf('%s, trial %d: %s', transformId, t, step.summary));
            end
        end

        function EEG = recording(testCase)
        %RECORDING  The continuous test recording, laid over EEGLAB's empty
        %   set, which pop_reref and pop_select read fields from.
            srate = 250;
            n = 20 * srate;
            stream = RandStream('mt19937ar', 'Seed', 7);
            t = (0:n - 1) / srate;
            data = 10 * randn(stream, numel(testCase.Labels), n);
            for c = 1:numel(testCase.Labels)
                data(c, :) = data(c, :) + 20 * sin(2 * pi * (2 + 3 * c) * t) + 5 * sin(2 * pi * 50 * t);
            end
            EEG = eeg_emptyset();
            EEG.data = data;
            EEG.srate = srate;
            EEG.nbchan = size(data, 1);
            EEG.pnts = n;
            EEG.trials = 1;
            EEG.times = t;
            EEG.xmin = 0;
            EEG.xmax = t(end);
            EEG.chanlocs = struct('labels', testCase.Labels);
            EEG.DataFormat = 'CONTINUOUS';
            EEG.DataType = 'TIMEDOMAIN';
            latency = 200:200:(n - 300);
            codes = repmat({'11', '22'}, 1, ceil(numel(latency) / 2));
            EEG.event = struct('type', codes(1:numel(latency)), 'latency', num2cell(latency));
        end

        function [EEG, data, ctx] = trials(testCase)
        %TRIALS  The recording cut by DefineBins into two bins and their
        %   difference, and the same trials cut in FieldTrip from the
        %   decision the export carries.
            continuous = testCase.recording();
            params = struct('script', sprintf(['epoch [-200,600] ms\nbin 1 "A" : "11"\n' ...
                'bin 2 "B" : "22"\nbin 3 "A - B" = bin 1 - bin 2']));
            EEG = DefineBins(continuous, params);
            ctx = fieldtripStepContext('DefineBins', continuous, EEG);
            d = ctx.decision;
            trials = table((1:numel(d.epochStart))', d.epochStart, d.epochStart + d.pnts - 1, ...
                repmat(d.offset, numel(d.epochStart), 1), double(d.membership(:, 1)), ...
                double(d.membership(:, 2)), 'VariableNames', ...
                {'trial', 'begsample', 'endsample', 'offset', 'bin_1', 'bin_2'}); %#ok<NASGU> read by the emitted lines
            names = struct('in', 'data', 'out', 'data', 'trials', 'trials', 'step', 1, 'binColumns', []);
            step = fieldtripTransformCall('DefineBins', params, ctx, names);
            testCase.assertEqual(step.status, 'decision');
            data = runEmitted(step.lines, asFieldTrip(continuous), 'data', trials);
        end
    end
end

% ======================================================================= %
function data = asFieldTrip(EEG)
%ASFIELDTRIP  A continuous Alakazam recording as FieldTrip raw data, as
%   ft_preprocessing reads it from a file.
    data = struct('label', {reshape({EEG.chanlocs.labels}, [], 1)}, 'fsample', EEG.srate, ...
        'trial', {{double(EEG.data)}}, 'time', {{(0:EEG.pnts - 1) / EEG.srate}}, ...
        'sampleinfo', [1 EEG.pnts]);
end

function out = runEmitted(lines, data, variable, trials) %#ok<INUSD> data and trials are read by the lines
%RUNEMITTED  Evaluate an emitted step on DATA (and TRIALS, the table of
%   trials), quietly, and return the variable it assigns.
    evalc(strjoin(lines, newline));
    out = eval(variable);
end
