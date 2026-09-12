classdef EEGLabEnvironmentTest < matlab.unittest.TestCase
%EEGLABENVIRONMENTTEST  Unit tests for src/EEGLabEnvironment.m.
%
%   Only the pure part is tested here: which of several EEGLAB installs on
%   disk Alakazam should use. The rest of the class downloads, addpaths and
%   launches EEGLAB, none of which belongs in a unit test.
%
%   Why this exists: ensureEEGLab used to look for a hardcoded
%   'eeglab2026.0.0'. EEGLAB's own eeglab_update unzips a new release into a
%   folder named after the NEW version and renames the previous one with an
%   '_old' suffix, so the hardcoded name stopped resolving the first time
%   EEGLAB updated itself.
%
%   Run with: runtests('tests/EEGLabEnvironmentTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src')));
        end
    end

    methods (Test)
        function nothingInstalledGivesNothing(testCase)
            testCase.verifyEmpty(EEGLabEnvironment.pickNewestEEGLab({}));
        end

        function theOnlyInstallIsChosen(testCase)
            only = 'C:\Users\x\Documents\MATLAB\eeglab\eeglab2026.0.0';
            testCase.verifyEqual(EEGLabEnvironment.pickNewestEEGLab({only}), only);
        end

        function aNewerVersionBeatsAnOlderOne(testCase)
        %ANEWERVERSIONBEATSANOLDERONE  And note the ASCII trap this exists
        %   to catch: 'eeglab2026.0.0_old' sorts BEFORE 'eeglab2026.1.0',
        %   so simply taking the first match would pick the wrong one.
            base = 'C:\Users\x\Documents\MATLAB\eeglab\';
            old = [base 'eeglab2026.0.0'];
            new = [base 'eeglab2026.1.0'];

            testCase.verifyEqual(EEGLabEnvironment.pickNewestEEGLab({old, new}), new);
            testCase.verifyEqual(EEGLabEnvironment.pickNewestEEGLab({new, old}), new, ...
                'The answer must not depend on the order dir happened to return.');
        end

        function aSupersededOldFolderIsSkipped(testCase)
        %ASUPERSEDEDOLDFOLDERISSKIPPED  An '_old' folder is a complete,
        %   working install, so a plain search finds it. Using it would pin
        %   Alakazam to the copy the user had just replaced.
            base = 'C:\Users\x\Documents\MATLAB\eeglab\';
            superseded = [base 'eeglab2026.0.0_old'];
            current    = [base 'eeglab2026.1.0'];

            testCase.verifyEqual( ...
                EEGLabEnvironment.pickNewestEEGLab({superseded, current}), current);
        end

        function anOldFolderWithAHigherNumberStillLoses(testCase)
        %ANOLDFOLDERWITHAHIGHERNUMBERSTILLLOSES  '_old' wins on version
        %   number whenever a downgrade or a re-install happened. The
        %   suffix has to disqualify it outright, not merely rank it lower.
            base = 'C:\Users\x\Documents\MATLAB\eeglab\';
            superseded = [base 'eeglab2027.0.0_old'];
            current    = [base 'eeglab2026.1.0'];

            testCase.verifyEqual( ...
                EEGLabEnvironment.pickNewestEEGLab({superseded, current}), current);
        end

        function onlySupersededInstallsCountAsNotFound(testCase)
        %ONLYSUPERSEDEDINSTALLSCOUNTASNOTFOUND  Returning '' sends
        %   ensureEEGLab down its "offer to download" branch, which is the
        %   right outcome: there is no current install to attach to.
            base = 'C:\Users\x\Documents\MATLAB\eeglab\';
            testCase.verifyEmpty(EEGLabEnvironment.pickNewestEEGLab( ...
                {[base 'eeglab2026.0.0_old'], [base 'eeglab2025.1.0_old']}));
        end

        function patchNumbersAreComparedNumericallyNotAsText(testCase)
        %PATCHNUMBERSARECOMPAREDNUMERICALLYNOTASTEXT  '10' is greater than
        %   '9', which string comparison gets backwards.
            base = 'C:\Users\x\Documents\MATLAB\eeglab\';
            nine = [base 'eeglab2026.9.0'];
            ten  = [base 'eeglab2026.10.0'];

            testCase.verifyEqual(EEGLabEnvironment.pickNewestEEGLab({nine, ten}), ten);
        end

        function aShorterVersionDoesNotOutrankALongerOne(testCase)
        %ASHORTERVERSIONDOESNOTOUTRANKALONGERONE  'eeglab2026' must not beat
        %   'eeglab2026.0.1' -- the padding in versionKey is what makes the
        %   two comparable at all.
            base = 'C:\Users\x\Documents\MATLAB\eeglab\';
            bare  = [base 'eeglab2026'];
            patch = [base 'eeglab2026.0.1'];

            testCase.verifyEqual(EEGLabEnvironment.pickNewestEEGLab({bare, patch}), patch);
        end

        function aTrailingSeparatorDoesNotConfuseTheVersion(testCase)
            base = 'C:\Users\x\Documents\MATLAB\eeglab\';
            testCase.verifyEqual( ...
                EEGLabEnvironment.pickNewestEEGLab( ...
                    {[base 'eeglab2026.0.0\'], [base 'eeglab2026.1.0\']}), ...
                [base 'eeglab2026.1.0\']);
        end

        function aNameWithNoVersionAtAllIsStillUsable(testCase)
        %ANAMEWITHNOVERSIONATALLISSTILLUSABLE  Someone who unzipped EEGLAB
        %   into a plain 'eeglab' folder should not be told it is missing.
            only = 'C:\Users\x\Documents\MATLAB\eeglab\eeglab';
            testCase.verifyEqual(EEGLabEnvironment.pickNewestEEGLab({only}), only);
        end
    end
end
