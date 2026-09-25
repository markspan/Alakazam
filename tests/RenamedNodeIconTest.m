classdef RenamedNodeIconTest < matlab.unittest.TestCase
%RENAMEDNODEICONTEST  A renamed node keeps its transformation's icon.
%
%   THE REPORTED BUG: rename a node, restart, and its icon became the
%   generic one. A rename writes the new name into EEG.id, and the tree
%   rebuilt from disk looked the icon up by EEG.id, which then named no
%   transformation. The transformation is EEG.Call, which a rename leaves
%   alone, so the icon is looked up there first. These cases run against
%   WorkSpaceTree.iconForResult with the same stand-in a restart builds
%   (id, Call, DataType, see eegProxyFromCacheInfo) and a throwaway
%   Transformations folder.
%
%   Run with: runtests('tests/RenamedNodeIconTest.m').
%
%   See also WORKSPACETREE, ALAKAZAM/ONRENAMENODE, WORKSPACE/TREETRAVERSE.

    properties
        Root    % a Transformations folder holding one transformation, "Smooth"
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'src')));
        end
    end

    methods (TestMethodSetup)
        function makeTransformations(testCase)
            testCase.Root = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            folder = fullfile(testCase.Root, 'Smooth');
            mkdir(folder);
            fid = fopen(fullfile(folder, 'Smooth.json'), 'w');
            fwrite(fid, '{"Icon": "Smooth.png"}');
            fclose(fid);
            imwrite(uint8(255 * rand(6, 6, 3)), fullfile(folder, 'Smooth.png'));
        end
    end

    methods (Test)
        function aRenamedNodeKeepsItsTransformationsIcon(testCase)
            original = WorkSpaceTree.iconForResult(RenamedNodeIconTest.node('Smooth', 'Smooth'), testCase.Root);
            renamed = WorkSpaceTree.iconForResult(RenamedNodeIconTest.node('Smoothed, second try', 'Smooth'), testCase.Root);

            testCase.verifyTrue(startsWith(original, 'data:image/png;base64,'));
            testCase.verifyEqual(renamed, original, 'The rename changed the icon.');
        end

        function aNameThatIsAnotherTransformationDoesNotBorrowItsIcon(testCase)
        %ANAMETHATISANOTHERTRANSFORMATIONDOESNOTBORROWITSICON  Renaming a
        %   node to the name of some other transformation must not give it
        %   that one's icon: Call is asked first.
            folder = fullfile(testCase.Root, 'Other');
            mkdir(folder);
            fid = fopen(fullfile(folder, 'Other.json'), 'w');
            fwrite(fid, '{"Icon": "Other.png"}');
            fclose(fid);
            imwrite(uint8(255 * rand(6, 6, 3)), fullfile(folder, 'Other.png'));

            icon = WorkSpaceTree.iconForResult(RenamedNodeIconTest.node('Other', 'Smooth'), testCase.Root);

            testCase.verifyEqual(icon, WorkSpaceTree.iconForResult( ...
                RenamedNodeIconTest.node('Smooth', 'Smooth'), testCase.Root));
        end

        function aDatasetCachedWithoutCallStillFindsItsIcon(testCase)
            proxy = rmfield(RenamedNodeIconTest.node('Smooth', ''), 'Call');

            icon = WorkSpaceTree.iconForResult(proxy, testCase.Root);

            testCase.verifyTrue(startsWith(icon, 'data:image/png;base64,'), ...
                'With no Call, the id is still tried, as it always was.');
        end

        function aRawRecordingKeepsItsDataTypeBadge(testCase)
            icon = WorkSpaceTree.iconForResult(RenamedNodeIconTest.node('subject01', ''), testCase.Root);

            testCase.verifyEqual(icon, WorkSpaceTree.iconFor('TIMEDOMAIN'));
        end
    end

    methods (Static)
        function proxy = node(id, call)
        %NODE  What a restart rebuilds a node from (eegProxyFromCacheInfo).
            proxy = struct('id', id, 'Call', call, 'DataFormat', 'CONTINUOUS', 'DataType', 'TIMEDOMAIN');
        end
    end
end
