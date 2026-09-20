classdef ClearWorkspaceCacheTest < matlab.unittest.TestCase
%CLEARWORKSPACECACHETEST  What "Clear WorkSpace" removes in its normal and
%   deep modes (src/Support/clearWorkspaceCache.m), and the argument checks
%   of the chooser that asks which one (src/Support/chooseAction.m).
%
%   The fixture is a small real cache on disk. Recordings A and B belong to
%   the workspace; recording C sits in the same cache but belongs to another
%   workspace. Each recording has its own cache file <id>.mat, its sidecar,
%   and a folder <id>/ holding an analysis node (with a nested one below it).
%   Three grand averages sit in GrandAverages: one built only from A and B,
%   one from A and C, and one with no provenance at all.
%
%   What matters, and what each test pins:
%     - a NORMAL clear keeps the recordings' own .mat files and sidecars,
%       because they hold no analysis and are slow to recreate
%     - a DEEP clean removes those too
%     - neither ever touches another workspace's data
%
%   Run with: runtests('tests/ClearWorkspaceCacheTest.m').
%
%   See also CLEARWORKSPACECACHE, CHOOSEACTION, WORKSPACE/RAWCLEAR.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Support')));
        end
    end

    methods (Test)
        function normalKeepsTheRecordingsButRemovesTheirAnalyses(testCase)
            [cache, nodes] = testCase.buildCache();

            clearWorkspaceCache(nodes, cache, 'normal');

            for id = {'A', 'B'}
                testCase.verifyTrue(isfile(fullfile(cache, [id{1} '.mat'])), ...
                    sprintf('%s.mat is the recording as loaded and a normal clear keeps it.', id{1}));
                testCase.verifyTrue(isfile(fullfile(cache, [id{1} '.mat.json'])), ...
                    sprintf('%s.mat.json describes the kept recording.', id{1}));
                testCase.verifyTrue(isfile(fullfile(cache, [id{1} '.mat.meta'])), ...
                    sprintf('%s.mat.meta belongs to the kept recording.', id{1}));
                testCase.verifyFalse(isfolder(fullfile(cache, id{1})), ...
                    sprintf('The analyses folder %s/ should be gone.', id{1}));
            end
        end

        function deepRemovesTheRecordingsAsWell(testCase)
            [cache, nodes] = testCase.buildCache();

            clearWorkspaceCache(nodes, cache, 'deep');

            for id = {'A', 'B'}
                testCase.verifyFalse(isfile(fullfile(cache, [id{1} '.mat'])));
                testCase.verifyFalse(isfile(fullfile(cache, [id{1} '.mat.json'])), ...
                    'The sidecar must go with its .mat, not be left describing nothing.');
                testCase.verifyFalse(isfile(fullfile(cache, [id{1} '.mat.meta'])), ...
                    'So must the meta record.');
                testCase.verifyFalse(isfolder(fullfile(cache, id{1})));
            end
        end

        function anotherWorkspacesRecordingIsLeftAloneInEitherMode(testCase)
            for mode = {'normal', 'deep'}
                [cache, nodes] = testCase.buildCache();

                clearWorkspaceCache(nodes, cache, mode{1});

                testCase.verifyTrue(isfile(fullfile(cache, 'C.mat')), ...
                    sprintf('C belongs to another workspace and survives a %s clear.', mode{1}));
                testCase.verifyTrue(isfile(fullfile(cache, 'C.mat.json')));
                testCase.verifyTrue(isfile(fullfile(cache, 'C', 'n1.mat')));
                testCase.verifyTrue(isfile(fullfile(cache, 'C', 'n1', 'n2.mat')));
            end
        end

        function grandAveragesGoOnlyWhenEverySourceIsOurs(testCase)
            for mode = {'normal', 'deep'}
                [cache, nodes] = testCase.buildCache();

                clearWorkspaceCache(nodes, cache, mode{1});

                ga = fullfile(cache, 'GrandAverages');
                testCase.verifyFalse(isfile(fullfile(ga, 'ga_own.mat')), ...
                    sprintf('Built only from A and B, so a %s clear removes it.', mode{1}));
                testCase.verifyFalse(isfile(fullfile(ga, 'ga_own.mat.json')));
                testCase.verifyFalse(isfile(fullfile(ga, 'ga_own.mat.meta')));
                testCase.verifyTrue(isfile(fullfile(ga, 'ga_mixed.mat')), ...
                    'Partly built from C, which is somebody else''s: kept.');
                testCase.verifyTrue(isfile(fullfile(ga, 'ga_bare.mat')), ...
                    'No provenance means it is not claimed: kept.');
            end
        end

        function aDryRunReportsWithoutDeleting(testCase)
            [cache, nodes] = testCase.buildCache();

            normal = clearWorkspaceCache(nodes, cache, 'normal', true);
            deep = clearWorkspaceCache(nodes, cache, 'deep', true);

            testCase.verifyTrue(isfile(fullfile(cache, 'A.mat')));
            testCase.verifyTrue(isfolder(fullfile(cache, 'A')));
            testCase.verifyFalse(any(strcmp(normal, fullfile(cache, 'A.mat'))), ...
                'A normal clear must not list the recording''s own file.');
            testCase.verifyTrue(any(strcmp(deep, fullfile(cache, 'A.mat'))), ...
                'A deep clean must list it.');
            testCase.verifyTrue(all(ismember(normal, deep)), ...
                'Everything a normal clear removes, a deep clean removes too.');
            testCase.verifyGreaterThan(numel(deep), numel(normal));
        end

        function nothingIsFabricatedForARecordingWithNoAnalyses(testCase)
        %   A recording that was loaded but never analysed has no <id>/
        %   folder. That is not an error, and nothing is reported for it.
            [cache, nodes] = testCase.buildCache();
            rmdir(fullfile(cache, 'B'), 's');

            targets = clearWorkspaceCache(nodes, cache, 'normal', true);

            testCase.verifyFalse(any(strcmp(targets, fullfile(cache, 'B'))));
            testCase.verifyTrue(isfile(fullfile(cache, 'B.mat')));
        end

        function anEmptyTreeIsNotAnError(testCase)
            [cache, ~] = testCase.buildCache();
            targets = clearWorkspaceCache([], cache, 'deep');
            testCase.verifyEmpty(targets);
            testCase.verifyTrue(isfile(fullfile(cache, 'A.mat')), 'No nodes, so nothing is ours to delete.');
        end

        function aPathOutsideTheCacheIsNeverDeleted(testCase)
        %   The paths come from tree node data. One that claims to be a
        %   recording but lives outside the cache is refused, with a
        %   warning, in both modes, and everything belonging to it stays.
            [cache, nodes] = testCase.buildCache();
            outside = fullfile(fileparts(cache), 'Elsewhere');
            mkdir(fullfile(outside, 'X'));
            touch(fullfile(outside, 'X.mat'));
            touch(fullfile(outside, 'X.mat.json'));
            touch(fullfile(outside, 'X', 'n1.mat'));
            nodes(end + 1) = struct('Id', 'x', 'Name', 'X', ...
                'UserData', fullfile(outside, 'X.mat'), 'IsRoot', true);

            testCase.verifyWarning(@() clearWorkspaceCache(nodes, cache, 'deep'), ...
                'Alakazam:clearWorkspaceCache');

            testCase.verifyTrue(isfile(fullfile(outside, 'X.mat')));
            testCase.verifyTrue(isfile(fullfile(outside, 'X.mat.json')));
            testCase.verifyTrue(isfile(fullfile(outside, 'X', 'n1.mat')));
        end

        function anUnknownModeIsRefused(testCase)
            [cache, nodes] = testCase.buildCache();
            testCase.verifyError(@() clearWorkspaceCache(nodes, cache, 'thorough'), ...
                'Alakazam:clearWorkspaceCache');
            testCase.verifyTrue(isfile(fullfile(cache, 'A.mat')), 'A refused mode must delete nothing.');
        end

        function theChooserRefusesADefaultOrCancelItDoesNotOffer(testCase)
        %   Checked before any dialog is shown, so this needs no display.
            testCase.verifyError(@() chooseAction([], 'm', 't', {'a', 'b'}, 'x', 'b'), ...
                'Alakazam:chooseAction');
            testCase.verifyError(@() chooseAction([], 'm', 't', {'a', 'b'}, 'a', 'x'), ...
                'Alakazam:chooseAction');
        end

        function theClassicDialogFallbackOffersNoMoreThanThreeButtons(testCase)
        %   questdlg takes three at most; a fourth would be dropped without
        %   a word, so it is an error instead. With no uifigure the fallback
        %   is the path taken, and the check comes before the dialog.
            testCase.verifyError( ...
                @() chooseAction([], 'm', 't', {'a', 'b', 'c', 'd'}, 'a', 'd'), ...
                'Alakazam:chooseAction');
        end
    end

    methods (Access = private)
        function [cache, nodes] = buildCache(testCase)
        %BUILDCACHE  The fixture described in the class header.
            folder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture()).Folder;
            cache = fullfile(folder, 'Cache');
            mkdir(fullfile(cache, 'GrandAverages'));

            for id = {'A', 'B', 'C'}
                touch(fullfile(cache, [id{1} '.mat']));
                touch(fullfile(cache, [id{1} '.mat.json']));
                touch(fullfile(cache, [id{1} '.mat.meta']));
                mkdir(fullfile(cache, id{1}, 'n1'));
                touch(fullfile(cache, id{1}, 'n1.mat'));
                touch(fullfile(cache, id{1}, 'n1.mat.json'));
                touch(fullfile(cache, id{1}, 'n1', 'n2.mat'));
            end

            ga = fullfile(cache, 'GrandAverages');
            writeGrandAverage(fullfile(ga, 'ga_own.mat'), ...
                {fullfile(cache, 'A', 'n1.mat'), fullfile(cache, 'B.mat')});
            touch(fullfile(ga, 'ga_own.mat.json'));
            touch(fullfile(ga, 'ga_own.mat.meta'));
            writeGrandAverage(fullfile(ga, 'ga_mixed.mat'), ...
                {fullfile(cache, 'A.mat'), fullfile(cache, 'C.mat')});
            EEG = struct('data', 1);
            save(fullfile(ga, 'ga_bare.mat'), 'EEG');

            nodes = repmat(struct('Id', '', 'Name', '', 'UserData', '', 'IsRoot', false), 1, 0);
            for id = {'A', 'B'}
                nodes(end + 1) = struct('Id', id{1}, 'Name', id{1}, ...
                    'UserData', fullfile(cache, [id{1} '.mat']), 'IsRoot', true); %#ok<AGROW>
                nodes(end + 1) = struct('Id', [id{1} '1'], 'Name', 'n1', ...
                    'UserData', fullfile(cache, id{1}, 'n1.mat'), 'IsRoot', false); %#ok<AGROW>
            end
        end
    end
end

function touch(file)
%TOUCH  Create FILE with a byte in it.
    fid = fopen(file, 'w');
    fwrite(fid, 'x');
    fclose(fid);
end

function writeGrandAverage(file, sources)
%WRITEGRANDAVERAGE  A grand average file recording which cache files it combined.
    EEG = struct('etc', struct('GrandAverage', struct('sources', {sources})));
    save(file, 'EEG');
end
