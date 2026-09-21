classdef ReplayBranchTest < matlab.unittest.TestCase
%REPLAYBRANCHTEST  Apply to All Raw Files, as a replay that can run on
%   parallel workers.
%
%   Apply to All Raw Files used to replay a branch through the app, one
%   recording after another (evaluateDroppedBranch). It now replays through
%   replayBranch, which only reads and writes cache files, so
%   replayBranchOnTargets can give each recording to a worker; the app adds
%   the nodes as each one finishes (addReplayedNodes). These cases check
%   that the replay writes what the branch did, keeps a partial branch when
%   a step fails, never overwrites a result, is the same on a worker as in
%   the app, and that the number of workers follows the settings, the cores
%   and the free memory.
%
%   The branch here is DCDetrend followed by Rectify on a small synthetic
%   recording: two real transformations, fast, and needing no EEGLAB.
%
%   Run with: runtests('tests/ReplayBranchTest.m').
%
%   See also REPLAYBRANCH, REPLAYBRANCHONTARGETS, APPLYTOALLWORKERS.

    properties
        Folder
        TransRoot
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.TransRoot = fullfile(root, 'src', 'Transformations');
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Dialogs'), testCase.TransRoot, ...
                     fullfile(testCase.TransRoot, 'DCDetrend'), fullfile(testCase.TransRoot, 'Rectify'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (TestMethodSetup)
        function makeFolder(testCase)
            testCase.Folder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture()).Folder;
        end
    end

    methods (Test)
        function theReplayWritesWhatTheBranchDid(testCase)
            [branch, target] = testCase.branchAndTarget();

            [nodes, message] = replayBranch(branch, target, testCase.TransRoot);

            testCase.assertEqual(message, '');
            testCase.assertNumElements(nodes, 2);
            testCase.verifyEqual({nodes.Label}, {'DCDetrend', 'Rectify'});
            testCase.verifyEqual(nodes(1).ParentFile, target);
            testCase.verifyEqual(nodes(2).ParentFile, nodes(1).File, ...
                'Rectify ran on the detrended result, so it hangs under it.');
            [~, targetStem] = fileparts(target);
            testCase.verifyTrue(startsWith(nodes(1).File, fullfile(testCase.Folder, targetStem)), ...
                'Results go in the folder named after the target, where the tree looks for them.');

            want = Rectify(DCDetrend(testCase.recording(2), testCase.detrendOpts()), testCase.rectifyOpts());
            got = load(nodes(2).File, 'EEG');
            testCase.verifyEqual(got.EEG.data, want.data, 'AbsTol', 1e-12);
            testCase.verifyEqual(char(got.EEG.Call), 'Rectify');
            testCase.verifyEqual(got.EEG.File, nodes(2).File);
            testCase.verifyTrue(isfield(nodes(1).Opts, 'canListEvents'), ...
                'The tree options come with the node, so the app need not load the result.');
        end

        function aFailedStepKeepsWhatWasWrittenBeforeIt(testCase)
        %AFAILEDSTEPKEEPSWHATWASWRITTENBEFOREIT  As the one-at-a-time replay
        %   does: the steps before the failure stay, and the failure is
        %   reported rather than thrown, so one recording cannot stop a batch.
            [branch, target] = testCase.branchAndTarget();
            [branchDir, branchStem] = fileparts(branch);
            broken = testCase.recording(9);
            broken.Call = 'NoSuchTransformation';
            broken.params = struct();
            saveEegCache(fullfile(branchDir, branchStem, 'NoSuchTransformation01000000.mat'), broken);

            [nodes, message] = replayBranch(branch, target, testCase.TransRoot);

            testCase.verifySubstring(message, 'NoSuchTransformation');
            testCase.verifyGreaterThanOrEqual(numel(nodes), 1);
            testCase.verifyEqual(nodes(1).Label, 'DCDetrend');
            testCase.verifyTrue(isfile(nodes(1).File));
        end

        function aMissingTargetIsReportedNotThrown(testCase)
            [branch, ~] = testCase.branchAndTarget();

            [nodes, message] = replayBranch(branch, fullfile(testCase.Folder, 'gone.mat'), testCase.TransRoot);

            testCase.verifyEmpty(nodes);
            testCase.verifySubstring(message, 'could not be found');
        end

        function aResultIsNeverOverwritten(testCase)
        %ARESULTISNEVEROVERWRITTEN  Two runs of one transformation on one
        %   parent within a second used to get the same file name, and the
        %   second silently replaced the first.
            parent = fullfile(testCase.Folder, 'parent.mat');
            first = resultCacheFile(parent, 'Rectify');
            save(first, 'parent');
            second = resultCacheFile(parent, 'Rectify');

            testCase.verifyNotEqual(second, first);
            [folder, stem] = fileparts(first);
            testCase.verifyEqual(folder, fullfile(testCase.Folder, 'parent'));
            testCase.verifyTrue(startsWith(stem, 'Rectify'));
        end

        function theAppAddsEachNodeUnderItsParent(testCase)
            [branch, target] = testCase.branchAndTarget();
            nodes = replayBranch(branch, target, testCase.TransRoot);
            tree = FakeTree();
            targetNode = struct('Id', 'root7', 'UserData', target, 'Name', 'Target', 'IsRoot', true);

            addReplayedNodes(tree, nodes, targetNode, true);

            testCase.assertSize(tree.Added, [2 5]);
            testCase.verifyEqual(tree.Added{1, 2}, 'root7');
            testCase.verifyEqual(tree.Added{2, 2}, 'a1', 'Rectify goes under the node DCDetrend made.');
            testCase.verifyEqual(tree.Added{2, 4}, nodes(2).File);
            testCase.verifyTrue(tree.Added{2, 5}.canApplyToAll);
        end

        function oneAtATimeReportsEachRecordingInTurn(testCase)
            [branch, targets] = testCase.branchAndTargets(3);
            order = [];
            startedOrder = [];

            [results, width] = replayBranchOnTargets(branch, targets, testCase.TransRoot, 1, ...
                @(k, ~) recordDone(k), @(k) recordStart(k));

            testCase.verifyEqual(width, 1);
            testCase.verifyEqual(order, 1:3);
            testCase.verifyEqual(startedOrder, 1:3);
            testCase.verifyEqual({results.error}, {'', '', ''});
            testCase.verifyEqual(arrayfun(@(r) numel(r.nodes), results), [2 2 2]);

            function recordDone(k)
                order(end + 1) = k;
            end
            function recordStart(k)
                startedOrder(end + 1) = k;
            end
        end

        function theWorkerCountFollowsSettingsCoresAndMemory(testCase)
            files = {'a.mat', 'b.mat', 'c.mat', 'd.mat', 'e.mat', 'f.mat', 'g.mat', 'h.mat', 'i.mat'};
            gb = 1e9;
            base = {'Parallel', true, 'MaxWorkers', 0, 'HaveToolbox', true, 'Cores', 8, ...
                'FileBytes', repmat(0.6 * gb, 1, 9)};

            count = @(varargin) applyToAllWorkers(files, base{:}, varargin{:});
            testCase.verifyEqual(count('AvailableBytes', 13 * gb), 3, ...
                '13 GB free, 0.6 GB recordings: 3.3 GB a worker leaves room for three.');
            testCase.verifyEqual(count('AvailableBytes', 64 * gb), 8, 'With memory to spare, the cores decide.');
            testCase.verifyEqual(count('AvailableBytes', 64 * gb, 'MaxWorkers', 2), 2, 'The Settings maximum wins.');
            testCase.verifyEqual(count('AvailableBytes', 3 * gb), 1, 'Too little memory: one at a time.');
            testCase.verifyEqual(count('AvailableBytes', NaN), 2, 'Unknown free memory: a cautious two.');
            testCase.verifyEqual(count('AvailableBytes', 64 * gb, 'Parallel', false), 1);
            testCase.verifyEqual(count('AvailableBytes', 64 * gb, 'HaveToolbox', false), 1);
            testCase.verifyEqual(applyToAllWorkers(files(1), base{:}, 'AvailableBytes', 64 * gb, ...
                'FileBytes', 0.6 * gb), 1, 'One recording has nothing to share.');
        end
    end

    methods (Test, TestTags = {'Slow'})
        function aWorkerWritesWhatTheAppWould(testCase)
        %AWORKERWRITESWHATTHEAPPWOULD  The same branch on the same recordings,
        %   on two workers and here, gives the same data. Starts a pool of two
        %   when none is running (and stops it again), so it is slow.
            testCase.assumeTrue(license('test', 'Distrib_Computing_Toolbox') && ~isempty(ver('parallel')), ...
                'The Parallel Computing Toolbox is not available.');
            if isempty(gcp('nocreate'))
                parpool('Processes', 2);
                testCase.addTeardown(@() delete(gcp('nocreate')));
            end
            [branch, targets] = testCase.branchAndTargets(3);

            [onWorkers, width] = replayBranchOnTargets(branch, targets, testCase.TransRoot, 2);
            here = replayBranchOnTargets(branch, targets, testCase.TransRoot, 1);

            testCase.verifyEqual(width, 2);
            for k = 1:3
                testCase.assertEqual(onWorkers(k).error, '');
                a = load(onWorkers(k).nodes(2).File, 'EEG');
                b = load(here(k).nodes(2).File, 'EEG');
                testCase.verifyEqual(a.EEG.data, b.EEG.data);
                testCase.verifyNotEqual(onWorkers(k).nodes(2).File, here(k).nodes(2).File, ...
                    'Two replays onto one recording are two branches, not one overwritten.');
            end
        end
    end

    methods (Access = private)
        function EEG = recording(~, seed)
            EEG = makeTestEEG('nbchan', 3, 'labels', {'Fz', 'Pz', 'Oz'}, 'trials', 1, 'DataFormat', 'CONTINUOUS');
            EEG.data = EEG.data + seed * (1:size(EEG.data, 2)) / 100 - 5;   % a drift to remove
        end

        function o = detrendOpts(~)
            o = struct('Channels', {{}}, 'Order', '1 - linear', 'Method', 'Least squares', ...
                'FitStart', 0, 'FitStop', 0);
        end

        function o = rectifyOpts(~)
            o = struct('Channels', {{'Fz', 'Pz', 'Oz'}}, 'Mode', 'Full wave (|x|)');   % empty would rectify nothing
        end

        function [branchFile, targetFiles] = branchAndTargets(testCase, n)
        %BRANCHANDTARGETS  A source recording with a DCDetrend > Rectify branch
        %   cached under it, and N other recordings to replay it onto.
            source = fullfile(testCase.Folder, 'source.mat');
            saveEegCache(source, testCase.recording(1));
            detrended = DCDetrend(testCase.recording(1), testCase.detrendOpts());
            detrended.Call = 'DCDetrend';
            detrended.params = testCase.detrendOpts();
            detrended.id = 'DCDetrend';
            branchFile = resultCacheFile(source, 'DCDetrend');
            saveEegCache(branchFile, detrended);
            rectified = Rectify(detrended, testCase.rectifyOpts());
            rectified.Call = 'Rectify';
            rectified.params = testCase.rectifyOpts();
            rectified.id = 'Rectify';
            saveEegCache(resultCacheFile(branchFile, 'Rectify'), rectified);

            targetFiles = cell(1, n);
            for k = 1:n
                targetFiles{k} = fullfile(testCase.Folder, sprintf('target%d.mat', k));
                saveEegCache(targetFiles{k}, testCase.recording(k + 1));
            end
        end

        function [branchFile, targetFile] = branchAndTarget(testCase)
            [branchFile, targets] = testCase.branchAndTargets(1);
            targetFile = targets{1};
        end
    end
end
