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

        function aComponentARecordingCouldNotBuildIsNamed(testCase)
        %ACOMPONENTARECORDINGCOULDNOTBUILDISNAMED  The second recording has no
        %   30 Hz trials, as RIFT subjects 4 to 10 have none: RESS leaves its
        %   RESS30Hz empty, the Spectral Measure still runs and reads it as
        %   missing, and the report says which recording and why.
            entries = RessReportTest.entries(500, true);

            qmd = generateQuartoReport(entries, 'x.csv');

            testCase.verifySubstring(qmd, ['RESS30Hz could not be built in 1 of the 2 recordings (s2), ' ...
                'which has no usable trial of SSVEP 30Hz']);
            testCase.verifyFalse(contains(qmd, 'RESS60Hz could not be built'));
            [coh1, snr1] = RessReportTest.readout(entries(1).EEG, '30Hz', 'RESS30Hz');
            [coh2, snr2] = RessReportTest.readout(entries(2).EEG, '30Hz', 'RESS30Hz');
            testCase.verifyTrue(all(isfinite(coh1(1:3))) && all(isfinite(snr1(1:3))), ...
                'Built in the first recording, it is read in every bin with trials.');
            testCase.verifyTrue(all(isnan(coh2)) && all(isnan(snr2)), 'Empty in the second: missing.');
        end

        function howFarEachFilterSeparatedIsStated(testCase)
        %HOWFAREACHFILTERSEPARATEDISSTATED  The largest eigenvalue is the
        %   separation the filter achieved; near 1 it found nothing, which
        %   the article asks a reader to check and the table of coherences
        %   cannot show.
            entries = RessReportTest.entries(500);
            entries(2).EEG.etc.alz.ress(1).eigenvalues(1) = 0.85;

            qmd = generateQuartoReport(entries, 'x.csv');

            testCase.verifySubstring(qmd, 'RESS60Hz separated 60 Hz from the frequencies beside it');
            testCase.verifySubstring(qmd, 'A factor near 1 means');
            testCase.verifySubstring(qmd, 's2 is below 1');
            testCase.verifyFalse(contains(qmd, 'RESS64Hz separated 64 Hz from the frequencies beside it by a factor of 0'), ...
                'The other component separated normally, so it gets no warning.');
        end

        function anInvertedMapIsNamed(testCase)
        %ANINVERTEDMAPISNAMED  The sign of a component is fixed by the
        %   largest channel of its own map, so a recording whose map points
        %   the other way has its phase half a cycle from the rest.
            entries = RessReportTest.entries(500);
            entries(3) = entries(1);
            entries(3).subject = 's3';
            entries(3).person = 's3';
            entries(3).EEG.etc.alz.ress(1).map = -entries(1).EEG.etc.alz.ress(1).map;

            qmd = generateQuartoReport(entries, 'x.csv');

            testCase.verifySubstring(qmd, 'The scalp map of s3 is inverted relative to the others');
            testCase.verifySubstring(qmd, 'half a cycle');
        end

        function theSnrBiasIsStatedAndMeasuredAgainstTheFilterSOwnBand(testCase)
        %THESNRBIASISSTATEDANDMEASUREDAGAINSTTHEFILTERSOWNBAND  A component's
        %   SNR is above 1 by construction (Cohen & Gulbinaite), and most so
        %   when the SNR neighbours lie inside the band the filter suppressed.
            entries = RessReportTest.entries(500);
            wide = generateQuartoReport(entries, 'x.csv');          % neighbours out to 3.7 Hz
            for k = 1:numel(entries)
                entries(k).EEG.params.snrNeighbours = 2;            % out to 1 Hz: inside the band
            end
            narrow = generateQuartoReport(entries, 'x.csv');

            testCase.verifySubstring(wide, 'partly a biased measure');
            testCase.verifyFalse(contains(wide, 'inside the band the filter suppressed'), ...
                'Out there the neighbours are past the reference band, so there is nothing to warn about.');
            testCase.verifySubstring(narrow, 'inside the band the filter suppressed');
            testCase.verifySubstring(narrow, 'raising the Spectral Measure''s neighbour count');
        end

        function aNeighbourOnAnotherConditionSFrequencyIsNamed(testCase)
        %ANEIGHBOURONANOTHERCONDITIONSFREQUENCYISNAMED  The reference
        %   covariance is what the filter suppresses, so building it at
        %   another condition's own frequency suppresses that condition's
        %   response on purpose. The authors avoided precisely this with
        %   their 16 and 17 Hz stimuli.
            entries = RessReportTest.entries(500);
            for k = 1:numel(entries)   % neighbours 4 Hz either side of 60: one lands on the 64 Hz bin
                for c = 1:numel(entries(k).EEG.etc.alz.ress)
                    entries(k).EEG.etc.alz.ress(c).neighbourDistance = 4;
                end
            end

            qmd = generateQuartoReport(entries, 'x.csv');

            testCase.verifySubstring(qmd, 'RESS60Hz is built to suppress the frequencies 4 Hz either side of 60 Hz');
            testCase.verifySubstring(qmd, 'RIFT 64Hz (64 Hz) was tagged at one of them');
            testCase.verifySubstring(qmd, 'not to be compared through it');
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
        function entries = entries(winSize, secondLacks30Hz)
        %ENTRIES  Two recordings of RESSTest's fixture, each through RESS and a
        %   Spectral Measure reading the components with frame coherence of
        %   WINSIZE samples to the photodiode. With SECONDLACKS30HZ, a third
        %   component is built from the 30 Hz bin, which the second recording
        %   has no trials of.
            if nargin < 2
                secondLacks30Hz = false;
            end
            entries = struct('subject', {}, 'datasetType', {}, 'group', {}, 'person', {}, 'session', {}, 'EEG', {});
            opts = RESSTest.options();
            rows = {struct('label', '60Hz', 'freq', '60', 'channels', 'Oz RESS60Hz'), ...
                    struct('label', '64Hz', 'freq', '64', 'channels', 'Oz RESS64Hz')};
            if secondLacks30Hz
                opts.rows{3} = struct('label', 'RESS30Hz', 'freq', 30, 'bins', 'SSVEP 30Hz');
                rows{3} = struct('label', '30Hz', 'freq', '30', 'channels', 'Oz RESS30Hz');
            end
            spec = struct('rows', {rows}, ...
                'fundamentals', '', 'refChannel', 'PhotoDiode', 'method', 'Hann', 'tapers', 3, ...
                'snrNeighbours', 10, 'snrGuard', 1, 'coherenceMethod', 'frames', ...
                'crossf', struct('Method', 'frames', 'WinSize', winSize));
            for s = 1:2
                EEG = RESSTest.recording();
                EEG.data = EEG.data + 0.01 * s * randn(size(EEG.data));
                if secondLacks30Hz && s == 2
                    EEG.bindesc(4).trials = [];
                end
                warned = warning('off', 'Alakazam:RESS:noTrials');
                R = RESS(EEG, opts);
                warning(warned);
                [M, used] = SpectralMeasure(R, spec);
                M.params = used;
                entries(end + 1) = struct('subject', sprintf('s%d', s), 'datasetType', 'subject', ...
                    'group', '', 'person', sprintf('s%d', s), 'session', '', 'EEG', M); %#ok<AGROW>
            end
        end

        function [coh, snr] = readout(M, rowLabel, channel)
        %READOUT  One channel's coherence and SNR in every bin, from the
        %   Spectral Measure row ROWLABEL of M.
            row = M.spectralMeasures{cellfun(@(r) strcmp(r.label, rowLabel), M.spectralMeasures)};
            c = strcmp(row.channels, channel);
            coh = row.coherence(c, :);
            snr = row.snr(c, :);
        end
    end
end
