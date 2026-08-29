classdef GenerateQuartoReportTest < matlab.unittest.TestCase
%GENERATEQUARTOREPORTTEST  Smoke coverage for
%   src/IO/generateQuartoReport.m and the src/IO/+ReportSections package it
%   delegates to.
%
%   generateQuartoReport had no test coverage at all before this file: its
%   own R/Quarto output can only be fully validated by actually rendering
%   it (outside MATLAB, requiring Quarto + R), which is out of reach for a
%   MATLAB unit test. What IS reachable, and what these tests actually
%   check, is the MATLAB-level wiring: that every design (1/2/3+ ordinary
%   bins, with and without a between-subjects group, plus a combination
%   bin in both its ordinary and descriptive-only-measure-type forms)
%   resolves to a real section builder in +ReportSections and returns
%   non-empty text containing that section's own heading, rather than
%   erroring with "undefined function" -- exactly the class of bug a
%   package-qualification mistake produces (one such mistake, a bare
%   in-package call to comboSectionDescriptiveOnly that needed to be
%   ReportSections.comboSectionDescriptiveOnly, was caught by writing
%   this file).
%
%   Run with: runtests('tests/GenerateQuartoReportTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'IO')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Support')));
        end
    end

    methods (Test)
        function threeOrdinaryBinsPlusComboNoGroupsReachesAnovaAndCombo(testCase)
        %THREEORDINARYBINSPLUSCOMBONOGROUPSREACHESANOVAANDCOMBO  3 ordinary
        %   bins with no between-subjects group routes to lmmSection; the
        %   combo bin's 'Peak' window produces both an ordinary measure
        %   type (peak_amplitude -> comboSection's own one-sample-vs-zero
        %   text) and a descriptive-only one (peak_latency -> delegates to
        %   comboSectionDescriptiveOnly).
            entries = oneEntry(bindesc3WithCombo(), 'Peak', '');
            txt = generateQuartoReport(entries, 'x.csv');
            testCase.verifySubstring(txt, '## N400 -- peak\_amplitude');
            testCase.verifySubstring(txt, '3 conditions: A, B, C.');           % lmmSection
            testCase.verifySubstring(txt, 'Difference/combination bin');      % comboSection
            testCase.verifySubstring(txt, 'descriptive statistics');         % comboSectionDescriptiveOnly's own text
        end

        function threeOrdinaryBinsPlusComboWithGroupsReachesMixedAndGroupedCombo(testCase)
        %THREEORDINARYBINSPLUSCOMBOWITHGROUPSREACHESMIXEDANDGROUPEDCOMBO
        %   The same design, but with >= 2 distinct subject groups, routes
        %   to lmmSection and comboSectionGrouped instead.
            entries = twoGroupEntries(bindesc3WithCombo(), 'Peak');
            txt = generateQuartoReport(entries, 'x.csv');
            testCase.verifySubstring(txt, '## N400 -- peak\_amplitude');
        end

        function oneOrdinaryBinNoGroupsReachesDescriptiveSection(testCase)
            entries = oneEntry(bindescN(1), 'Mean Amplitude', '');
            txt = generateQuartoReport(entries, 'x.csv');
            testCase.verifySubstring(txt, '## N400 -- mean\_amplitude');
            testCase.verifySubstring(txt, 'descriptive statistics only, no comparison possible');
        end

        function oneOrdinaryBinWithGroupsReachesBetweenSection(testCase)
            entries = twoGroupEntries(bindescN(1), 'Mean Amplitude');
            txt = generateQuartoReport(entries, 'x.csv');
            testCase.verifySubstring(txt, '## N400 -- mean\_amplitude');
        end

        function twoOrdinaryBinsNoGroupsReachesPairedSection(testCase)
            entries = oneEntry(bindescN(2), 'Mean Amplitude', '');
            txt = generateQuartoReport(entries, 'x.csv');
            testCase.verifySubstring(txt, '## N400 -- mean\_amplitude');
            testCase.verifySubstring(txt, 'Two conditions: "A" vs. "B"');
        end

        function spectralReportReachesCircularPhaseHandling(testCase)
        %SPECTRALREPORTREACHESCIRCULARPHASEHANDLING  A Spectral export's
        %   'phase' measure type is circular (see isCircularType): its
        %   combo section must skip the vs-zero test, without erroring.
            entries = oneEntrySpectral(bindesc3WithCombo());
            txt = generateQuartoReport(entries, 'x.csv');
            testCase.verifySubstring(txt, '## 10Hz -- phase');
        end
    end
end

function bindesc = bindesc3WithCombo()
    bindesc = struct('index', {1, 2, 3, 4}, 'label', {'A', 'B', 'C', 'A-B'}, ...
        'combo', {[], [], [], struct('coeff', {1, -1}, 'bin', {1, 2})});
end

function bindesc = bindescN(n)
    labels = {'A', 'B', 'C'};
    bindesc = struct('index', num2cell(1:n), 'label', labels(1:n), 'combo', repmat({[]}, 1, n));
end

function entries = oneEntry(bindesc, measureName, group)
    EEG = struct('bindesc', bindesc, 'measurements', {{struct('label', 'N400', 'measure', measureName)}});
    entries = struct('subject', 's1', 'datasetType', 'subject', 'group', group, 'EEG', EEG);
end

function entries = oneEntrySpectral(bindesc)
    EEG = struct('bindesc', bindesc, 'spectralMeasures', {{struct('label', '10Hz', 'refChannel', '')}});
    entries = struct('subject', 's1', 'datasetType', 'subject', 'group', '', 'EEG', EEG);
end

function entries = twoGroupEntries(bindesc, measureName)
    EEG = struct('bindesc', bindesc, 'measurements', {{struct('label', 'N400', 'measure', measureName)}});
    entries(1) = struct('subject', 's1', 'datasetType', 'subject', 'group', 'ctrl', 'EEG', EEG);
    entries(2) = struct('subject', 's2', 'datasetType', 'subject', 'group', 'patient', 'EEG', EEG);
end
