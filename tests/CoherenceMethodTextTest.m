classdef CoherenceMethodTextTest < matlab.unittest.TestCase
%COHERENCEMETHODTEXTTEST  The report says how its coherence was estimated.
%
%   The exported CSV holds the coherence and not the method (its twelve columns are
%   pinned by the exporter and by the report), and the estimators differ by a
%   factor of about 2.5, so a report that only quoted the number would leave the
%   reader unable to place it against a coherence map or a published figure.
%   coherenceMethodText reads the method from each SpectralMeasure node's own
%   settings, and generateQuartoReport puts the sentence before any result.
%
%   Run with: runtests('tests/CoherenceMethodTextTest.m').
%
%   See also REPORTSECTIONS.COHERENCEMETHODTEXT, SPECTRALMEASURE.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Reports'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Transformations'), fullfile(root, 'tests')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function theFrameEstimatorIsDescribedWithItsWindow(testCase)
            text = ReportSections.coherenceMethodText(testCase.entryWith( ...
                struct('coherenceMethod', 'frames', 'crossf', struct('WinSize', 480))));

            testCase.verifySubstring(text, 'How coherence was estimated');
            testCase.verifySubstring(text, 'frame-averaged coherence');
            testCase.verifySubstring(text, 'frames of about 500 ms');
            testCase.verifyFalse(contains(text, 'biased'));
        end

        function theSingleWindowIsFlaggedAsBiasedAndNotComparable(testCase)
            text = ReportSections.coherenceMethodText(testCase.entryWith( ...
                struct('coherenceMethod', 'window')));

            testCase.verifySubstring(text, 'a single window');
            testCase.verifySubstring(text, 'biased upwards');
            testCase.verifySubstring(text, 'should not be compared with a coherence map');
        end

        function optionsFromBeforeTheMethodExistedAreReadByTheirOldFlag(testCase)
            on = ReportSections.coherenceMethodText(testCase.entryWith( ...
                struct('crossf', struct('enabled', true, 'MinFreq', 52, 'MaxFreq', 68))));
            off = ReportSections.coherenceMethodText(testCase.entryWith( ...
                struct('crossf', struct('enabled', false))));

            testCase.verifySubstring(on, 'newcrossf');
            testCase.verifySubstring(on, 'between 52 and 68 Hz');
            testCase.verifySubstring(off, 'a single window');
        end

        function recordingsThatDisagreeAreSaidNotToBeComparable(testCase)
            entries = [testCase.entryWith(struct('coherenceMethod', 'frames', 'crossf', struct('WinSize', 480))), ...
                       testCase.entryWith(struct('coherenceMethod', 'window'))];

            text = ReportSections.coherenceMethodText(entries);

            testCase.verifySubstring(text, 'do not share one estimator');
            testCase.verifySubstring(text, 'frame-averaged');
            testCase.verifySubstring(text, 'a single window');
        end

        function nothingIsSaidWhenNoCoherenceWasMeasured(testCase)
            noReference = testCase.entryWith(struct('coherenceMethod', 'frames'));
            noReference.EEG.spectralMeasures{1}.refChannel = '';
            noParams = testCase.entryWith(struct());
            noParams.EEG = rmfield(noParams.EEG, 'params');

            testCase.verifyEqual(ReportSections.coherenceMethodText(noReference), '');
            testCase.verifyEqual(ReportSections.coherenceMethodText(noParams), '');
        end

        function theReportCarriesTheNoteBeforeItsResults(testCase)
            entries = ReportFixtures.censusEntries('F-SPEC3CR');
            for k = 1:numel(entries)
                entries(k).EEG.srate = 960;
                entries(k).EEG.params = struct('coherenceMethod', 'frames', 'crossf', struct('WinSize', 510));
            end

            qmd = generateQuartoReport(entries, 'x.csv');
            plain = generateQuartoReport(rmParams(entries), 'x.csv');

            testCase.verifySubstring(qmd, '**How coherence was estimated.**');
            testCase.verifyFalse(contains(plain, 'How coherence was estimated'), ...
                'Entries with no recorded method must produce the report they always did.');
        end
    end

    methods (Access = private)
        function entry = entryWith(~, params)
            spectral = {struct('label', 'R', 'freq', 60, 'channels', {{'Oz'}}, 'refChannel', 'Photodiode')};
            EEG = struct('spectralMeasures', {spectral}, 'params', params, 'srate', 960);
            entry = struct('subject', 's', 'datasetType', 'subject', 'group', '', ...
                'person', 'p', 'session', '', 'EEG', EEG);
        end
    end
end

function entries = rmParams(entries)
    for k = 1:numel(entries)
        if isfield(entries(k).EEG, 'params')
            entries(k).EEG = rmfield(entries(k).EEG, 'params');
        end
    end
end
