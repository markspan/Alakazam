classdef BranchReplayTest < matlab.unittest.TestCase
%BRANCHREPLAYTEST  Replaying, recalculating and scanning a branch of cache nodes
%   without reading nodes back that are already in memory, and without loading
%   whole nodes to read two small fields from each.
%
%   Applying a branch to another recording saved every step's result and then
%   loaded the very same file for the next step, and loaded every step of the
%   SOURCE branch in full to read its transformation and settings: about 1.7 GB
%   per target on the RIFT chain, for values that fit in a kilobyte.
%
%   These tests run the real methods (see MethodCopy) against a fake app, on a
%   branch whose saved .mat files have been overwritten with garbage: anything
%   that still loads one fails, and only the .meta records (see eegCacheMeta)
%   let the replay succeed. The steps' results are checked, too, so "no read"
%   cannot be reached by computing nothing.
%
%   Run with: runtests('tests/BranchReplayTest.m').
%
%   See also METHODCOPY, FAKEAPP, EEGCACHEMETA.

    properties
        Folder
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Transformations'), fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (TestMethodSetup)
        function makeFolder(testCase)
            testCase.Folder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testCase.Folder));
            % A transformation that records what it was given, so a replay's
            % lineage and arithmetic can be read back from its result.
            write(fullfile(testCase.Folder, 'AlzTestStep.m'), [ ...
                'function [EEG, options] = AlzTestStep(input, params)' newline ...
                '    EEG = input;' newline ...
                '    EEG.data = input.data + params.add;' newline ...
                '    EEG.trail = [input.trail, {params.tag}];' newline ...
                '    options = params;' newline ...
                'end' newline]);
        end
    end

    methods (Test)
        function aForkIsReplayedFromMemoryAndFromTheSourceRecords(testCase)
        %AFORKISREPLAYEDFROMMEMORYANDFROMTHESOURCERECORDS  Steps a, then b and c
        %   (a fork) on a target. Each persisted result is deleted the moment it
        %   is saved, so a step that read its parent back from disk would fail; the
        %   source .mat files are garbage, so a step that loaded one would fail too.
            source = testCase.sourceBranch();
            app = testCase.makeApp(true);
            target = testCase.targetNode(1000);

            evalRecurse(app, source.step1, target);

            saved = app.Persisted;
            testCase.assertEqual(size(saved, 1), 3, 'Three steps: a, then b and c.');
            testCase.verifyEqual(saved{1, 1}.trail, {'a'});
            testCase.verifyEqual(saved{2, 1}.trail, {'a', 'b'});
            testCase.verifyEqual(saved{3, 1}.trail, {'a', 'c'});
            testCase.verifyEqual(saved{1, 1}.data, 1000 * ones(2, 4) + 1);
            testCase.verifyEqual(saved{2, 1}.data, 1000 * ones(2, 4) + 11);
            testCase.verifyEqual(saved{3, 1}.data, 1000 * ones(2, 4) + 101);
        end

        function aTargetHeldInMemoryNeedsNoFileButATopLevelOneDoes(testCase)
            source = testCase.sourceBranch();
            app = testCase.makeApp(false);
            missing = struct('Id', 'x', 'Name', 'x', 'IsRoot', true, ...
                'UserData', fullfile(testCase.Folder, 'not_there.mat'));
            held = testCase.dataset(5);

            evalRecurse(app, source.step1, missing, held);
            testCase.verifyEqual(size(app.Persisted, 1), 3);

            testCase.verifyError(@() evalRecurse(app, source.step1, missing), ...
                'Alakazam:evaluateDroppedBranch');
        end

        function anAveragedSourceOnAMatchingAveragedTargetIsOverlaid(testCase)
        %ANAVERAGEDSOURCEONAMATCHINGAVERAGEDTARGETISOVERLAID  The one case that does
        %   load the source, because the overlay needs its waveforms.
            file = fullfile(testCase.Folder, 'avg.mat');
            saveEegCache(file, testCase.averaged('Average', 7));
            app = testCase.makeApp(false);
            target = testCase.targetNode(0);
            target.UserData = fullfile(testCase.Folder, 'avgtarget.mat');
            saveEegCache(target.UserData, testCase.averaged('Average', 3));

            evalRecurse(app, file, target);

            testCase.verifyEqual(app.Overlaid, 1);
            testCase.verifyEqual(app.OverlaidData, 7 * ones(2, 3), ...
                'The overlay must receive the source''s own waveforms.');
            testCase.verifyEmpty(app.Persisted, 'An overlay creates no node.');
        end

        function anAveragedSourceThatIsNotAFreshAverageIsReplayedNotOverlaid(testCase)
            file = fullfile(testCase.Folder, 'avg.mat');
            saveEegCache(file, testCase.averaged('AlzTestStep', 7));
            app = testCase.makeApp(false);
            target = testCase.targetNode(0);
            target.UserData = fullfile(testCase.Folder, 'avgtarget.mat');
            saveEegCache(target.UserData, testCase.averaged('Average', 3));

            evalRecurse(app, file, target);

            testCase.verifyEqual(app.Overlaid, 0);
            testCase.verifyEqual(size(app.Persisted, 1), 1);
            testCase.verifyEqual(app.Persisted{1, 1}.data, 3 * ones(2, 3), ...
                'The step (adding 0) was applied to the target''s own data.');
        end

        function aTemplateStepTakesItsParentFromMemory(testCase)
            app = testCase.makeApp(true);
            missing = struct('Id', 'x', 'Name', 'x', 'IsRoot', true, ...
                'UserData', fullfile(testCase.Folder, 'not_there.mat'));

            testCase.copyMethod('applyStepToTarget', 'stepCopy');
            [node, result] = stepCopy(app, 'AlzTestStep', struct('add', 2, 'tag', 'z'), ...
                missing, testCase.dataset(10));

            testCase.verifyEqual(result.data, 12 * ones(2, 4));
            testCase.verifyEqual(result.trail, {'z'});
            testCase.verifyEqual(node.UserData, app.Persisted{1, 2}.UserData);
        end

        function aBranchIsCollectedFromItsRecordsAlone(testCase)
            source = testCase.sourceBranch();

            testCase.copyMethod('collectBranchTree', 'treeCopy');
            nodes = treeCopy([], source.step1);

            testCase.verifyEqual({nodes.transformId}, {'AlzTestStep', 'AlzTestStep', 'AlzTestStep'});
            testCase.verifyEqual([nodes.parent], [-1 1 1]);
            testCase.verifyEqual({nodes.params}, {struct('add', 1, 'tag', 'a'), ...
                struct('add', 10, 'tag', 'b'), struct('add', 100, 'tag', 'c')});
        end

        function aRecalculationReadsEachDescendantsSettingsFromItsRecord(testCase)
            source = testCase.sourceBranch();
            app = FakeApp(struct());
            app.addprop('planDescendantRecalc');
            testCase.copyMethod('planDescendantRecalc', 'planCopy');
            app.planDescendantRecalc = @(file, eeg) planCopy(app, file, eeg);

            plan = planCopy(app, source.step1, testCase.dataset(0));

            testCase.assertEqual(numel(plan), 2);
            testCase.verifyEqual(plan(1).EEG.trail, {'b'});
            testCase.verifyEqual(plan(2).EEG.trail, {'c'});
            testCase.verifyEqual(plan(1).EEG.data, 10 * ones(2, 4));
            testCase.verifyEqual(plan(1).EEG.Call, 'AlzTestStep');
            testCase.verifyEqual(plan(1).EEG.id, 'AlzTestStep');
            testCase.verifyTrue(endsWith(plan(1).file, 'step2.mat'));
        end

        function binLabelsAndEpochRangesComeFromTheSidecarsNotTheNodes(testCase)
            files = {fullfile(testCase.Folder, 'a.mat'), fullfile(testCase.Folder, 'b.mat')};
            a = testCase.dataset(1);
            a.bindesc = struct('label', {'Std', 'Dev'});
            a.times = linspace(-200, 800, 10);
            b = testCase.dataset(1);
            b.bindesc = struct('label', {'Dev', 'Odd'});
            b.times = linspace(-100, 600, 10);
            for k = 1:2
                eegs = {a, b};
                saveEegCache(files{k}, eegs{k});
                testCase.garble(files{k}, eegs{k});
            end

            testCase.copyMethod('candidateBinLabels', 'binsCopy');
            testCase.copyMethod('candidateEpochMs', 'epochCopy');

            testCase.verifyEqual(binsCopy([], files), {'Dev'; 'Odd'; 'Std'});
            testCase.verifyEqual(epochCopy([], files), [-100 600], ...
                'The epoch every candidate shares is the narrower of the two.');
        end

        function grandAveragesAreListedFromTheirRecordsAndOthersAreLeftOut(testCase)
            cache = fullfile(testCase.Folder, 'cache');
            mkdir(fullfile(cache, 'GrandAverages'));
            owned = fullfile(cache, 'subject1.mat');
            ours = fullfile(cache, 'GrandAverages', 'ours.mat');
            theirs = fullfile(cache, 'GrandAverages', 'theirs.mat');
            testCase.grandAverageNode(ours, 'Ours', {owned});
            testCase.grandAverageNode(theirs, 'Theirs', {fullfile(cache, 'elsewhere.mat')});

            grandTree = FakeTree();
            app = FakeApp(struct('CacheDirectory', cache, 'Tree', FakeTree({owned}), ...
                'GrandAveragesTree', grandTree));
            testCase.copyMethod('loadGrandAverages', 'gaCopy', '@WorkSpace');

            gaCopy(app);

            testCase.assertEqual(size(grandTree.Added, 1), 1, ...
                'Only the grand average built from this workspace''s recordings is listed.');
            testCase.verifyEqual(grandTree.Added{1, 1}, 'Ours');
            testCase.verifyEqual(grandTree.Added{1, 4}, ours);
            testCase.verifyTrue(grandTree.Added{1, 5}.canRecalculate);
        end

        function reportsAreListedByTheirLabelsFromTheirRecords(testCase)
            reports = fullfile(testCase.Folder, 'reports');
            mkdir(reports);
            file = fullfile(reports, 'r1_node.mat');
            EEG = struct('id', 'Report', 'Label', 'Report (spectral) - 20-Sep', ...
                'DataFormat', 'EPOCHED', 'DataType', 'REPORT');
            saveEegCache(file, EEG);
            testCase.garble(file, EEG);

            tree = FakeTree();
            app = FakeApp(struct('ReportsTree', tree, 'reportsDirectory', @() reports));
            testCase.copyMethod('loadReports', 'reportsCopy', '@WorkSpace');

            reportsCopy(app);

            testCase.assertEqual(size(tree.Added, 1), 1);
            testCase.verifyEqual(tree.Added{1, 1}, 'Report (spectral) - 20-Sep');
        end

        function aGrandAverageIsRefreshedWhenAnyOfItsSourcesWasRecalculated(testCase)
            ga = fullfile(testCase.Folder, 'ga.mat');
            testCase.grandAverageNode(ga, 'GA', {'src1.mat', 'src2.mat'});
            app = FakeApp(struct( ...
                'Workspace', struct('GrandAveragesTree', FakeTree({ga})), ...
                'closeTab', @(~) [], 'SavedSpec', []));
            app.addprop('saveGrandAverage');
            app.saveGrandAverage = @(spec, ~) setSpec(app, spec);
            testCase.copyMethod('recalculateAffectedGrandAverages', 'gaRefresh');

            gaRefresh(app, {'src2.mat'});

            testCase.assertNotEmpty(app.SavedSpec, 'A source was recalculated, so the grand average is rebuilt.');
            testCase.verifyEqual(app.SavedSpec.name, 'GA');
            testCase.verifyEqual(app.SavedSpec.sources, {'src1.mat', 'src2.mat'});
            testCase.verifyFalse(app.SavedSpec.weighted);

            app.SavedSpec = [];
            gaRefresh(app, {'unrelated.mat'});
            testCase.verifyEmpty(app.SavedSpec, 'No source was touched, so nothing is rebuilt.');
        end
    end

    methods (Access = private)
        function copyMethod(testCase, method, newName, classFolder)
            if nargin < 4
                classFolder = '@Alakazam';
            end
            MethodCopy.make(testCase.Folder, classFolder, method, newName);
            rehash;
        end

        function source = sourceBranch(testCase)
        %SOURCEBRANCH  step1 with children step2 and step2b, on disk, each .mat
        %   replaced by garbage after its records were written.
            root = fullfile(testCase.Folder, 'src');
            mkdir(fullfile(root, 'step1'));
            source.step1 = fullfile(root, 'step1.mat');
            children = {fullfile(root, 'step1', 'step2.mat'), fullfile(root, 'step1', 'step2b.mat')};
            specs = {source.step1, 1, 'a'; children{1}, 10, 'b'; children{2}, 100, 'c'};
            for k = 1:size(specs, 1)
                EEG = testCase.dataset(0);
                EEG.Call = 'AlzTestStep';
                EEG.id = 'AlzTestStep';
                EEG.params = struct('add', specs{k, 2}, 'tag', specs{k, 3});
                saveEegCache(specs{k, 1}, EEG);
                testCase.garble(specs{k, 1}, EEG);
            end
        end

        function garble(~, file, EEG)
        %GARBLE  Replace the node with bytes that cannot be loaded, then rewrite its
        %   record so it is at least as new as the node: only the record is usable.
            fid = fopen(file, 'w');
            fwrite(fid, 'not a MAT file');
            fclose(fid);
            writeCacheSidecar(file, eegCacheInfo(EEG));
            writeCacheMeta(file, eegCacheMeta(EEG));
        end

        function EEG = dataset(~, level)
            EEG = struct('data', level * ones(2, 4), 'trail', {{}}, 'DataFormat', 'EPOCHED', ...
                'times', 1:4, 'etc', struct());
        end

        function EEG = averaged(testCase, call, level)
            EEG = testCase.dataset(0);
            EEG.data = level * ones(2, 3);
            EEG.DataFormat = 'Averaged';
            EEG.Call = call;
            EEG.id = call;
            EEG.params = struct('add', 0, 'tag', 't');
        end

        function node = targetNode(testCase, level)
            file = fullfile(testCase.Folder, 'target.mat');
            EEG = testCase.dataset(level);
            EEG.File = file;
            saveEegCache(file, EEG);
            node = struct('Id', 't', 'Name', 'target', 'UserData', file, 'IsRoot', true);
        end

        function grandAverageNode(testCase, file, name, sources)
            mkdir(fileparts(file));
            EEG = testCase.averaged('Average', 1);
            EEG.id = name;
            EEG.etc.GrandAverage = struct('sources', {sources}, 'weighted', false, ...
                'nSubjects', numel(sources), 'kind', 'erp');
            saveEegCache(file, EEG);
            testCase.garble(file, EEG);
        end

        function app = makeApp(testCase, deleteAfterSave)
        %APP  A fake Alakazam whose persistResultNode saves like the real one, keeps
        %   what it was given, and (when DELETEAFTERSAVE) removes the file at once.
            app = FakeApp(struct('Persisted', {cell(0, 2)}, 'Overlaid', 0, ...
                'OverlaidData', [], 'Counter', 0));
            app.addprop('persistResultNode');
            app.addprop('isOverlayableAverage');
            app.addprop('overlayAverage');
            app.addprop('evaluateDroppedBranch');
            testCase.copyMethod('isOverlayableAverage', 'overlapCopy');
            testCase.copyMethod('evaluateDroppedBranch', 'evalRecurse');

            app.persistResultNode = @(eeg, sourceFile, ~, transformId, parent) ...
                persistFake(app, deleteAfterSave, eeg, sourceFile, transformId, parent);
            app.isOverlayableAverage = @(target, source) overlapCopy(app, target, source);
            app.overlayAverage = @(target, source) overlayFake(app, source);
            app.evaluateDroppedBranch = @(varargin) evalRecurse(app, varargin{:});
        end
    end
