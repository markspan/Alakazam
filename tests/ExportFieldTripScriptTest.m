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
            testCase.verifySubstring(code, 'stem = ''sub_01'';');
            testCase.verifySubstring(code, 'readtable(fullfile(here, [stem ''_trials.tsv''])');
            rows = strsplit(strtrim(sidecars.content), newline);
            testCase.verifyEqual(strsplit(rows{1}, char(9)), ...
                {'trial', 'begsample', 'endsample', 'offset', 'bin_1', 'bin_2', 'rejected_4'});
            testCase.verifyEqual(str2double(strsplit(rows{2}, char(9))), [1 90 289 -10 1 0 0]);
            testCase.verifyEqual(str2double(strsplit(rows{3}, char(9))), [2 290 489 -10 0 1 1], ...
                'The second trial is in bin 2 and was rejected at step 4.');
        end

        function recordingsRunTheSameWayShareALoop(testCase)
        %RECORDINGSRUNTHESAMEWAYSHAREALOOP  Two recordings with the same
        %   steps are written once, as a loop; a third, run otherwise, has its
        %   own block. Each keeps its own rows, and its own numbers, in the
        %   header, and its own files.
            one = testCase.subject();
            two = one;
            two.name = 'sub 02';
            two.rawFile = 'C:\data\sub02.vhdr';
            two.contexts(4).decision.rejected = [];
            three = one;
            three.name = 'sub 03';
            three.steps(1).params.mode = 'Specific channels';
            three.steps(1).params.refChannels = {'Cz'};
            [code, sidecars] = exportFieldTripScript([one, two, three]);
            testCase.verifySubstring(code, '%% sub 01, sub 02 (run the same way)');
            testCase.verifySubstring(code, '''sub 02'', ''sub_02'', ''C:\data\sub02.vhdr''; ...');
            testCase.verifySubstring(code, '    [name, stem, rawFile] = recordings{r, :};');
            testCase.verifySubstring(code, '%% sub 03');
            testCase.verifySubstring(code, 'name = ''sub 03'';');
            testCase.verifyNumElements(strfind(code, 'for r = 1:size(recordings, 1)'), 1);
            testCase.verifySubstring(code, 'read from the trial table: 1 trials rejected');
            testCase.verifySubstring(code, 'read from the trial table: 0 trials rejected');
            testCase.verifyEqual({sidecars.name}, {'sub_01_trials.tsv', 'sub_02_trials.tsv', 'sub_03_trials.tsv'});
        end

        function theScriptFindsFieldTripItself(testCase)
        %THESCRIPTFINDSFIELDTRIPITSELF  Run on its own, in a session that has
        %   not got FieldTrip on the path, the script adds the folder FieldTrip
        %   was in when it was written, and says where to get it if that is
        %   gone; ft_defaults only after that.
            code = exportFieldTripScript(testCase.subject(), struct('fieldtripFolder', 'C:\tools\fieldtrip'));
            setup = extractBetween(code, 'here = fileparts', 'results = struct();');
            testCase.assertNotEmpty(setup);
            for expected = {'fieldtripFolder = ''C:\tools\fieldtrip'';', 'if isempty(which(''ft_defaults''))', ...
                    'addpath(fieldtripFolder);', 'https://www.fieldtriptoolbox.org/download/', 'ft_defaults;'}
                testCase.verifySubstring(setup{1}, expected{1});
            end
            testCase.verifyLessThan(strfind(code, 'addpath(fieldtripFolder);'), strfind(code, 'ft_defaults;'));
        end

        function theModeIsSaidInTheHeader(testCase)
            testCase.verifySubstring(exportFieldTripScript(testCase.subject()), '% Mode: REPRODUCE.');
            testCase.verifySubstring(exportFieldTripScript(testCase.subject(), struct('mode', 'rerun')), ...
                '% Mode: RE-RUN.');
            testCase.verifyError(@() exportFieldTripScript(testCase.subject(), struct('mode', 'guess')), ...
                'Alakazam:exportFieldTripScript');
        end

        function aRerunDecomposesInFieldTripAndMatchesByTopography(testCase)
        %ARERUNDECOMPOSESINFIELDTRIPANDMATCHESBYTOPOGRAPHY  In a re-run, an
        %   ICA step is FieldTrip's own extended Infomax (the algorithm
        %   recorded), with EEGLAB's learning rate, the same channels and as
        %   many components, and the components removed are matched by
        %   topography; in a reproduction, the decomposition is read back.
            s = testCase.icaSubject();
            [reproduce, reproduced] = exportFieldTripScript(s);
            [rerun, rerunFiles] = exportFieldTripScript(s, struct('mode', 'rerun'));
            testCase.verifySubstring(reproduce, 'cfg.unmixing = ica.unmixing;');
            testCase.verifySubstring(reproduce, 'RemoveComponents DECISION');
            testCase.verifyEqual(fieldnames(reproduced.content)', {'unmixing', 'topolabel', 'removed'});
            for expected = {'cfg.method = ''runica'';', 'cfg.channel = ica.topolabel;', ...
                    'cfg.numcomponent = 2;', 'cfg.runica.extended = 1;', ...
                    'cfg.runica.lrate = 0.00065 / log(numel(ica.topolabel));', ...
                    'remove = matchComponents(comp, ica.templates, ica.topolabel, 0.9);', ...
                    'function remove = matchComponents(', 'RemoveComponents APPROXIMATE'}
                testCase.verifySubstring(rerun, expected{1});
            end
            testCase.verifyEqual(rerunFiles.content.templates, [1; 2], ...
                'The removed component''s topography, its column of the mixing matrix.');
            reref = @(code) regexp(code, '% Step 1\. ReRef.*?\n\n', 'match', 'once');
            testCase.verifyEqual(reref(rerun), reref(reproduce), 'An exact step is the same in both.');
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
            [app, defined] = testCase.workspaceApp();

            [subjects, grandAverages] = collectCopy(app);

            testCase.assertNumElements(subjects, 1);
            testCase.verifyEqual(subjects.rawFile, 'C:\data\rec01.vhdr');
            testCase.verifyEqual({subjects.steps.transformId}, {'DefineBins', 'ManualReject', 'Average'});
            testCase.verifyEqual([subjects.steps.parent], [-1 1 2]);
            testCase.verifyEqual(subjects.contexts(1).decision.epochStart', defined.etc.alz.epochStart);
            testCase.verifyEqual(subjects.contexts(2).decision.rejected, [2 5]);
            testCase.verifyEqual({subjects.contexts(3).decision.bins.label}, {'A', 'B', 'A - B'});
            testCase.assertNumElements(grandAverages, 2);
            testCase.verifyEqual([grandAverages.weighted], [true false]);
            testCase.verifyEqual(grandAverages(1).members, [1 3; 1 3], ...
                'Its sources are the recording''s third step, matched by cache file.');
            testCase.verifyEqual(grandAverages(2).members, [1 3; NaN NaN]);
            [code, sidecars] = exportFieldTripScript(subjects, struct('grandAverages', grandAverages));
            testCase.verifySubstring(code, 'DefineBins      DECISION');
            testCase.verifySubstring(code, 'Grand average node1: EXACT');
            testCase.verifySubstring(code, ['Grand average node2: NOT TRANSLATED, a source average ' ...
                'is not among the recordings']);
            testCase.verifySubstring(sidecars.content, sprintf('rejected_2'));
        end

        function autoEyeIcaIsReadFromItsOwnRecord(testCase)
        %AUTOEYEICAISREADFROMITSOWNRECORD  The decomposition before pruning,
        %   on the channels the result's icachansind names (an EOG channel,
        %   unpositioned, left out), the components it removed, and why.
            input = struct('srate', 250, 'chanlocs', struct('labels', {'Fz', 'VEOG', 'Cz'}), ...
                'DataFormat', 'CONTINUOUS', 'data', [1 2 3 4; 9 9 9 9; 2 1 0 -1]);
            weights = [1 1; 1 -1];
            removed = 2;
            x = input.data([1 3], :);
            result = input;
            winv = inv(weights);
            result.data([1 3], :) = x - winv(:, removed) * (weights(removed, :) * x);
            result.icachansind = [1 3];
            result.etc.alz.eyeICA = struct('threshold', 0.8, 'removed', removed, ...
                'decomposition', struct('icaweights', weights, 'icasphere', eye(2), ...
                    'icawinv', winv, 'icachansind', [1 2]));
            ctx = fieldtripStepContext('AutoEyeICA', input, result);
            testCase.verifyEqual(ctx.decision.topolabel, {'Fz'; 'Cz'});
            testCase.verifyEqual(ctx.decision.removed, 2);
            testCase.verifyEqual(ctx.decision.unmixing, weights);
            testCase.verifyTrue(ctx.decision.exact);
            testCase.verifySubstring(ctx.decision.why, '0.8');
        end

        function aRemoveComponentsWithoutItsDecompositionIsRefused(testCase)
            EEG = struct('srate', 250, 'chanlocs', struct('labels', {'Fz', 'Cz'}), ...
                'DataFormat', 'CONTINUOUS', 'data', ones(2, 4));
            EEG.etc.alz.manualICA = struct('removed', 1, 'nRemoved', 1, 'nComponents', 2);
            testCase.verifyError(@() fieldtripStepContext('RemoveComponents', EEG, EEG), ...
                'Alakazam:exportFieldTripScript');
        end

        function theButtonWritesTheScriptAndItsFilesInEitherMode(testCase)
        %THEBUTTONWRITESTHESCRIPTANDITSFILESINEITHERMODE  The ribbon action
        %   itself, run on the workspace with its dialogs answered: the mode
        %   asked, the analysis collected, the script and its table of trials
        %   written where the save dialog said, and the message saying so.
            for mode = {'Reproduce Alakazam''s results', 'Re-run in FieldTrip'}
                [app, ~] = testCase.workspaceApp();
                out = testCase.standInDialogs(mode{1}, 'erp_analysis.m');
                copies = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(copies));
                MethodCopy.make(copies, '@Alakazam', 'onExportFieldTripScript', 'exportCopy');
                rehash;

                exportCopy(app);

                code = fileread(fullfile(out, 'erp_analysis.m'));
                if startsWith(mode{1}, 'Re-run')
                    testCase.verifySubstring(code, '% Mode: RE-RUN.');
                else
                    testCase.verifySubstring(code, '% Mode: REPRODUCE.');
                end
                testCase.verifyTrue(isfile(fullfile(out, 'node1_trials.tsv')), 'Its table of trials, beside it.');
                testCase.verifySubstring(fileread(fullfile(out, 'message.txt')), 'Wrote the analysis of 1 recording(s)');
                testCase.verifyEmpty(checkcode(fullfile(out, 'erp_analysis.m'), '-m2'), 'The script is valid MATLAB.');
            end
        end

        function aNameTheScriptCannotRunUnderIsRefused(testCase)
        %ANAMETHESCRIPTCANNOTRUNUNDERISREFUSED  Saved as erp.m, the script
        %   would assign a variable of its own name, which MATLAB will not run:
        %   the export says so and leaves nothing behind.
            [app, ~] = testCase.workspaceApp();
            out = testCase.standInDialogs('Reproduce Alakazam''s results', 'erp.m');
            copies = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(copies));
            MethodCopy.make(copies, '@Alakazam', 'onExportFieldTripScript', 'exportCopy');
            rehash;
            testCase.verifyError(@() exportCopy(app), 'standIn:warndlg');
            testCase.verifyEmpty(dir(fullfile(out, '*.m')), 'No script left behind.');
            testCase.verifyEmpty(dir(fullfile(out, '*.tsv')), 'Nor its table of trials.');
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
        function [app, defined] = workspaceApp(testCase)
        %WORKSPACEAPP  A workspace on disk, as the app writes one (a recording,
        %   then DefineBins, ManualReject and Average, each in its parent's
        %   folder, and two grand averages), and a FakeApp over it whose
        %   collectFieldTripSubjects, collectBranchTree and loadNodeEEG are the
        %   real methods (MethodCopy).
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
            averaged = testCase.saveStep(rejected.File, 'Average', Average(rejected, struct('Param', 'Init')), ...
                struct('Param', 'Init'));
            % Two grand averages as the Grand Averages tree keeps them, each with
            % its record of what it combined: this average twice, weighted;
            % and this average with one from outside the workspace.
            grandFiles = {fullfile(folder, 'grandA.mat'), fullfile(folder, 'grandB.mat')};
            sources = {{averaged.File, averaged.File}, {averaged.File, fullfile(folder, 'elsewhere.mat')}};
            for g = 1:2
                grand = averaged;
                grand.etc.GrandAverage = struct('sources', {sources{g}}, 'weighted', g == 1, 'nSubjects', 2);
                saveEegCache(grandFiles{g}, grand);
            end

            copies = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(copies));
            MethodCopy.make(copies, '@Alakazam', 'collectFieldTripSubjects', 'collectCopy');
            MethodCopy.make(copies, '@Alakazam', 'collectBranchTree', 'branchCopy');
            MethodCopy.make(copies, '@Alakazam', 'loadNodeEEG', 'loadCopy');
            rehash;
            app = FakeApp(struct('Workspace', struct('Tree', FakeTree({rootFile}), ...
                'GrandAveragesTree', FakeTree(grandFiles), 'ExportsDirectory', folder), 'MainFigure', []));
            app.addprop('collectBranchTree');
            app.addprop('loadNodeEEG');
            app.addprop('collectFieldTripSubjects');
            app.collectBranchTree = @(file) branchCopy(app, file);
            app.loadNodeEEG = @(file, action) loadCopy(app, file, action);
            app.collectFieldTripSubjects = @(varargin) collectCopy(app, varargin{:});
        end

        function out = standInDialogs(testCase, choice, fileName)
        %STANDINDIALOGS  The dialogs the export opens, answered without a
        %   screen: uiconfirm picks CHOICE, uiputfile names FILENAME in OUT,
        %   msgbox keeps what it was told in OUT/message.txt, warndlg raises it
        %   as an error (so a failure in the handler fails the test), and the
        %   busy indicator does nothing.
            out = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            stands = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            write = @(name, text) writeText(fullfile(stands, [name '.m']), text);
            write('uiconfirm', sprintf('function choice = uiconfirm(varargin)\nchoice = ''%s'';\nend\n', ...
                strrep(choice, '''', '''''')));
            write('uiputfile', sprintf(['function [name, folder] = uiputfile(varargin)\n' ...
                'name = ''%s'';\nfolder = ''%s'';\nend\n'], fileName, [out filesep]));
            write('msgbox', sprintf(['function msgbox(text, varargin)\nfid = fopen(''%s'', ''w'');\n' ...
                'fwrite(fid, text, ''char'');\nfclose(fid);\nend\n'], fullfile(out, 'message.txt')));
            write('warndlg', sprintf('function warndlg(text, varargin)\nerror(''standIn:warndlg'', ''%%s'', text);\nend\n'));
            write('beginBusy', sprintf(['function [restore, set] = beginBusy(varargin)\n' ...
                'restore = onCleanup(@() []);\nset = @(varargin) [];\nend\n']));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(stands));
            warning('off', 'MATLAB:dispatcher:nameConflict');
            rehash;
        end

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

        function s = icaSubject(~)
        %ICASUBJECT  A recording run through ReRef and RemoveComponents, its
        %   decomposition extended Infomax over two channels.
            labels = {'Fz', 'Cz'};
            ica = struct('unmixing', [1 0; 0 1], 'topolabel', {labels(:)}, 'removed', 2, ...
                'why', 'chosen by hand', 'exact', true, 'method', 'runica', 'templates', [1; 2]);
            s = struct('name', 'sub 01', 'rawFile', 'C:\data\sub01.vhdr');
            s.steps = struct('transformId', {'ReRef', 'RemoveComponents'}, 'params', ...
                {struct('mode', 'Average', 'refChannels', {{}}, 'exclude', {{}}, 'keepref', false, ...
                    'implicitRef', ''), struct('components', 2)}, 'parent', {-1, 1});
            s.contexts = struct('srate', 250, 'labels', {labels, labels}, 'format', 'CONTINUOUS', ...
                'decision', {[], ica});
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

% ======================================================================= %
function writeText(file, text)
    fid = fopen(file, 'w');
    fwrite(fid, text, 'char');
    fclose(fid);
end
