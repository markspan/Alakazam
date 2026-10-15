classdef AnalysisBranchesTest < matlab.unittest.TestCase
%ANALYSISBRANCHESTEST  Alternative analyses of one recording: how each is
%   named (analysisBranches), when a report asks which to use
%   (chooseAnalysisBranches), and how a grand average's inputs are labelled
%   (findGrandAverageCandidates).
%
%   Every subject's average is called "Average", so two analyses of one
%   recording were two identical rows in the Grand Average dialog, and a
%   report took both as if they were more measurements of the same thing.
%   The naming is tested on chains of steps alone; the question and the
%   labels run the real methods (MethodCopy) on a small tree of real cache
%   files (LinkedTree).
%
%   Run with: runtests('tests/AnalysisBranchesTest.m').
%
%   See also ANALYSISBRANCHES, DATASETBRANCHES, ALAKAZAM.CHOOSEANALYSISBRANCHES.

    properties
        Folder
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (TestMethodSetup)
        function copyTheMethods(testCase)
            testCase.Folder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testCase.Folder));
            MethodCopy.make(testCase.Folder, '@Alakazam', 'chooseAnalysisBranches', 'chooseCopy');
            MethodCopy.make(testCase.Folder, '@Alakazam', 'findGrandAverageCandidates', 'candidatesCopy');
            rehash;
        end
    end

    methods (Test)
        % ---- the names ----------------------------------------------------
        function oneWayHasNoName(testCase)
            [branch, names] = analysisBranches({chain('Filter', 'Average'), ...
                chain('Filter', 'Average')}, {'S01', 'S02'});
            testCase.verifyEqual(branch, [1 1]);
            testCase.verifyEqual(names, {''});
        end

        function anExtraStepNamesBothWays(testCase)
            ica = chain('Filter', 'AutoICA', 'DefineBins', 'Average');
            plain = chain('Filter', 'DefineBins', 'Average');
            [branch, names] = analysisBranches({ica, plain, ica, plain}, {'S01', 'S01', 'S02', 'S02'});
            testCase.verifyEqual(branch, [1 2 1 2], 'Each way is one branch across recordings.');
            testCase.verifyEqual(names, {'AutoICA', 'without AutoICA'});
        end

        function aSettingThatSplitsARecordingNamesTheStep(testCase)
            at30 = chain({'Filter', struct('lowpass', struct('enabled', true, 'freq', 30))}, 'Average');
            at40 = chain({'Filter', struct('lowpass', struct('enabled', true, 'freq', 40))}, 'Average');
            [branch, names] = analysisBranches({at30, at40, at30, at40}, {'S01', 'S01', 'S02', 'S02'});
            testCase.verifyEqual(branch, [1 2 1 2]);
            testCase.verifyEqual(names, {'Filter (lowpass.freq 30)', 'Filter (lowpass.freq 40)'});
        end

        function settingsThatDifferOnlyBetweenRecordingsAreNotAnotherAnalysis(testCase)
            first = chain({'AutoICA', struct('removed', [1 2])}, 'Average');
            second = chain({'AutoICA', struct('removed', 3)}, 'Average');
            [branch, names] = analysisBranches({first, second}, {'S01', 'S02'});
            testCase.verifyEqual(branch, [1 1], ...
                'The components ICA removed differ by subject, which is not another analysis.');
            testCase.verifyEqual(names, {''});
        end

        function theSameStepsInAnotherOrderAreNamedByTheirChain(testCase)
            [~, names] = analysisBranches({chain('Filter', 'Resample', 'Average'), ...
                chain('Resample', 'Filter', 'Average')}, {'S01', 'S01'});
            testCase.verifyEqual(names, {'Filter / Resample / Average', 'Resample / Filter / Average'});
        end

        function aLongDifferenceIsShortened(testCase)
            [~, names] = analysisBranches({chain('Filter', 'Average'), ...
                chain('Filter', 'ReRef', 'AutoICA', 'Interpolate', 'ArtefactDetect', 'Average')}, ...
                {'S01', 'S01'});
            testCase.verifyEqual(names{2}, ['ReRef / ' char(8230) ' / ArtefactDetect']);
            testCase.verifyEqual(names{1}, 'without ReRef, AutoICA, Interpolate, ArtefactDetect');
        end

        % ---- the question -------------------------------------------------
        function oneAnalysisIsNotAskedAbout(testCase)
            [app, files] = testCase.workspace({'S01', 'S02'}, {{'Filter', 'Average'}});
            [keep, cancelled] = chooseCopy(app, files, 'average', ...
                @(varargin) testCase.verifyFail('Nothing is due to be asked.'));
            testCase.verifyEqual(keep, true(1, 2));
            testCase.verifyFalse(cancelled);
        end

        function twoAnalysesOfARecordingAreAskedAbout(testCase)
            [app, files] = testCase.workspace({'S01', 'S02'}, ...
                {{'Filter', 'AutoICA', 'Average'}, {'Filter', 'Average'}});
            asked = {};
            [keep, cancelled] = chooseCopy(app, files, 'average', @ask);
            testCase.verifyEqual(asked, {'AutoICA  (2 recordings)', 'without AutoICA  (2 recordings)'});
            testCase.verifyFalse(cancelled);
            testCase.verifyEqual(keep, [false true false true], 'Only the analysis chosen is kept.');

            function chosen = ask(items, description)
                asked = items;
                testCase.verifySubstring(description, 'more than one average');
                chosen = items(2);
            end
        end

        function cancellingMakesNoReport(testCase)
            [app, files] = testCase.workspace({'S01'}, ...
                {{'Filter', 'AutoICA', 'Average'}, {'Filter', 'Average'}});
            [keep, cancelled] = chooseCopy(app, files, 'average', @(varargin) []);
            testCase.verifyTrue(cancelled);
            testCase.verifyEqual(keep, false(1, 2));
        end

        function aRecordingProcessedDifferentlyIsNotAQuestion(testCase)
        %ARECORDINGPROCESSEDDIFFERENTLYISNOTAQUESTION  One subject needed
        %   Interpolate and the other not: the ways differ, but no recording
        %   has two of them to choose from.
            tree = LinkedTree();
            files = {testCase.subject(tree, 'S01', {'Filter', 'Average'}), ...
                     testCase.subject(tree, 'S02', {'Filter', 'Interpolate', 'Average'})};
            app = FakeApp(struct('Workspace', struct('Tree', tree)));
            [keep, cancelled] = chooseCopy(app, files, 'average', ...
                @(varargin) testCase.verifyFail('Nothing is due to be asked.'));
            testCase.verifyEqual(keep, true(1, 2));
            testCase.verifyFalse(cancelled);
        end

        % ---- the grand average's inputs -----------------------------------
        function grandAverageInputsCarryTheirAnalysis(testCase)
            [app, files] = testCase.workspace({'S01', 'S02'}, ...
                {{'Filter', 'AutoICA', 'Average'}, {'Filter', 'Average'}});
            [found, labels, kinds, ~, branches] = candidatesCopy(app);
            [~, order] = ismember(files, found);
            testCase.assertTrue(all(order > 0), 'Every average is a candidate.');
            testCase.verifyEqual(kinds(order), repmat({'ERP'}, 1, 4));
            testCase.verifyEqual(branches(order), {'AutoICA', 'without AutoICA', 'AutoICA', 'without AutoICA'});
            testCase.verifyEqual(labels{order(1)}, 'S01: Average [AutoICA] (Faces, Cars)');
            testCase.verifyEqual(labels{order(4)}, 'S02: Average [without AutoICA] (Faces, Cars)');
        end

        function oneAnalysisKeepsTheLabelItHad(testCase)
            app = testCase.workspace({'S01', 'S02'}, {{'Filter', 'Average'}});
            [~, labels, ~, ~, branches] = candidatesCopy(app);
            testCase.verifyEqual(sort(labels), {'S01: Average (Faces, Cars)', 'S02: Average (Faces, Cars)'});
            testCase.verifyEqual(branches, {'', ''});
        end
    end

    methods (Test, TestTags = {'Slow'})
        function theGrandAverageDialogOffersEachAnalysis(testCase)
        %THEGRANDAVERAGEDIALOGOFFERSEACHANALYSIS  The dialog is modal, so a
        %   timer finds its Analysis row, chooses one analysis, reads the
        %   subjects that selects, picks one subject by hand, and cancels.
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'src', 'Dialogs')));
            try
                probe = uifigure('Visible', 'off');
                delete(probe);
            catch err
                testCase.assumeFail(['A uifigure could not be created here: ' err.message]);
            end
            files = {'s01-ica', 's01-plain', 's02-ica', 's02-plain'};
            labels = {'S01: Average [AutoICA] (A)', 'S01: Average [without AutoICA] (A)', ...
                      'S02: Average [AutoICA] (A)', 'S02: Average [without AutoICA] (A)'};
            branches = {'AutoICA', 'without AutoICA', 'AutoICA', 'without AutoICA'};
            seen = struct('visible', '', 'items', {{}}, 'selected', {{}}, 'byHand', '');
            timerObj = timer('ExecutionMode', 'fixedSpacing', 'Period', 1, ...
                'TasksToExecute', 60, 'TimerFcn', @(src, ~) drive(src));
            cleanup = onCleanup(@() delete(timerObj));
            start(timerObj);
            spec = GrandAverageDialog(files, labels, repmat({'ERP'}, 1, 4), [], branches);
            clear cleanup;

            testCase.verifyEmpty(spec, 'Cancelled.');
            testCase.verifyEqual(seen.visible, 'on', 'Two analyses: the row is shown.');
            testCase.verifyEqual(seen.items, {'Choose subjects by hand', 'AutoICA', 'without AutoICA'});
            testCase.verifyEqual(sort(seen.selected), {'s01-plain', 's02-plain'}, ...
                'Choosing an analysis selects every subject analysed that way.');
            testCase.verifyEqual(seen.byHand, 'Choose subjects by hand', ...
                'A selection that is not one analysis is by hand.');

            function drive(src)
                f = findall(groot, 'Type', 'figure', 'Name', 'Grand Average');
                if isempty(f)
                    return;
                end
                drop = findall(f(1), 'Tag', 'gaBranch');
                list = findall(f(1), 'Tag', 'gaSubjects');
                if isempty(drop) || isempty(list) || numel(list.Items) < 4
                    return;
                end
                stop(src);
                seen.visible = char(string(drop.Parent.Visible));
                seen.items = drop.Items;
                drop.Value = 'without AutoICA';
                drop.ValueChangedFcn(drop, []);
                seen.selected = list.Value;
                list.Value = {'s01-ica'};
                list.ValueChangedFcn(list, []);
                seen.byHand = drop.Value;
                cancel = findall(f(1), 'Type', 'uibutton', 'Text', 'Cancel');
                cancel(1).ButtonPushedFcn(cancel(1), []);
            end
        end
    end

    methods (Access = private)
        function [app, files] = workspace(testCase, subjects, ways)
        %WORKSPACE  A fake app whose tree has, for each subject, one branch
        %   per way (a list of step names, the last an average), and the
        %   averages' files, subject by subject and way by way.
            tree = LinkedTree();
            files = {};
            for s = 1:numel(subjects)
                raw = testCase.cacheFile(subjects{s}, 'Raw', 'CONTINUOUS');
                root = tree.add(subjects{s}, '', raw);
                for w = 1:numel(ways)
                    files{end + 1} = testCase.branch(tree, root, sprintf('%s_%d', subjects{s}, w), ways{w}); %#ok<AGROW>
                end
            end
            app = FakeApp(struct('Workspace', struct('Tree', tree, 'includedFor', @(~) true)));
        end

        function file = subject(testCase, tree, name, steps)
        %SUBJECT  One recording with one branch; the average's file.
            root = tree.add(name, '', testCase.cacheFile(name, 'Raw', 'CONTINUOUS'));
            file = testCase.branch(tree, root, name, steps);
        end

        function file = branch(testCase, tree, parent, stem, steps)
            for k = 1:numel(steps)
                format = 'CONTINUOUS';
                if k == numel(steps)
                    format = 'Averaged';
                end
                file = testCase.cacheFile(sprintf('%s_%d_%s', stem, k, steps{k}), steps{k}, format);
                parent = tree.add(steps{k}, parent, file);
            end
        end

        function file = cacheFile(testCase, stem, call, format)
        %CACHEFILE  A cache file as a step leaves it: its call, settings,
        %   format and, for an average, two bins.
            EEG = struct('id', call, 'Call', call, 'params', struct('step', call), ...
                'DataFormat', format, 'DataType', 'TimeDomain', 'data', zeros(2, 4));
            if strcmp(format, 'Averaged')
                EEG.bindesc = struct('label', {'Faces', 'Cars'});
            end
            file = fullfile(testCase.Folder, [stem '.mat']);
            save(file, 'EEG');
        end
    end
end

function c = chain(varargin)
%CHAIN  Steps by name, each its own transformation; {name, params} gives
%   one settings.
    c = struct('label', {}, 'call', {}, 'params', {});
    for k = 1:nargin
        step = varargin{k};
        params = struct();
        if iscell(step)
            params = step{2};
            step = step{1};
        end
        c(end + 1) = struct('label', step, 'call', step, 'params', params); %#ok<AGROW>
    end
end
