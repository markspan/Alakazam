classdef WorkSpaceTreeBatchTest < matlab.unittest.TestCase
%WORKSPACETREEBATCHTEST  The tree is sent to the page once per batch, not once
%   per node, and a transformation's icon is encoded once per session.
%
%   Every change to WorkSpaceTree used to push the whole tree to the page:
%   every node, every icon as a base64 image. Opening a workspace of 550 nodes,
%   or applying a ten-step template to a dozen recordings, was hundreds of
%   complete sends, and each addNode also re-read and re-encoded the same icon
%   file. beginBatch defers the send until the last batch ends.
%
%   The tree lives in a uihtml component, so these tests need a uifigure. They
%   are skipped, not failed, where one cannot be made.
%
%   Run with: runtests('tests/WorkSpaceTreeBatchTest.m').
%
%   See also WORKSPACETREE.

    properties
        Figure
        Tree
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'src')));
        end
    end

    methods (TestMethodSetup)
        function makeTree(testCase)
            try
                testCase.Figure = uifigure('Visible', 'off');
                testCase.Tree = WorkSpaceTree(testCase.Figure);
            catch ME
                testCase.assumeFail(['A uifigure with a uihtml tree could not be created here: ' ME.message]);
            end
        end
    end

    methods (TestMethodTeardown)
        function closeFigure(testCase)
            if ~isempty(testCase.Figure) && isvalid(testCase.Figure)
                delete(testCase.Figure);
            end
        end
    end

    methods (Test)
        function eachChangeIsOneSendOutsideABatch(testCase)
            before = testCase.sends();
            testCase.addNodes(3);

            testCase.verifyEqual(testCase.sends() - before, 3);
        end

        function aBatchSendsOnceWhenItEnds(testCase)
            before = testCase.sends();
            release = testCase.Tree.beginBatch(); %#ok<NASGU>
            testCase.addNodes(3);

            testCase.verifyEqual(testCase.sends(), before, ...
                'Nothing should be sent while the batch is open.');
            testCase.verifyEqual(numel(testCase.Tree.allNodes()), 3, ...
                'The nodes themselves are added at once; only the redraw waits.');

            clear release;
            testCase.verifyEqual(testCase.sends() - before, 1);
            testCase.verifyEqual(numel(testCase.Component().Data.nodes), 3, ...
                'The one send carries every node added in the batch.');
        end

        function batchesNestAndSendOnceAtTheOutermostEnd(testCase)
            before = testCase.sends();
            outer = testCase.Tree.beginBatch(); %#ok<NASGU>
            inner = testCase.Tree.beginBatch(); %#ok<NASGU>
            testCase.addNodes(2);
            clear inner;
            testCase.verifyEqual(testCase.sends(), before, ...
                'Ending the inner batch must not send while the outer one is open.');
            clear outer;

            testCase.verifyEqual(testCase.sends() - before, 1);
        end

        function aBatchThatChangedNothingSendsNothing(testCase)
            before = testCase.sends();
            release = testCase.Tree.beginBatch(); %#ok<NASGU>
            clear release;

            testCase.verifyEqual(testCase.sends(), before);
        end

        function anErrorInsideABatchStillReleasesIt(testCase)
            before = testCase.sends();
            testCase.verifyError(@() failInsideBatch(testCase.Tree), 'BatchTest:boom');

            testCase.verifyEqual(testCase.sends() - before, 1, ...
                'The changes made before the error must still reach the page.');
            testCase.addNodes(1);
            testCase.verifyEqual(testCase.sends() - before, 2, ...
                'And later changes must send as usual, not stay held back.');
        end

        function aTransformationIconIsReadOnceThenRemembered(testCase)
            root = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            folder = fullfile(root, 'Foo');
            mkdir(folder);
            fid = fopen(fullfile(folder, 'Foo.json'), 'w');
            fwrite(fid, '{"Icon": "Foo.png"}');
            fclose(fid);
            imwrite(uint8(255 * rand(6, 6, 3)), fullfile(folder, 'Foo.png'));

            first = WorkSpaceTree.iconForResult(struct('id', 'Foo'), root);
            delete(fullfile(folder, 'Foo.png'));
            second = WorkSpaceTree.iconForResult(struct('id', 'Foo'), root);

            testCase.verifyTrue(startsWith(first, 'data:image/png;base64,'));
            testCase.verifyEqual(second, first, ...
                'The icon was encoded again, so the file was read again.');
        end
    end

    methods (Access = private)
        function n = sends(testCase)
        %SENDS  How many times the tree has been pushed to the page (the payload
        %   carries a sequence number; the constructor's first payload has none).
            data = testCase.Component().Data;
            n = 0;
            if isstruct(data) && isfield(data, 'seq')
                n = data.seq;
            end
        end

        function c = Component(testCase)
            c = testCase.Tree.Component;
        end

        function addNodes(testCase, n)
            for k = 1:n
                testCase.Tree.addNode(sprintf('n%d', k), '', 'default', sprintf('f%d.mat', k));
            end
        end
    end
end

function failInsideBatch(tree)
    release = tree.beginBatch(); %#ok<NASGU>
    tree.addNode('x', '', 'default', 'x.mat');
    error('BatchTest:boom', 'boom');
end
