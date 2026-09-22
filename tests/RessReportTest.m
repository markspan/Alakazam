classdef RessReportTest < matlab.unittest.TestCase
%RESSREPORTTEST  The spectral report's RESS section: what the components are,
%   and which bins are their null.
%
%   The report is to show each component's null automatically: the filter
%   applied to the trials of the other frequency. On the RIFT recordings two
%   kinds of other bin turned out not to be a null, and the section names
%   them rather than letting them pass as one (see ReportSections.ressSection):
%   a bin a harmonic of whose frequency falls on the filter's (30 Hz drives
%   60 Hz), and a bin whose frequency, or a harmonic of it, the coherence
%   frames are too short to separate from the filter's. With 255 ms frames 60
%   and 64 Hz leak into each other; with 1020 ms frames they do not.
%
%   Run with: runtests('tests/RessReportTest.m').
%
%   See also REPORTSECTIONS.RESSSECTION, RESS, RESSTEST.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), fullfile(root, 'src', 'Dialogs'), ...
                     fullfile(root, 'src', 'Reports'), fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Transformations', 'RESS'), ...
                     fullfile(root, 'src', 'Transformations', 'SpectralMeasure'), ...
                     fullfile(root, 'src', 'Transformations', 'Measure'), fullfile(root, 'tests')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function shortFramesAreNotANull(testCase)
            qmd = generateQuartoReport(RessReportTest.entries(100), 'x.csv');   % 100 samples at 500 Hz: 200 ms

            testCase.verifySubstring(qmd, '## RESS components and their null');
            testCase.verifySubstring(qmd, 'RESS60Hz, RESS64Hz are RESS components');
            testCase.verifySubstring(qmd, '"not a clean null: 200 ms frames cannot separate 60 from 64 Hz"', ...
                'The 64 Hz filter''s 60 Hz trials leak through frames this short.');
            testCase.verifySubstring(qmd, '"not a clean null: 30 Hz has a harmonic at 60 Hz"');
            testCase.verifySubstring(qmd, ...
                '"not a clean null: 200 ms frames cannot separate 64 Hz from 60 Hz, a harmonic of 30 Hz"', ...
                'For the 64 Hz filter the 30 Hz bin leaks through its harmonic, not its fundamental.');
            testCase.verifyFalse(contains(qmd, '"null"'), 'With these frames nothing here is a clean null.');
        end

        function longFramesMakeTheOtherFrequencyANull(testCase)
            qmd = generateQuartoReport(RessReportTest.entries(500), 'x.csv');   % 1000 ms frames

            roles = regexp(qmd, 'role = c\(([^)]*)\)', 'tokens', 'once');
            testCase.assertNotEmpty(roles);
            testCase.verifySubstring(roles{1}, '"null"', ...
                'At 1 s the frames separate 60 from 64 Hz, so each filter''s other frequency is its null.');
            testCase.verifySubstring(qmd, '"not a clean null: 30 Hz has a harmonic at 60 Hz"', ...
                'An exact harmonic is never a null, however long the frames.');
            testCase.verifySubstring(qmd, '"built from"');
        end

        function noComponentMeansNoSection(testCase)
            entries = RessReportTest.entries(100);
            for k = 1:numel(entries)
                entries(k).EEG.etc.alz = rmfield(entries(k).EEG.etc.alz, 'ress');
            end

            qmd = generateQuartoReport(entries, 'x.csv');

            testCase.verifyFalse(contains(qmd, 'RESS components and their null'));
        end
    end

    methods (Test, TestTags = {'Slow', 'External'})
        function theSectionRenders(testCase)
            testCase.assumeTrue(~isempty(ReportFixtures.rscriptExe()) && ~isempty(ReportFixtures.quartoExe()), ...
                'R and/or Quarto not found.');
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture()).Folder;
            qmd = ReportFixtures.writeReport(RessReportTest.entries(500), folder, 'ress');

            [html, err] = renderQuartoReport(qmd);

            testCase.assertEmpty(err, sprintf('The report did not render:\n%s', err));
            text = regexprep(fileread(html), '<[^>]+>', ' ');
            testCase.verifySubstring(text, 'Each Component at Its Own Frequency, by Bin');
            testCase.verifyFalse(contains(text, 'there is no null to show'), ...
                'The components were read, so the table must have rows.');
        end
    end

    methods (Static)
        function entries = entries(winSize)
        %ENTRIES  Two recordings of RESSTest's fixture, each through RESS and a
        %   Spectral Measure reading the components with frame coherence of
        %   WINSIZE samples to the photodiode.
            entries = struct('subject', {}, 'datasetType', {}, 'group', {}, 'person', {}, 'session', {}, 'EEG', {});
            opts = RESSTest.options();
            spec = struct('rows', {{struct('label', '60Hz', 'freq', '60', 'channels', 'Oz RESS60Hz'), ...
                                    struct('label', '64Hz', 'freq', '64', 'channels', 'Oz RESS64Hz')}}, ...
                'fundamentals', '', 'refChannel', 'PhotoDiode', 'method', 'Hann', 'tapers', 3, ...
                'snrNeighbours', 10, 'snrGuard', 1, 'coherenceMethod', 'frames', ...
                'crossf', struct('Method', 'frames', 'WinSize', winSize));
            for s = 1:2
                EEG = RESSTest.recording();
                EEG.data = EEG.data + 0.01 * s * randn(size(EEG.data));
                R = RESS(EEG, opts);
                [M, used] = SpectralMeasure(R, spec);
                M.params = used;
                entries(end + 1) = struct('subject', sprintf('s%d', s), 'datasetType', 'subject', ...
                    'group', '', 'person', sprintf('s%d', s), 'session', '', 'EEG', M); %#ok<AGROW>
            end
        end
    end
end
