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

        function writeTheScriptsHelpers(testCase)
        %WRITETHESCRIPTSHELPERS  addChannel and restoreChannelOrder, each in a
        %   file of its own, taken from a generated script that calls both.
            labels = testCase.Labels;
            ica = struct('unmixing', eye(4), 'topolabel', {labels(:)}, 'removed', 1, ...
                'why', 'chosen by hand', 'exact', true, 'method', 'fastica', 'templates', ones(4, 1));
            subject = struct('name', 'probe', 'rawFile', 'probe.vhdr', 'steps', ...
                struct('transformId', {'DeriveChannels', 'RemoveComponents'}, 'params', ...
                    {struct('derivations', 'let d = Fz - Cz'), struct('components', 1)}, ...
                    'parent', {-1, 1}), ...
                'contexts', struct('srate', 250, 'labels', {labels, labels}, ...
                    'format', 'CONTINUOUS', 'decision', {[], ica}));
            code = [exportFieldTripScript(subject), newline, ...
                exportFieldTripScript(subject, struct('mode', 'rerun'))];
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            for name = {'addChannel', 'restoreChannelOrder', 'matchComponents'}
                at = regexp(code, ['function (\w+ = )?' name{1} '\('], 'once');
                testCase.assertNotEmpty(at, sprintf('The generated script carries no %s.', name{1}));
                rest = code(at:end);
                stop = regexp(rest, '\nend(\r?\n|$)', 'end', 'once');   % a helper ends at column 0
                rest = rest(1:stop);
                fid = fopen(fullfile(folder, [name{1} '.m']), 'w');
                fwrite(fid, rest, 'char');
                fclose(fid);
            end
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

        function componentsRemovedByHand(testCase)
        %COMPONENTSREMOVEDBYHAND  RemoveComponents on a full decomposition:
        %   the components it took out, taken out by ft_rejectcomponent.
            EEG = testCase.decomposed(testCase.recording(), 4);
            testCase.verifyIca(EEG, [1 3], 'decision');
        end

        function componentsFromADecompositionOfReducedRank(testCase)
        %COMPONENTSFROMADECOMPOSITIONOFREDUCEDRANK  Average-referenced data
        %   have one dimension fewer than channels, and a decomposition of that
        %   rank spans them: subtracting is what pop_subcomp's rebuilding gives.
            EEG = testCase.recording();
            EEG.data = EEG.data - mean(EEG.data, 1);
            testCase.verifyIca(testCase.decomposed(EEG, 3), 2, 'decision');
        end

        function aChannelLeftOutOfTheDecompositionKeepsItsPlace(testCase)
        %ACHANNELLEFTOUTOFTHEDECOMPOSITIONKEEPSITSPLACE  As an EOG channel
        %   with no scalp position is left out of AutoEyeICA's: Cz here.
        %   ft_rejectcomponent puts such channels last; the script puts them
        %   back.
            EEG = testCase.recording();
            kept = [1 3 4];
            part = EEG;
            part.data = EEG.data(kept, :);
            part = testCase.decomposed(part, 3);
            EEG.icaweights = part.icaweights;
            EEG.icasphere = part.icasphere;
            EEG.icawinv = part.icawinv;
            EEG.icachansind = kept;
            EEG.etc = part.etc;
            testCase.verifyIca(EEG, 2, 'decision');
        end

        function aRerunFindsTheBlinkAlakazamRemoved(testCase)
        %ARERUNFINDSTHEBLINKALAKAZAMREMOVED  Four sources mixed into four
        %   channels, one of them blinks. Alakazam's decomposition (FastICA,
        %   as AutoEyeICA runs it) and the blink component removed; then the
        %   re-run: FieldTrip's own FastICA, the component matching the blink
        %   by topography removed. Not the same numbers, ICA being unseeded,
        %   but the same cleaned data to within a few percent, and no blink.
            testCase.assumeNotEmpty(which('fastica'), 'FastICA is not installed.');
            [EEG, blink] = testCase.blinking();
            [~, A, W] = TransTools.WithRestoredRng(@() fastica(double(EEG.data), 'displayMode', 'off', ...
                'verbose', 'off'));
            EEG.icaweights = W;
            EEG.icasphere = eye(size(W, 2));
            EEG.icawinv = A;
            EEG.icachansind = 1:size(EEG.data, 1);
            EEG.etc.alz.icaType = 'fastica';
            EEG.etc.ic_classification.ICLabel.classifications = repmat([0.9 0 0.1 0 0 0 0], size(W, 1), 1);
            [~, blinkComponent] = max(abs(correlation((W * double(EEG.data))', blink')));
            params = struct('components', blinkComponent);
            result = RemoveComponents(EEG, params);
            ctx = fieldtripStepContext('RemoveComponents', EEG, result);
            testCase.verifyEqual(ctx.decision.method, 'fastica');
            names = struct('in', 'data', 'out', 'data', 'trials', 'trials', 'step', 1, ...
                'binColumns', [], 'icaFile', 'probe_ica_1.mat', 'mode', 'rerun');
            step = fieldtripTransformCall('RemoveComponents', params, ctx, names);
            testCase.verifyEqual(step.status, 'approximate');
            here = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            writeExportSidecars(here, struct('name', names.icaFile, 'content', step.sidecar));
            fieldtrip = TransTools.WithRestoredRng(@() runEmitted(step.lines, asFieldTrip(EEG), 'data', [], here));
            cleaned = fieldtrip.trial{1};
            expected = double(result.data);
            testCase.verifyLessThan(rms(cleaned(:) - expected(:)) / rms(expected(:)), 0.05, ...
                'FieldTrip''s re-run cleans the data as Alakazam did, to within 5%.');
            leftover = max(abs(correlation(cleaned', blink')));
            testCase.verifyLessThan(leftover, 0.1, 'No channel still carries the blinks.');
        end

        function aDecompositionThatDoesNotSpanTheDataIsApproximate(testCase)
        %ADECOMPOSITIONTHATDOESNOTSPANTHEDATAISAPPROXIMATE  Three components
        %   for four independent channels: pop_subcomp also drops what lies
        %   outside them, which subtracting does not, and the export says so.
            EEG = testCase.decomposed(testCase.recording(), 3);
            result = RemoveComponents(EEG, struct('components', 2));
            ctx = fieldtripStepContext('RemoveComponents', EEG, result);
            testCase.verifyFalse(ctx.decision.exact);
            names = struct('in', 'data', 'out', 'data', 'trials', 'trials', 'step', 1, ...
                'binColumns', [], 'icaFile', 'probe_ica_1.mat');
            step = fieldtripTransformCall('RemoveComponents', struct('components', 2), ctx, names);
            testCase.verifyEqual(step.status, 'approximate');
        end

        function grandAveragesEqualAndWeighted(testCase)
        %GRANDAVERAGESEQUALANDWEIGHTED  Three recordings, each with its own
        %   data and its own trials rejected, through the emitted DefineBins,
        %   rejection and Average lines; then the emitted grand averages
        %   against Alakazam's GrandAverage, equal and weighted.
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            params = struct('script', sprintf(['epoch [-200,600] ms\nbin 1 "A" : "11"\n' ...
                'bin 2 "B" : "22"\nbin 3 "A - B" = bin 1 - bin 2']));
            dropped = {[], [1 2 3], 4};
            files = cell(1, 3);
            results = struct();
            subjects = struct('name', {}, 'rawFile', {}, 'steps', {}, 'contexts', {});
            for s = 1:3
                continuous = testCase.recording();
                continuous.data = continuous.data * s + 3 * s;
                EEG = DefineBins(continuous, params);
                flags = false(size(EEG.data, 1), size(EEG.data, 3));
                flags(:, dropped{s}) = true;
                rejected = ManualReject(EEG, struct('flags', flags, 'scope', 'Whole epoch', ...
                    'channelMode', 'Leave NaN'));
                averaged = Average(rejected, struct('Param', 'Init'));
                contexts = [fieldtripStepContext('DefineBins', continuous, EEG), ...
                    fieldtripStepContext('ManualReject', EEG, rejected), ...
                    fieldtripStepContext('Average', rejected, averaged)];
                files{s} = fullfile(folder, sprintf('s%d.mat', s));
                averaged.File = files{s};
                saveEegCache(files{s}, averaged);

                d = contexts(1).decision;
                n = numel(d.epochStart);
                trials = table((1:n)', d.epochStart, d.epochStart + d.pnts - 1, repmat(d.offset, n, 1), ...
                    double(d.membership(:, 1)), double(d.membership(:, 2)), ...
                    double(ismember((1:n)', contexts(2).decision.rejected)), 'VariableNames', ...
                    {'trial', 'begsample', 'endsample', 'offset', 'bin_1', 'bin_2', 'rejected_2'});
                names = @(k) struct('in', 'data', 'out', 'data', 'trials', 'trials', 'step', k, ...
                    'binColumns', [1 2], 'icaFile', '');
                data = runEmitted(fieldtripTransformCall('DefineBins', params, contexts(1), names(1)).lines, ...
                    asFieldTrip(continuous), 'data', trials);
                data = runEmitted(fieldtripTransformCall('ManualReject', struct(), contexts(2), names(2)).lines, ...
                    data, 'data', trials);
                averageNames = names(3);
                averageNames.out = 'erp';
                results.(sprintf('s%d', s)) = runEmitted(fieldtripTransformCall('Average', ...
                    struct('Param', 'Init'), contexts(3), averageNames).lines, data, 'erp', trials);
                subjects(s) = struct('name', sprintf('s%d', s), 'rawFile', 'none', 'steps', ...
                    struct('transformId', {'DefineBins', 'ManualReject', 'Average'}, ...
                        'params', {params, struct(), struct('Param', 'Init')}, 'parent', {-1, 1, 2}), ...
                    'contexts', contexts);
            end
            for weighted = [false true]
                code = exportFieldTripScript(subjects, struct('grandAverages', ...
                    struct('name', 'all', 'weighted', weighted, 'members', [1 3; 2 3; 3 3])));
                section = code(strfind(code, '%% Grand average: all'):end);
                helpers = regexp(section, '\n% =+ %', 'once');
                if ~isempty(helpers)
                    section = section(1:helpers);
                end
                grand = runGrand(section, results);
                alakazam = GrandAverage(files, weighted);
                for b = 1:3
                    testCase.verifyEqual(grand.all{b}.avg, double(alakazam.data(:, :, b)), 'AbsTol', 1e-10, ...
                        sprintf('Weighted %d, bin %d (%s).', weighted, b, alakazam.bindesc(b).label));
                end
            end
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
        function verifyIca(testCase, EEG, components, status)
        %VERIFYICA  RemoveComponents and the emitted FieldTrip lines, with the
        %   decomposition written beside them as the export writes it.
            params = struct('components', components);
            result = RemoveComponents(EEG, params);
            ctx = fieldtripStepContext('RemoveComponents', EEG, result);
            names = struct('in', 'data', 'out', 'data', 'trials', 'trials', 'step', 1, ...
                'binColumns', [], 'icaFile', 'probe_ica_1.mat');
            step = fieldtripTransformCall('RemoveComponents', params, ctx, names);
            testCase.assertEqual(step.status, status, step.summary);
            here = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            d = ctx.decision;
            writeExportSidecars(here, struct('name', names.icaFile, 'content', ...
                struct('unmixing', d.unmixing, 'topolabel', {d.topolabel}, 'removed', d.removed)));
            fieldtrip = runEmitted(step.lines, asFieldTrip(EEG), 'data', [], here);
            testCase.assertEqual(fieldtrip.label(:)', {result.chanlocs.labels}, 'The channels, in order.');
            expected = double(result.data);
            testCase.verifyEqual(fieldtrip.trial{1}, expected, 'AbsTol', 1e-9 * max(abs(expected(:))));
        end

        function [EEG, blink] = blinking(testCase)
        %BLINKING  The recording's channels replaced by four sources mixed:
        %   blinks (a large bump every few seconds) and three non-Gaussian
        %   noises, through a fixed mixing matrix.
            EEG = testCase.recording();
            stream = RandStream('mt19937ar', 'Seed', 3);
            n = size(EEG.data, 2);
            t = (0:n - 1) / EEG.srate;
            blink = zeros(1, n);
            for at = 1.3:2.7:t(end) - 1
                blink = blink + 80 * exp(-((t - at) / 0.08) .^ 2);
            end
            noise = [sign(randn(stream, 1, n)) .* -log(rand(stream, 1, n)); ...
                rand(stream, 1, n) - 0.5; sin(2 * pi * 10 * t) .* (1 + 0.3 * randn(stream, 1, n))] * 10;
            mixing = [1 0.3 0.2 0.1; 0.5 1 0.2 0.3; 0.2 0.4 1 0.2; 0.05 0.2 0.3 1];
            EEG.data = mixing * [blink; noise];
        end

        function EEG = decomposed(~, EEG, nComponents)
        %DECOMPOSED  EEG with a known decomposition of NCOMPONENTS: a fixed
        %   random rotation of its leading principal components, as ICA after
        %   PCA would leave it, and an ICLabel classification so that
        %   RemoveComponents classifies nothing itself.
            stream = RandStream('mt19937ar', 'Seed', 11);
            nChannels = size(EEG.data, 1);
            [u, ~, ~] = svd(double(EEG.data) * double(EEG.data)');
            rotation = orth(randn(stream, nComponents));
            unmixing = rotation * u(:, 1:nComponents)';
            % A sphere as ICA leaves one, not the identity, so that weights and
            % sphere must both be used: the unmixing matrix is their product.
            EEG.icasphere = diag(1:nChannels) * orth(randn(stream, nChannels));
            EEG.icaweights = unmixing / EEG.icasphere;
            EEG.icawinv = pinv(unmixing);
            EEG.icachansind = 1:size(EEG.data, 1);
            EEG.etc.ic_classification.ICLabel.classifications = repmat([0.9 0 0 0 0.1 0 0], nComponents, 1);
            EEG.etc.ic_classification.ICLabel.classes = {'Brain', 'Muscle', 'Eye', 'Heart', ...
                'Line Noise', 'Channel Noise', 'Other'};
        end

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

function out = runEmitted(lines, data, variable, trials, here) %#ok<INUSD> read by the lines
%RUNEMITTED  Evaluate an emitted step on DATA (and TRIALS, the table of
%   trials, and HERE, the folder its sidecar files are in), quietly, and
%   return the variable it assigns, with the script's helpers on the path.
    evalc(strjoin(lines, newline));
    out = eval(variable);
end

function grand = runGrand(section, results) %#ok<INUSD> read by the section
%RUNGRAND  Evaluate an emitted grand-average section on RESULTS, quietly.
    grand = struct();
    evalc(section);
end

function r = correlation(a, b)
%CORRELATION  Pearson correlation of each column of A with column vector B.
    a = a - mean(a, 1);
    b = b - mean(b, 1);
    r = (a' * b)' ./ (vecnorm(a) * norm(b));
end
