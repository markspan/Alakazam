classdef ApplyPendingAlakazamUpdateTest < matlab.unittest.TestCase
%APPLYPENDINGALAKAZAMUPDATETEST  Unit tests for applyPendingAlakazamUpdate.m,
%   the swap startAlakazam runs before anything from src/ is on the path.
%
%   Every test builds its own throwaway "install" folder under a fresh
%   matlab.unittest.fixtures.TemporaryFolderFixture and stages a sibling
%   AlakazamUpdatePending next to it by hand, so nothing here depends on
%   network access or this repository's own real install layout.
%
%   WHAT THESE TESTS CANNOT REACH. The whole reason applyPendingAlakazamUpdate
%   moves PENDING's individual children into HERE rather than moving PENDING
%   itself (see that function's own header) is a Windows quirk that only
%   shows up when the currently-EXECUTING .m file lives inside the folder
%   being renamed -- confirmed empirically, by hand, with a script that
%   really was running from the folder it moved. Called from here, the test
%   runner itself is executing from tests/, not from "install", so the
%   locked-empty-stub behaviour the content-move approach exists to avoid
%   never actually triggers either way. These tests pin the swap's
%   observable CORRECTNESS (data and workspaces survive, stale files don't,
%   backups don't pile up) regardless of which code path produced it; they
%   are not what proved the Windows-specific reason for choosing it.
%
%   Run with: runtests('tests/ApplyPendingAlakazamUpdateTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
        end
    end

    methods (Test)
        function nothingStagedDoesNothing(testCase)
            install = testCase.makeInstall('V1');

            applied = applyPendingAlakazamUpdate(install);

            testCase.verifyFalse(applied);
            testCase.verifyEqual(strtrim(fileread(fullfile(install, 'VERSION'))), 'V1');
        end

        function aStagedUpdateIsSwappedIn(testCase)
            install = testCase.makeInstall('V1');
            testCase.stagePending(install, 'V2');

            applied = applyPendingAlakazamUpdate(install);

            testCase.verifyTrue(applied);
            testCase.verifyEqual(strtrim(fileread(fullfile(install, 'VERSION'))), 'V2');
            testCase.verifyEqual(strtrim(fileread(fullfile(install, 'src', 'thing.m'))), 'V2-thing');
        end

        function thePendingFolderIsGoneAfterApplying(testCase)
        %THEPENDINGFOLDERISGONEAFTERAPPLYING  Applied once, nothing is left
        %   to re-apply or pile up next launch.
            install = testCase.makeInstall('V1');
            testCase.stagePending(install, 'V2');

            applyPendingAlakazamUpdate(install);

            testCase.verifyFalse(isfolder(fullfile(fileparts(install), 'AlakazamUpdatePending')));
        end

        function dataAndWorkspacesSurviveTheSwap(testCase)
        %DATAANDWORKSPACESSURVIVETHESWAP  Neither is part of a release
        %   package (see .github/workflows/release.yml's own exclusion
        %   check), so the swap has to carry them across by hand or the
        %   analyst loses their data and saved workspaces on every update.
            install = testCase.makeInstall('V1');
            mkdir(fullfile(install, 'Data'));
            testCase.writeFile(fullfile(install, 'Data', 'mine.txt'), 'my-data');
            testCase.writeFile(fullfile(install, 'Project.wksp'), 'my-workspace');
            testCase.stagePending(install, 'V2');

            applyPendingAlakazamUpdate(install);

            testCase.verifyEqual(strtrim(fileread(fullfile(install, 'Data', 'mine.txt'))), 'my-data');
            testCase.verifyEqual(strtrim(fileread(fullfile(install, 'Project.wksp'))), 'my-workspace');
        end

        function staleFilesNotInTheNewPackageAreGone(testCase)
        %STALEFILESNOTINTHENEWPACKAGEAREGONE  The swap replaces the source
        %   tree wholesale (old install moved entirely to backup, new
        %   package's own files moved in), not a merge -- a .m file removed
        %   in the new release must not linger and shadow anything.
            install = testCase.makeInstall('V1');
            testCase.writeFile(fullfile(install, 'src', 'onlyInOld.m'), 'stale');
            testCase.stagePending(install, 'V2');

            applyPendingAlakazamUpdate(install);

            testCase.verifyEqual(exist(fullfile(install, 'src', 'onlyInOld.m'), 'file'), 0);
        end

        function anIncompleteStashIsIgnored(testCase)
        %ANINCOMPLETESTASHISIGNORED  Missing VERSION or startAlakazam.m: not
        %   a real release package (a partial download, an interrupted
        %   unzip), so left alone rather than swapped in half-broken.
            install = testCase.makeInstall('V1');
            pending = fullfile(fileparts(install), 'AlakazamUpdatePending');
            mkdir(pending);
            testCase.writeFile(fullfile(pending, 'VERSION'), 'V2');
            % startAlakazam.m deliberately not written.

            applied = applyPendingAlakazamUpdate(install);

            testCase.verifyFalse(applied);
            testCase.verifyEqual(strtrim(fileread(fullfile(install, 'VERSION'))), 'V1');
        end

        function aSecondApplyReplacesThePreviousBackupRatherThanAccumulating(testCase)
        %ASECONDAPPLYREPLACESTHEPREVIOUSBACKUP  Exactly one backup is ever
        %   kept -- the whole point being fixed, not versioned, names for
        %   both the pending and backup folders.
            install = testCase.makeInstall('V1');
            testCase.stagePending(install, 'V2');
            applyPendingAlakazamUpdate(install);

            testCase.stagePending(install, 'V3');
            applyPendingAlakazamUpdate(install);

            backup = fullfile(fileparts(install), 'AlakazamPreUpdateBackup');
            testCase.assertTrue(isfolder(backup));
            testCase.verifyEqual(strtrim(fileread(fullfile(backup, 'VERSION'))), 'V2', ...
                'The backup should hold the install that was replaced most recently (V2), not V1.');

            entries = dir(fileparts(install));
            names = {entries([entries.isdir]).name};
            testCase.verifyEqual(nnz(startsWith(names, 'AlakazamPreUpdateBackup')), 1, ...
                'More than one backup folder was left behind.');
        end

        function thePendingFolderNameMatchesDownloadAlakazamUpdate(testCase)
        %THEPENDINGFOLDERNAMEMATCHESDOWNLOADALAKAZAMUPDATE  The fixed
        %   "AlakazamUpdatePending" name is a literal in two files --
        %   this one runs before src/ is on the path, so it cannot share a
        %   helper function with downloadAlakazamUpdate.m (in src/) to stay
        %   in sync automatically. Pinning both literals here is what
        %   catches one being renamed without the other.
            root = fileparts(fileparts(mfilename('fullpath')));
            hereSource = fileread(fullfile(root, 'applyPendingAlakazamUpdate.m'));
            downloadSource = fileread(fullfile(root, 'src', 'downloadAlakazamUpdate.m'));

            testCase.verifySubstring(hereSource, 'AlakazamUpdatePending');
            testCase.verifySubstring(downloadSource, 'AlakazamUpdatePending');
        end
    end

    methods (Access = private)
        function install = makeInstall(testCase, version)
        %MAKEINSTALL  A throwaway release layout: VERSION, startAlakazam.m,
        %   and src/thing.m, named after VERSION so a swap is easy to check.
            parent = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture()).Folder;
            install = fullfile(parent, 'Install');
            mkdir(fullfile(install, 'src'));
            testCase.writeFile(fullfile(install, 'VERSION'), version);
            testCase.writeFile(fullfile(install, 'startAlakazam.m'), ...
                sprintf('function startAlakazam()\n%% %s\nend\n', version));
            testCase.writeFile(fullfile(install, 'src', 'thing.m'), [version '-thing']);
        end

        function stagePending(testCase, install, version)
        %STAGEPENDING  A sibling AlakazamUpdatePending next to INSTALL, as
        %   downloadAlakazamUpdate would leave it.
            pending = fullfile(fileparts(install), 'AlakazamUpdatePending');
            if isfolder(pending)
                rmdir(pending, 's');
            end
            mkdir(fullfile(pending, 'src'));
            testCase.writeFile(fullfile(pending, 'VERSION'), version);
            testCase.writeFile(fullfile(pending, 'startAlakazam.m'), ...
                sprintf('function startAlakazam()\n%% %s\nend\n', version));
            testCase.writeFile(fullfile(pending, 'src', 'thing.m'), [version '-thing']);
        end

        function writeFile(~, path, content)
            fid = fopen(path, 'w');
            fprintf(fid, '%s', content);
            fclose(fid);
        end
    end
end
