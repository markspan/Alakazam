classdef UnfoldToolboxTest < matlab.unittest.TestCase
%UNFOLDTOOLBOXTEST  Finding the Unfold toolbox, and installing it when it is
%   not there: Unfold.isAvailable, Unfold.ensure and Unfold.startToolbox.
%
%   NOTHING HERE DOWNLOADS ANYTHING, which is the whole difficulty. The
%   install path ends in a 30 MB fetch behind a consent dialog, so a test
%   that called it would either hang on the dialog or spend the network, and
%   a test that mocked the fetch would prove nothing about the real one. What
%   is testable without the network is everything around it, and that is
%   where the failures actually live:
%
%     - the passive check must be passive: no dialog, no download, and no
%       directory created, even when nothing is installed;
%     - an install from a previous session must be reattached in silence,
%       since consent was already given; a prompt here would be a bug that
%       hangs the app, and in a test it hangs the suite;
%     - a half-installed toolbox must answer "not available" rather than
%       throw out of a yes-or-no question;
%     - the three functions must agree about where an install lives and what
%       proves it is there. They are separate files holding the same two
%       strings, which is exactly the pair that drifts.
%
%   A FAKE INSTALL STANDS IN FOR THE REAL ONE. The archive's shape is what
%   matters to this code: init_unfold.m at the root, and the functions
%   themselves one level down in src/uf_toolbox, reachable only once
%   init_unfold has run. The fixture below builds that much and nothing
%   else, under a temporary USERPROFILE so EEGLabEnvironment.findInstalled
%   looks there instead of at the developer's own Documents/MATLAB.
%
%   Run with: runtests('tests/UnfoldToolboxTest.m').
%
%   See also UNFOLD.ISAVAILABLE, UNFOLD.ENSURE,
%   UNFOLD.STARTTOOLBOX, FIELDTRIPFIXTURES.

    properties (Constant)
        Root = fileparts(fileparts(mfilename('fullpath')))
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            for p = {fullfile(UnfoldToolboxTest.Root, 'src'), ...
                     fullfile(UnfoldToolboxTest.Root, 'src', 'Transformations'), ...
                     fullfile(UnfoldToolboxTest.Root, 'tests')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (TestMethodSetup)
        function isolateTheHomeFolder(testCase)
        %ISOLATETHEHOMEFOLDER  A temporary USERPROFILE and an unchanged path.
        %   findInstalled reads USERPROFILE, so pointing it at a temporary
        %   folder is what keeps these tests off the developer's real
        %   install. The path is restored afterwards because the code under
        %   test adds folders to it on purpose.
            testCase.assumeTrue(isempty(which('uf_designmat')), ...
                'The real Unfold toolbox is on this path, so the "not installed" cases cannot be tested.');

            previousProfile = getenv('USERPROFILE');
            previousPath = path();
            testCase.addTeardown(@() setenv('USERPROFILE', previousProfile));
            testCase.addTeardown(@() path(previousPath));

            folder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture()).Folder;
            setenv('USERPROFILE', folder);
            testCase.TempHome = folder;
        end
    end

    properties
        TempHome = ''
    end

    methods (Test)
        function theCheckIsPassiveWhenNothingIsInstalled(testCase)
            available = Unfold.isAvailable();

            testCase.verifyFalse(available);
            testCase.verifyTrue(islogical(available) && isscalar(available), ...
                'Callers branch on this, so it has to be a logical scalar.');
            testCase.verifyFalse(isfolder(fullfile(testCase.TempHome, 'Documents', 'MATLAB', 'unfold')), ...
                'Looking must not create the install folder.');
        end

        function aPreviousInstallIsReattachedWithoutAsking(testCase)
        %APREVIOUSINSTALLISREATTACHEDWITHOUTASKING  addpath from an earlier
        %   session does not survive a restart, so the toolbox is on disk and
        %   off the path. If this branch prompted or downloaded, the test
        %   would hang or fetch; that it returns is the assertion.
            testCase.assumeTrue(~isempty(which('eeg_checkset')), ...
                'Unfold.startToolbox ensures EEGLAB, which this test will not install.');
            root = testCase.fakeInstall('working');

            available = Unfold.isAvailable();

            testCase.verifyTrue(available);
            testCase.verifyEqual(fileparts(which('uf_designmat')), ...
                fullfile(root, 'src', 'uf_toolbox'), ...
                'The reattached install is the one that was found, not something else.');
        end

        function ensureDoesNotPromptWhenAnInstallExists(testCase)
            testCase.assumeTrue(~isempty(which('eeg_checkset')), ...
                'Unfold.startToolbox ensures EEGLAB, which this test will not install.');
            testCase.fakeInstall('working');

            Unfold.ensure('A test');   % a prompt here would hang the suite

            testCase.verifyNotEmpty(which('uf_designmat'));
        end

        function aHalfInstalledToolboxAnswersNoRatherThanThrowing(testCase)
        %AHALFINSTALLEDTOOLBOXANSWERSNORATHERTHANTHROWING  An init_unfold.m
        %   that does not bring the functions with it is a broken install,
        %   which every caller of the passive check has to survive: they ask
        %   a yes-or-no question and skip their work on "no".
            testCase.assumeTrue(~isempty(which('eeg_checkset')), ...
                'Unfold.startToolbox ensures EEGLAB, which this test will not install.');
            root = testCase.fakeInstall('broken');

            testCase.verifyFalse(Unfold.isAvailable());
            testCase.verifyError(@() Unfold.startToolbox(root), 'Alakazam:UnfoldMissing', ...
                'Started directly, the same broken install has to say so.');
        end

        function initRefusesAFolderWithoutTheToolbox(testCase)
            testCase.verifyError(@() Unfold.startToolbox(testCase.TempHome), ...
                'Alakazam:UnfoldMissing');
        end

        function theInstallIsAPinnedTagArchive(testCase)
        %THEINSTALLISAPINNEDTAGARCHIVE  The URL is read rather than followed.
        %   A moving branch archive would silently change the toolbox under a
        %   project, which is the thing ensureFieldTrip's own comment warns
        %   about and this inherits. The toolbox being actively maintained is
        %   a reason to use it, not a reason to track its branch: an analysis
        %   whose numbers depend on when it was installed is not reproducible.
            source = fileread(fullfile(UnfoldToolboxTest.Root, 'src', 'Transformations', ...
                '+Unfold', 'ensure.m'));

            url = regexp(source, 'https://github\.com/unfoldtoolbox/unfold/archive/refs/tags/[\w.]+\.zip', ...
                'match', 'once');
            testCase.assertNotEmpty(url, 'The pinned tag archive URL is gone.');
            testCase.verifyEmpty(regexp(url, '/heads/|/master|/main', 'once'), ...
                'A branch archive is not a pinned version.');
            testCase.verifySubstring(source, 'questdlg', 'The download stays consent-gated.');
        end

        function allThreeFunctionsAgreeOnWhereAnInstallLives(testCase)
        %ALLTHREEFUNCTIONSAGREEONWHEREANINSTALLLIVES  The target name and the
        %   probe file are the same two strings in three files. If the check
        %   looked under one name and the installer wrote another, the app
        %   would download the toolbox again on every single call and nothing
        %   would fail loudly enough to notice.
            folder = fullfile(UnfoldToolboxTest.Root, 'src', 'Transformations', '+Unfold');
            for f = {'isAvailable.m', 'ensure.m'}
                source = fileread(fullfile(folder, f{1}));
                testCase.verifySubstring(source, "findInstalled('unfold', 'init_unfold.m')", ...
                    sprintf('%s looks for the install somewhere else.', f{1}));
            end
            testCase.verifySubstring(fileread(fullfile(folder, 'ensure.m')), ...
                "installFromZip(unfoldUrl, 'unfold', 'init_unfold.m')", ...
                'The installer writes where the others look.');
        end
    end

    methods (Access = private)
        function root = fakeInstall(testCase, kind)
        %FAKEINSTALL  An Unfold-shaped folder under the temporary home.
        %   KIND 'working' puts uf_designmat where the real archive does and
        %   an init_unfold.m that adds it, as the real one does with
        %   src/uf_toolbox; 'broken' leaves init_unfold.m adding nothing, so
        %   the toolbox never becomes usable.
            root = fullfile(testCase.TempHome, 'Documents', 'MATLAB', 'unfold', 'unfold-1.3.1');
            mkdir(fullfile(root, 'src', 'uf_toolbox'));
            if strcmp(kind, 'working')
                writeLines(fullfile(root, 'init_unfold.m'), { ...
                    '% a stand-in for the toolbox initialiser: adds its own functions', ...
                    "addpath(fullfile(fileparts(mfilename('fullpath')), 'src', 'uf_toolbox'));", ...
                    "fprintf('Starting unfold toolbox.\\n');"});
                writeLines(fullfile(root, 'src', 'uf_toolbox', 'uf_designmat.m'), { ...
                    'function EEG = uf_designmat(EEG, varargin)', ...
                    'end'});
            else
                writeLines(fullfile(root, 'init_unfold.m'), { ...
                    '% a stand-in for a broken install: starts, brings nothing', ...
                    "fprintf('Starting unfold toolbox.\\n');"});
            end
            rehash path;
        end
    end
end

% ======================================================================= %
function writeLines(file, lines)
%WRITELINES  Write LINES to FILE, one per line.
    fid = fopen(file, 'w');
    assert(fid > 0, 'Could not write %s', file);
    fprintf(fid, '%s\n', lines{:});
    fclose(fid);
end