end

% ======================================================================= %
function [resultEEG, node] = persistFake(app, deleteAfterSave, resultEEG, sourceFile, transformId, ~)
%PERSISTFAKE  What persistResultNode does to the disk, without a tree: a child
%   folder named after the source, a timestamp-style file name, and the two
%   records. Optionally removes the node again, to prove nothing reads it back.
    app.Counter = app.Counter + 1;
    [parentDir, parentName] = fileparts(sourceFile);
    childDir = fullfile(parentDir, parentName);
    if ~exist(childDir, 'dir')
        mkdir(childDir);
    end
    resultEEG.File = fullfile(childDir, sprintf('%s%08d.mat', transformId, app.Counter));
    resultEEG.id = transformId;
    saveEegCache(resultEEG.File, resultEEG);
    node = struct('Id', sprintf('p%d', app.Counter), 'Name', transformId, ...
        'UserData', resultEEG.File, 'IsRoot', false);
    app.Persisted(end + 1, :) = {resultEEG, node};
    if deleteAfterSave
        delete(resultEEG.File);
    end
end

function setSpec(app, spec)
    app.SavedSpec = spec;
end

function overlayFake(app, source)
    app.Overlaid = app.Overlaid + 1;
    app.OverlaidData = source.data;
end

function write(file, text)
    fid = fopen(file, 'w');
    fwrite(fid, text);
    fclose(fid);
end
