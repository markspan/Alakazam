classdef RibbonScanTest < matlab.unittest.TestCase
%RIBBONSCANTEST  Which folders under Transformations are transformations.
%
%   THIS RAN AT STARTUP AND WAS UNTESTED, which is how it managed to stop
%   the app opening at all. The ribbon is built inside the Alakazam
%   constructor, before the main window exists, so an exception raised while
%   deciding what to put on it is not a missing button: it is no
%   application. The specific failure was that the scan skipped the one
%   package folder that existed at the time, '+TransTools', BY NAME. Adding
%   a second package under Transformations was therefore enough to break
%   startup, and adding packages is a normal thing to do.
%
%   The rule is now structural -- a folder starting with + or @ is a MATLAB
%   package or class and cannot be a transformation -- and these tests hold
%   it to that, using temporary folders so the repository never has to
%   contain the broken shapes being tested.
%
%   Run with: runtests('tests/RibbonScanTest.m').

    properties
        Root
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            repo = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(repo, 'src')));
        end
    end

    methods (TestMethodSetup)
        function makeTransRoot(testCase)
            f = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture());
            testCase.Root = f.Folder;
        end
    end

    methods (Access = private)
        function addTransformation(testCase, name)
        %ADDTRANSFORMATION  A minimally valid plugin folder: manifest + code.
            folder = fullfile(testCase.Root, name);
            mkdir(folder);
            manifest = struct('Name', name, 'Tab', 'Transform', ...
                'Group', 'Test', 'Icon', [name '.png'], 'Tooltip', 'test');
            fid = fopen(fullfile(folder, [name '.json']), 'w');
            fwrite(fid, jsonencode(manifest));
            fclose(fid);
        end

        function addFolder(testCase, name)
        %ADDFOLDER  A folder with no manifest in it at all.
            mkdir(fullfile(testCase.Root, name));
        end

        function names = scanNames(testCase)
            infos = AlakazamRibbon.ScanTransformations(testCase.Root);
            if isempty(infos)
                names = {};
            else
                names = arrayfun(@(s) char(string(s.Folder)), infos, ...
                    'UniformOutput', false);
            end
        end
    end

    methods (Test)
        function findsAPlainTransformation(testCase)
            testCase.addTransformation('Widget');
            testCase.verifyEqual(testCase.scanNames(), {'Widget'});
        end

        function ignoresAnyPackageFolderNotJustTransTools(testCase)
        %   THE REGRESSION. '+TransTools' was excluded by name, so the next
        %   package added -- here '+SourceCache', the one that actually did
        %   it -- was scanned as a transformation, found no manifest, and
        %   threw during startup.
        %
        %   SILENTLY is the load-bearing word, and this test needs it to
        %   have any force at all. Skipping a manifest-less folder (below)
        %   would keep a stray package from throwing, so asserting only the
        %   result here would pass even with the name list restored -- the
        %   two behaviours cover for each other. They differ in what they
        %   mean: a package is not a transformation and there is nothing to
        %   report, whereas a folder that should have had a manifest and has
        %   none is a broken transformation and must say so. Checking that
        %   this case stays warning-free is what makes the name-list bug
        %   visible, and it also keeps startup from printing a warning per
        %   package for the rest of the project's life.
            testCase.addTransformation('Widget');
            testCase.addFolder('+TransTools');
            testCase.addFolder('+SourceCache');
            testCase.addFolder('+AnythingElse');
            names = testCase.verifyWarningFree(@() testCase.scanNames());
            testCase.verifyEqual(names, {'Widget'});
        end

        function ignoresClassFolders(testCase)
            testCase.addTransformation('Widget');
            testCase.addFolder('@SomeClass');
            names = testCase.verifyWarningFree(@() testCase.scanNames());
            testCase.verifyEqual(names, {'Widget'});
        end

        function aFolderWithoutAManifestIsSkippedNotFatal(testCase)
        %   Losing one button beats losing the window. The warning names the
        %   folder, because a silently absent transformation is its own
        %   afternoon of confusion.
            testCase.addTransformation('Widget');
            testCase.addFolder('HalfFinished');
            testCase.verifyWarning(@() testCase.scanNames(), ...
                'Alakazam:AlakazamRibbon');
            testCase.verifyEqual( ...
                testCase.verifyWarningFree(@() scanQuietly(testCase)), {'Widget'});
        end

        function survivesARootWithNoTransformationsAtAll(testCase)
            testCase.addFolder('+OnlyAPackage');
            testCase.verifyEmpty(testCase.verifyWarningFree(@() testCase.scanNames()));
        end

        function theRealTransformationsFolderScansClean(testCase)
        %   The end-to-end case: the shipping folder, scanned without a
        %   single warning, offering every transformation actually present.
            repo = fileparts(fileparts(mfilename('fullpath')));
            transRoot = fullfile(repo, 'src', 'Transformations');
            infos = testCase.verifyWarningFree( ...
                @() AlakazamRibbon.ScanTransformations(transRoot));

            found = arrayfun(@(s) char(string(s.Folder)), infos, ...
                'UniformOutput', false);
            onDisk = dir(transRoot);
            onDisk = {onDisk([onDisk.isdir]).name};
            expected = onDisk(~startsWith(onDisk, {'.', '+', '@'}));

            testCase.verifyEqual(sort(found(:)), sort(expected(:)), ...
                'Every non-package folder under Transformations should be offered.');
        end
    end
end

function names = scanQuietly(testCase)
    w = warning('off', 'Alakazam:AlakazamRibbon');
    % Held, not cleared: this restores the warning state when scanQuietly
    % returns, which is the point. Clearing it here would restore the state
    % before the scan below ever ran.
    cleanup = onCleanup(@() warning(w));
    names = testCase.scanNames();
    clear cleanup;
end
