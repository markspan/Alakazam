classdef ExportFieldTripScriptTest < matlab.unittest.TestCase
%EXPORTFIELDTRIPSCRIPTTEST  The FieldTrip script export says, for every
%   step, how faithful it is, and writes what it reads back.
%
%   Text and bookkeeping only, without FieldTrip: whether the emitted lines
%   compute what Alakazam computed is FieldTripExportEquivalenceTest's
%   question, and whether a whole script does is FieldTripTutorialErpTest's.
%   Here: the header names every step with its status, a step FieldTrip
%   cannot do is marked and warned about rather than imitated, the table of
%   trials holds the decisions it should, a branch gets variables of its
%   own, and what cannot be carried is refused with a reason.
%
%   See also EXPORTFIELDTRIPSCRIPT, FIELDTRIPTRANSFORMCALL, FIELDTRIPSTEPCONTEXT.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'IO'), ...
                     fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Transformations', 'Filter'), ...
                     fullfile(root, 'src', 'Transformations', 'DefineBins'), ...
                     fullfile(root, 'src', 'Transformations', 'ManualReject'), ...
                     fullfile(root, 'src', 'Transformations', 'Average'), ...
                     fullfile(root, 'src', 'Support'), fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function theHeaderSaysHowFaithfulEachStepIs(testCase)
            code = exportFieldTripScript(testCase.subject());
            testCase.verifySubstring(code, 'ReRef           EXACT');
            testCase.verifySubstring(code, 'DefineBins      DECISION');
            testCase.verifySubstring(code, 'ManualReject    DECISION');
            testCase.verifySubstring(code, 'AutoGEDAI       NOT TRANSLATED');
            testCase.verifySubstring(code, 'Average         EXACT');
        end

        function aStepFieldTripCannotDoIsMarkedAndWarnedAbout(testCase)
            code = exportFieldTripScript(testCase.subject());
            testCase.verifySubstring(code, '% NOT TRANSLATED. FieldTrip has no counterpart for AutoGEDAI.');
            testCase.verifySubstring(code, 'warning(''Alakazam:fieldtripExport'', ''Skipped AutoGEDAI');
            testCase.verifySubstring(code, '%   struct(', 'Its options are recorded.');
        end

        function theTableHoldsTheTrialsTheirBinsAndTheRejections(testCase)
            [code, sidecars] = exportFieldTripScript(testCase.subject());
            testCase.assertNumElements(sidecars, 1);
            testCase.verifyEqual(sidecars.name, 'sub_01_trials.tsv');
            testCase.verifySubstring(code, 'readtable(fullfile(here, ''sub_01_trials.tsv'')');
            rows = strsplit(strtrim(sidecars.content), newline);
            testCase.verifyEqual(strsplit(rows{1}, char(9)), ...
                {'trial', 'begsample', 'endsample', 'offset', 'bin_1', 'bin_2', 'rejected_4'});
            testCase.verifyEqual(str2double(strsplit(rows{2}, char(9))), [1 90 289 -10 1 0 0]);
            testCase.verifyEqual(str2double(strsplit(rows{3}, char(9))), [2 290 489 -10 0 1 1], ...
                'The second trial is in bin 2 and was rejected at step 4.');
        end

        function aBranchGetsVariablesOfItsOwn(testCase)
            s = testCase.subject();
            s.steps(2).parent = -1;   % DefineBins now hangs off the recording, beside ReRef
            code = exportFieldTripScript(s);
            testCase.verifySubstring(code, 'data1 = ft_preprocessing(cfg, data);');
            testCase.verifySubstring(code, 'data2 = ft_redefinetrial(cfg, data);');
        end

        function aWeightedSumIsExactAndOtherArithmeticIsNot(testCase)
            ctx = struct('srate', 250, 'labels', {{'C3', 'C4'}}, 'format', 'EPOCHED', 'decision', []);
            names = struct('in', 'data', 'out', 'data', 'trials', 'trials', 'step', 1, 'binColumns', []);
            linear = fieldtripTransformCall('DeriveChannels', struct('derivations', 'let lrp = (C3 - C4) / 2'), ctx, names);
            testCase.verifyEqual(linear.status, 'exact');
            testCase.verifySubstring(strjoin(linear.lines, newline), ...
                'addChannel(data, ''lrp'', {''C3'', ''C4''}, [0.5, -0.5])');
            for text = {'let power = C3*C3', 'let size = abs(C3)', 'let shifted = C3 + 5'}
                step = fieldtripTransformCall('DeriveChannels', struct('derivations', text{1}), ctx, names);
                testCase.verifyEqual(step.status, 'none', text{1});
            end
        end

        function whatCannotBeCarriedIsRefusedWithItsReason(testCase)
            ctx = struct('srate', 250, 'labels', {{'C3', 'C4'}}, 'format', 'CONTINUOUS', 'decision', []);
            names = struct('in', 'data', 'out', 'data', 'trials', 'trials', 'step', 1, 'binColumns', []);
            excluded = fieldtripTransformCall('ReRef', struct('mode', 'Average', 'refChannels', {{}}, ...
                'exclude', {{'C4'}}, 'keepref', false, 'implicitRef', ''), ctx, names);
            testCase.verifyEqual(excluded.status, 'none');
            testCase.verifySubstring(excluded.summary, 'exclude');
            timed = fieldtripTransformCall('SelectData', struct('channels', struct('mode', '(off)'), ...
                'time', struct('mode', 'Keep', 'range', [0 1]), 'points', struct('mode', '(off)'), ...
                'trials', struct('mode', '(off)', 'indices', [])), ctx, names);
            testCase.verifyEqual(timed.status, 'none');
        end

        function aRejectionThatTouchedChannelsIsApproximate(testCase)
            before = struct('srate', 250, 'chanlocs', struct('labels', {'C3', 'C4'}), ...
                'DataFormat', 'EPOCHED', 'data', ones(2, 5, 3));
            after = before;
            after.data(:, :, 2) = NaN;          % trial 2 rejected whole
            after.data(1, :, 3) = NaN;          % and C3 in trial 3
            ctx = fieldtripStepContext('ManualReject', before, after);
            testCase.verifyEqual(ctx.decision.rejected, 2);
            testCase.verifyTrue(ctx.decision.partial);
            names = struct('in', 'data', 'out', 'data', 'trials', 'trials', 'step', 3, 'binColumns', []);
            step = fieldtripTransformCall('ManualReject', struct(), ctx, names);
            testCase.verifyEqual(step.status, 'approximate');

            interpolated = before;
            interpolated.data(2, :, 1) = 2;     % a channel rebuilt in trial 1
            ctx = fieldtripStepContext('ManualReject', before, interpolated);
            testCase.verifyEmpty(ctx.decision.rejected);
            testCase.verifyTrue(ctx.decision.partial, 'An interpolated channel is a change too.');
        end

        function theAppCollectsEachStepWithWhatItDecided(testCase)
        %THEAPPCOLLECTSEACHSTEPWITHWHATITDECIDED  A workspace on disk, as the
        %   app writes one (a recording, then DefineBins, ManualReject and
        %   Average, each in its parent's folder), read by the real
        %   collectFieldTripSubjects, collectBranchTree and loadNodeEEG.
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            raw = testCase.recording();
            raw.etc = struct('alz', struct('rawFile', 'C:\data\rec01.vhdr'));
            rootFile = fullfile(folder, 'rec01.mat');
            saveEegCache(rootFile, raw);
            binParams = struct('script', sprintf(['epoch [-40,40] ms\nbin 1 "A" : "11"\n' ...
                'bin 2 "B" : "22"\nbin 3 "A - B" = bin 1 - bin 2']));
            defined = testCase.saveStep(rootFile, 'DefineBins', DefineBins(raw, binParams), binParams);
            flags = false(2, 6);
            flags(:, [2 5]) = true;
            rejectParams = struct('flags', flags, 'scope', 'Whole epoch', 'channelMode', 'Leave NaN');
            rejected = testCase.saveStep(defined.File, 'ManualReject', ...
                ManualReject(defined, rejectParams), rejectParams);
            testCase.saveStep(rejected.File, 'Average', Average(rejected, struct('Param', 'Init')), ...
                struct('Param', 'Init'));

            copies = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(copies));
            MethodCopy.make(copies, '@Alakazam', 'collectFieldTripSubjects', 'collectCopy');
            MethodCopy.make(copies, '@Alakazam', 'collectBranchTree', 'branchCopy');
            MethodCopy.make(copies, '@Alakazam', 'loadNodeEEG', 'loadCopy');
            rehash;
            app = FakeApp(struct('Workspace', struct('Tree', FakeTree({rootFile})), 'MainFigure', []));
            app.addprop('collectBranchTree');
            app.addprop('loadNodeEEG');
            app.collectBranchTree = @(file) branchCopy(app, file);
            app.loadNodeEEG = @(file, action) loadCopy(app, file, action);

            subjects = collectCopy(app);

            testCase.assertNumElements(subjects, 1);
            testCase.verifyEqual(subjects.rawFile, 'C:\data\rec01.vhdr');
            testCase.verifyEqual({subjects.steps.transformId}, {'DefineBins', 'ManualReject', 'Average'});
            testCase.verifyEqual([subjects.steps.parent], [-1 1 2]);
            testCase.verifyEqual(subjects.contexts(1).decision.epochStart', defined.etc.alz.epochStart);
            testCase.verifyEqual(subjects.contexts(2).decision.rejected, [2 5]);
            testCase.verifyEqual({subjects.contexts(3).decision.bins.label}, {'A', 'B', 'A - B'});
            [code, sidecars] = exportFieldTripScript(subjects);
            testCase.verifySubstring(code, 'DefineBins      DECISION');
            testCase.verifySubstring(sidecars.content, sprintf('rejected_2'));
        end

        function aDefineBinsMadeBeforeItRecordedItsTrialsIsRefused(testCase)
            result = struct('srate', 250, 'DataFormat', 'EPOCHED', 'data', zeros(2, 10, 3), ...
                'times', -40:4:-4, 'etc', struct('alz', struct()), ...
                'chanlocs', struct('labels', {'C3', 'C4'}));
            testCase.verifyError(@() fieldtripStepContext('DefineBins', result, result), ...
                'Alakazam:exportFieldTripScript');
        end
    end

    methods (Access = private)
        function EEG = recording(~)
        %RECORDING  Two channels, 500 samples at 250 Hz, with events 11 and 22
        %   alternating every 70 samples: six trials, three per bin.
            EEG = struct('srate', 250, 'nbchan', 2, 'pnts', 500, 'trials', 1, ...
                'data', repmat(1:500, 2, 1) + [0; 1000], 'times', (0:499) / 250, ...
                'chanlocs', struct('labels', {'Fz', 'Cz'}), 'DataFormat', 'CONTINUOUS', ...
                'DataType', 'TIMEDOMAIN', 'xmin', 0, 'xmax', 499 / 250);
            latency = 60:70:410;
            EEG.event = struct('type', repmat({'11', '22'}, 1, 3), 'latency', num2cell(latency));
        end

        function EEG = saveStep(~, parentFile, transformId, EEG, params)
        %SAVESTEP  A step's result where persistResultNode puts it: in a
        %   folder named after its parent, with its transformation and options.
            [folder, stem] = fileparts(parentFile);
            childDir = fullfile(folder, stem);
            if ~isfolder(childDir)
                mkdir(childDir);
            end
            EEG.File = fullfile(childDir, [transformId '00000001.mat']);
            EEG.Call = transformId;
            EEG.id = transformId;
            EEG.params = params;
            saveEegCache(EEG.File, EEG);
        end

        function s = subject(~)
        %SUBJECT  A recording run through ReRef, DefineBins (two trials, one
        %   per bin), AutoGEDAI, ManualReject (the second trial) and Average.
            labels = {'Fz', 'Cz'};
            ctx = @(format, decision) struct('srate', 250, 'labels', {labels}, ...
                'format', format, 'decision', decision);
            defined = struct('epochStart', [90; 290], 'pnts', 200, 'offset', -10, ...
                'bins', struct('index', {1, 2}, 'label', {'A', 'B'}), ...
                'membership', logical([1 0; 0 1]));
            bins = struct('index', {1, 2, 3}, 'label', {'A', 'B', 'A - B'}, ...
                'coeff', {[], [], [1 -1]}, 'combines', {[], [], [1 2]});
            s = struct('name', 'sub 01', 'rawFile', 'C:\data\sub01.vhdr');
            s.steps = struct('transformId', {'ReRef', 'DefineBins', 'AutoGEDAI', 'ManualReject', 'Average'}, ...
                'params', {struct('mode', 'Average', 'refChannels', {{}}, 'exclude', {{}}, ...
                    'keepref', false, 'implicitRef', ''), ...
                    struct('script', sprintf('bin 1 "A" : "11"\nbin 2 "B" : "22"\nbin 3 "A - B" = bin 1 - bin 2')), ...
                    struct('Strength', 'auto'), struct(), struct('Param', 'Init')}, ...
                'parent', {-1, 1, 2, 3, 4});
            s.contexts = [ctx('CONTINUOUS', []), ctx('CONTINUOUS', defined), ctx('EPOCHED', []), ...
                ctx('EPOCHED', struct('rejected', 2, 'partial', false)), ...
                ctx('EPOCHED', struct('bins', bins))];
        end
    end
end
