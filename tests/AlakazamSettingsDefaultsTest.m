classdef AlakazamSettingsDefaultsTest < matlab.unittest.TestCase
%ALAKAZAMSETTINGSDEFAULTSTEST  AlakazamSettings.useDefaults, what the
%   manual's pictures are taken with: every setting at its default for this
%   MATLAB session, the bands included, without the stored file being
%   written; reload reads the user's own settings back.
%
%   The manual's pictures were once taken with one user's own settings (the
%   jet colour map, reversed sort, trials grouped by bin, a 2 x SE band),
%   where a new installation shows the defaults.
%
%   Run with: runtests('tests/AlakazamSettingsDefaultsTest.m').
%
%   See also ALAKAZAMSETTINGS, CAPTUREMANUALIMAGES.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'src')));
        end
    end

    methods (TestMethodSetup)
        function startFromTheStoredSettings(testCase)
            % Whatever a test changes in memory, the next starts from the
            % stored file again; nothing here writes it.
            AlakazamSettings.reload();
            testCase.addTeardown(@() AlakazamSettings.reload());
        end
    end

    methods (Test)
        function everySettingIsAtItsDefault(testCase)
            AlakazamSettings.set('graphics', 'colormap', 'name', 'jet');
            AlakazamSettings.set('graphics', 'epochImage', 'groupByBin', true);
            AlakazamSettings.set('graphics', 'epochImage', 'reverseSort', true);
            AlakazamSettings.set('graphics', 'erpPlot', 'confIntN', 2);
            AlakazamSettings.useDefaults();
            testCase.verifyEqual(AlakazamSettings.get('graphics', 'colormap', 'name'), 'diverging');
            testCase.verifyFalse(AlakazamSettings.get('graphics', 'epochImage', 'groupByBin'));
            testCase.verifyFalse(AlakazamSettings.get('graphics', 'epochImage', 'reverseSort'));
            testCase.verifyEqual(AlakazamSettings.get('graphics', 'erpPlot', 'confIntN'), 3);
        end

        function theBandsAreAtTheirDefaultsToo(testCase)
            AlakazamSettings.useDefaults();
            defaults = AlakazamSettings.getBands();
            testCase.assertNotEmpty(defaults);
            AlakazamSettings.setBands(defaults(1));
            AlakazamSettings.useDefaults();
            testCase.verifyEqual(AlakazamSettings.getBands(), defaults);
        end

        function theStoredFileIsNotWritten(testCase)
            file = fullfile(prefdir, 'AlakazamSettings.json');
            before = fileState(file);
            AlakazamSettings.set('graphics', 'colormap', 'name', 'jet');
            AlakazamSettings.useDefaults();
            testCase.verifyEqual(fileState(file), before);
        end

        function reloadReadsTheUsersOwnBack(testCase)
            own = AlakazamSettings.instance().Values;
            AlakazamSettings.useDefaults();
            AlakazamSettings.reload();
            testCase.verifyEqual(AlakazamSettings.instance().Values, own);
        end
    end
end

function state = fileState(file)
%FILESTATE  A file's contents and modification time, or empty when absent.
    state = {};
    if isfile(file)
        info = dir(file);
        state = {fileread(file), info.datenum};
    end
end
