classdef ErpsetExportTest < matlab.unittest.TestCase
%ERPSETEXPORTTEST  An average exported as an ERPLAB ERPset (averagedToErpset,
%   as Export as ERPset writes it) opens in ERPLAB as one of its own.
%
%   THE ONE THIS PINS. The ERPset said version 'Alakazam', which ERPLAB's
%   loader cannot read as a version number, so it took the file for a very
%   old one: "Erpset ... was created from an older ERPLAB version", "ERPLAB
%   will attempt to update the ERP structure", and the loaded ERPset lost
%   its file name and was marked unsaved. ERPLAB stamps its own ERPsets with
%   geterplabversion, and so does the export now, reading it from EEGLAB's
%   plugins folder when ERPLAB is not on the path.
%
%   Run with: runtests('tests/ErpsetExportTest.m').
%
%   See also AVERAGEDTOERPSET, ONEXPORTERPSET, EXPORTSETTEST.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'IO'), ...
                     fullfile(root, 'src', 'Transformations'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Transformations', 'DefineBins'), ...
                     fullfile(root, 'src', 'Transformations', 'Average'), ...
                     fullfile(root, 'tests')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end

        function ensureEeglab(testCase)
            testCase.assumeTrue(~isempty(which('eeglab')), 'EEGLAB is not on the MATLAB path.');
            if isempty(which('eeg_checkset'))
                eeglab('nogui');
            end
            testCase.assumeFalse(isempty(which('eeg_checkset')), 'EEGLAB is not initialised.');
        end
    end

    methods (Test)
        function theVersionIsOneErplabReads(testCase)
        %THEVERSIONISONEERPLABREADS  A.B or A.B.C, as ERPLAB numbers its
        %   own: the installed ERPLAB's where there is one (found in EEGLAB's
        %   plugins folder, as the app runs without ERPLAB on the path), and
        %   13.10, the version the ERPset shape was checked against, where
        %   there is not.
            ERP = averagedToErpset(ErpsetExportTest.average());

            testCase.verifyMatches(ERP.version, '^\d+\.\d+(\.\d+)?$');
            if ErpsetExportTest.attachErplab(testCase)
                testCase.verifyEqual(ERP.version, geterplabversion(), 'The installed ERPLAB''s own version.');
            else
                testCase.verifyEqual(ERP.version, '13.10');
            end
        end

        function theVersionIsReadFromEeglabsPluginsFolder(testCase)
        %THEVERSIONISREADFROMEEGLABSPLUGINSFOLDER  Without ERPLAB on the
        %   path, the erplabver of the ERPLAB in EEGLAB's plugins folder, the
        %   newest by number (100.2, not 99.1, which sorts last by name).
            average = ErpsetExportTest.average();
            testCase.assumeTrue(isempty(which('geterplabversion')), 'ERPLAB is on the path already.');
            eeglab = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            fclose(fopen(fullfile(eeglab, 'eeglab.m'), 'w'));
            for v = ["99.1", "100.2"]
                plugin = fullfile(eeglab, 'plugins', "erplab" + v);
                mkdir(plugin);
                writelines(["erplabver = '" + v + "';                  % current erplab version", ...
                    "erplabrel = '01-Jan-2030';"], fullfile(plugin, 'erplab_default_values.m'));
            end
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(eeglab));

            ERP = averagedToErpset(average);

            testCase.verifyEqual(ERP.version, '100.2');
        end
    end

    methods (Test, TestTags = {'External'})
        function erplabOpensItWithoutUpdatingIt(testCase)
            testCase.assumeTrue(ErpsetExportTest.attachErplab(testCase), 'ERPLAB is not installed.');
            average = ErpsetExportTest.average();
            ERP = averagedToErpset(average);
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            ERP.erpname = 'average';
            ERP.filename = 'average.erp';
            ERP.filepath = folder;
            save(fullfile(folder, 'average.erp'), 'ERP');     % as onExportErpset writes it

            loaded = [];
            said = evalc('loaded = pop_loaderp(''filename'', ''average.erp'', ''filepath'', folder);');

            testCase.verifyFalse(contains(said, 'ERPLAB version'), ...
                sprintf('ERPLAB took the file for another version:\n%s', said));
            testCase.verifyFalse(contains(said, 'attempt to update'), said);
            testCase.verifyEqual(loaded.filename, 'average.erp', 'Kept as saved, not reset by an update.');
            testCase.verifyEqual(loaded.bindata, double(average.data), 'AbsTol', 1e-9);
            testCase.verifyEqual(loaded.bindescr, {'First', 'Second', 'Second minus first'});
        end
    end

    methods (Static)
        function average = average()
        %AVERAGE  A real Average of DefineBins' trials, difference bin
        %   included (ExportSetTest's recording).
            EEG = ExportSetTest.continuousRecording();
            script = ['bin 1 "First" "S1"' newline 'bin 2 "Second" "S2"' newline ...
                'bin 3 "Second minus first" = bin 2 - bin 1' newline 'epoch [-200,800] ms'];
            epoched = [];
            evalc('epoched = DefineBins(EEG, struct(''script'', script));');
            average = [];
            evalc('average = Average(epoched);');
        end

        function attached = attachErplab(testCase)
        %ATTACHERPLAB  ERPLAB from EEGLAB's plugins folder, for this test
        %   only; false when there is no ERPLAB.
            if isempty(which('pop_loaderp')) && ~isempty(which('eeglab'))
                erplab = dir(fullfile(fileparts(which('eeglab')), 'plugins', 'erplab*'));
                if ~isempty(erplab)
                    testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                        fullfile(erplab(end).folder, erplab(end).name), 'IncludeSubfolders', true));
                end
            end
            attached = ~isempty(which('pop_loaderp'));
        end
    end
end
