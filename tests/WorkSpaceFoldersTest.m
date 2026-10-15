classdef WorkSpaceFoldersTest < matlab.unittest.TestCase
%WORKSPACEFOLDERSTEST  A workspace whose folders are not on this computer is
%   asked about, not opened: a message lists the missing folders, and
%   closing it opens Edit WorkSpace. Nothing is created in the meantime.
%
%   open() makes any missing folder it can, so a Raw folder whose data had
%   moved came back as an empty new folder and the tree as an empty tree,
%   with nothing to say why. The real methods run against a fake workspace
%   (MethodCopy), and the message is caught rather than shown.
%
%   Run with: runtests('tests/WorkSpaceFoldersTest.m').
%
%   See also WORKSPACE.OPENORASK, WORKSPACE.MISSINGDIRECTORIES.

    properties
        Folder
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (TestMethodSetup)
        function copyTheMethods(testCase)
            testCase.Folder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testCase.Folder));
            MethodCopy.make(testCase.Folder, '@WorkSpace', 'missingDirectories', 'missingCopy');
            MethodCopy.make(testCase.Folder, '@WorkSpace', 'openOrAsk', 'openOrAskCopy');
            rehash;
        end
    end

    methods (Test)
        function aWorkspaceWhoseFoldersAreThereOpens(testCase)
            app = testCase.workspace(testCase.made('raw'), testCase.made('cache'), testCase.made('exports'));

            openOrAskCopy(app, @(varargin) testCase.verifyFail('No message is due.'));

            testCase.verifyTrue(app.Opened);
            testCase.verifyFalse(app.Edited);
        end

        function aMovedRawFolderIsAskedAboutNotCreated(testCase)
            moved = fullfile(testCase.Folder, 'old', 'disk', 'raw');
            app = testCase.workspace(moved, testCase.made('cache'), testCase.made('exports'));
            shown = struct('message', '', 'close', []);

            openOrAskCopy(app, @alert);

            testCase.verifyFalse(app.Opened, 'The workspace is not opened on folders that are not there.');
            testCase.verifyFalse(isfolder(moved), 'Nothing is created.');
            testCase.verifySubstring(shown.message, ['Raw data:  ' moved]);
            testCase.verifySubstring(shown.message, 'terribly sorry');
            testCase.verifyEmpty(strfind(shown.message, 'Cache:'), 'Only the missing folder is listed.');
            testCase.verifyFalse(app.Edited, 'Edit WorkSpace waits until the message is closed.');
            shown.close([], []);
            testCase.verifyTrue(app.Edited, 'Closing the message opens Edit WorkSpace.');

            function alert(~, message, ~, varargin)
                shown.message = message;
                shown.close = varargin{find(strcmp(varargin, 'CloseFcn')) + 1};
            end
        end

        function anUnsetFolderIsMissingToo(testCase)
            app = testCase.workspace(testCase.made('raw'), '', fullfile(testCase.Folder, 'nowhere'));
            missing = missingCopy(app);
            testCase.verifyEqual({missing.label}, {'Cache', 'Exports'});
            testCase.verifyEqual(missing(1).path, '');
        end
    end

    methods (Access = private)
        function folder = made(testCase, name)
            folder = fullfile(testCase.Folder, name);
            mkdir(folder);
        end

        function app = workspace(~, raw, cache, exports)
        %WORKSPACE  A fake workspace with these folders, which records
        %   whether it was opened or Edit WorkSpace was.
            app = FakeApp(struct('RawDirectory', raw, 'CacheDirectory', cache, ...
                'ExportsDirectory', exports, 'Parent', struct(), ...
                'Opened', false, 'Edited', false));
            app.addprop('open');
            app.addprop('edit');
            app.addprop('missingDirectories');
            app.open = @() mark(app, 'Opened');
            app.edit = @() mark(app, 'Edited');
            app.missingDirectories = @() missingCopy(app);
        end
    end
end

function mark(app, field)
    app.(field) = true;
end
