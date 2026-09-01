classdef SourceEstimateReportTest < matlab.unittest.TestCase
%SOURCEESTIMATEREPORTTEST  The "Source Estimate (Exploratory)" report
%   section: ReportSections.sourceEstimateSection's own pure-markdown
%   text, generateQuartoReport's new optional third argument, and
%   generateSourceEstimateReportAssets' own early-outs plus one full
%   end-to-end render against a REAL FieldTrip template.
%
%   MOST OF THIS FILE NEEDS NO FIELDTRIP AT ALL: sourceEstimateSection is
%   pure text assembly from already-computed numbers, and every early-out
%   in generateSourceEstimateReportAssets (no datasetType, no grand
%   average, a non-scalp-positioned dataset) is a decision made before
%   TransTools.isFieldTripAvailable is ever consulted -- see that
%   function's own header for why the checks are ordered that way. Only
%   theFullPipelineRendersRealSnapshots needs FieldTrip, and it is
%   genuinely slow (BuildSourceForwardModel builds a real leadfield over
%   FieldTrip's own ~20000-vertex template, "tens of seconds upwards" per
%   its own header) -- there is no synthetic shortcut for THAT function
%   the way SourceInverseTest's forwardFixture is for InverseSolution
%   alone, since the point of this one test is to exercise the real
%   template end to end at least once.
%
%   Run with: runtests('tests/SourceEstimateReportTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'IO')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src')));
        end
    end

    methods (Test)
        % ---- sourceEstimateSection: pure text, no FieldTrip needed -------
        function emptyAssetsProduceNoSection(testCase)
            testCase.verifyEqual(ReportSections.sourceEstimateSection( ...
                SourceEstimateReportTest.emptyAssets()), '');
        end

        function sloretaFitIsShownAsNotApplicable(testCase)
        %SLORETAFITISSHOWNASNOTAPPLICABLE  sLORETA reports no residual
        %   variance (NaN) because its filter output is a standardized
        %   statistic rather than a current -- see
        %   TransTools.InverseSolution. The table must say so rather than
        %   print "NaN%", which reads as a failed computation.
            assets = SourceEstimateReportTest.emptyAssets();
            assets(1) = struct('BinLabel', 'Target', 'Method', 'sloreta', ...
                'MethodLabel', 'sLORETA (standardized)', 'ImagePath', 'images/x.png', ...
                'ResidualVariance', NaN, 'InstantMs', 200);

            text = ReportSections.sourceEstimateSection(assets);

            testCase.verifySubstring(text, '| n/a |');
            testCase.verifyEmpty(strfind(text, 'NaN'), ...
                'A NaN reached the rendered table.');
        end

        function sectionListsEveryBinMethodAndFitPercentage(testCase)
            assets = SourceEstimateReportTest.twoBinsTwoMethodsAssets();
            text = ReportSections.sourceEstimateSection(assets);

            testCase.verifySubstring(text, '## Source Estimate (Exploratory)');
            testCase.verifySubstring(text, '### Target');
            testCase.verifySubstring(text, '### Standard');
            testCase.verifySubstring(text, 'dSPM (noise-normalized)');
            testCase.verifySubstring(text, 'eLORETA (source amplitude)');
            % ResidualVariance 0.09 -> 91% variance explained, 0.30 -> 70%.
            testCase.verifySubstring(text, '91%');
            testCase.verifySubstring(text, '70%');
            testCase.verifySubstring(text, '::: {.panel-tabset}');
            testCase.verifySubstring(text, ':::');
        end

        function imageLinkIsAngleBracketed(testCase)
        %IMAGELINKISANGLEBRACKETED  The link destination is wrapped in
        %   <...>, CommonMark's own escape for a destination containing
        %   spaces or parentheses -- see the section builder's own header
        %   for why ImagePath (built from the analyst's own export file
        %   name) cannot be trusted as bare, unescaped Markdown text.
            assets = SourceEstimateReportTest.twoBinsTwoMethodsAssets();
            text = ReportSections.sourceEstimateSection(assets);
            testCase.verifySubstring(text, '(<images/source_bin1_mne.png>)');
        end

        function specialCharactersInLabelsAreEscaped(testCase)
        %SPECIALCHARACTERSINLABELSAREESCAPED  A bin label an analyst typed
        %   with a markdown-special character must not corrupt the
        %   generated heading -- the same hazard ReportSections.mdLit
        %   exists to prevent everywhere else in this package.
            assets = SourceEstimateReportTest.emptyAssets();
            assets(1) = struct('BinLabel', 'A [vs] B', 'Method', 'mne', ...
                'MethodLabel', 'dSPM (noise-normalized)', 'ImagePath', 'images/x.png', ...
                'ResidualVariance', 0.1, 'InstantMs', 200);
            text = ReportSections.sourceEstimateSection(assets);
            testCase.verifySubstring(text, 'A \[vs\] B');
        end

        % ---- generateQuartoReport: the new argument is truly optional ----
        function omittingSourceEstimatesReproducesThePreviousReportExactly(testCase)
        %OMITTINGSOURCEESTIMATESREPRODUCESTHEPREVIOUSREPORTEXACTLY  Pins
        %   backward compatibility: every pre-existing call site passes
        %   only two arguments, and must keep getting byte-for-byte the
        %   same document it always has.
            entries = ReportFixtures.erpEntries();
            twoArg = generateQuartoReport(entries, 'x.csv');
            threeArgEmpty = generateQuartoReport(entries, 'x.csv', SourceEstimateReportTest.emptyAssets());
            threeArgAbsent = generateQuartoReport(entries, 'x.csv', []);

            testCase.verifyEqual(threeArgEmpty, twoArg);
            testCase.verifyEqual(threeArgAbsent, twoArg);
            testCase.verifyFalse(contains(twoArg, 'Source Estimate'), ...
                'The old two-argument call must not grow a new section on its own.');
        end

        function nonEmptySourceEstimatesAppendTheSourceEstimateSection(testCase)
            entries = ReportFixtures.erpEntries();
            assets = SourceEstimateReportTest.twoBinsTwoMethodsAssets();

            qmd = generateQuartoReport(entries, 'x.csv', assets);

            testCase.verifySubstring(qmd, '## Source Estimate (Exploratory)');
            testCase.verifySubstring(qmd, 'dSPM (noise-normalized)');
            % Appended AFTER the statistical summary, not interleaved with
            % it -- see generateQuartoReport's own comment for why.
            summaryPos = strfind(qmd, '## Summary Across All Tests');
            sourcePos  = strfind(qmd, '## Source Estimate (Exploratory)');
            testCase.verifyGreaterThan(sourcePos, summaryPos);
        end

        % ---- generateSourceEstimateReportAssets: early-outs, no FieldTrip -
        function noDatasetTypeFieldReturnsEmpty(testCase)
            entries = struct('EEG', struct('data', 1));
            assets = generateSourceEstimateReportAssets(entries, tempname());
            testCase.verifyEmpty(assets);
        end

        function noGrandAverageEntryReturnsEmpty(testCase)
            entries = struct('datasetType', {'subject', 'subject'}, ...
                'EEG', {struct('data', 1), struct('data', 1)});
            assets = generateSourceEstimateReportAssets(entries, tempname());
            testCase.verifyEmpty(assets);
        end

        function nonScalpPositionedGrandAverageReturnsEmpty(testCase)
        %NONSCALPPOSITIONEDGRANDAVERAGERETURNSEMPTY  A grand average
        %   present but missing .ScalpChanlocs/.ScalpHasPos/.data (an
        %   unusual export, or one predating those fields) must not error
        %   its way out of the rest of the report.
            entries = struct('datasetType', {'grand_average'}, 'EEG', {struct('id', 'GA')});
            assets = generateSourceEstimateReportAssets(entries, tempname());
            testCase.verifyEmpty(assets);
        end

        % ---- full pipeline: needs a real FieldTrip install ---------------
        function theFullPipelineRendersRealSnapshots(testCase)
        %THEFULLPIPELINERENDERSREALSNAPSHOTS  End to end, against
        %   FieldTrip's REAL template BEM/electrodes/cortical sheet (not
        %   SourceInverseTest's synthetic leadfield, which exercises
        %   InverseSolution alone, not BuildSourceForwardModel): two bins,
        %   two methods, real PNGs actually written to disk, with the
        %   fields sourceEstimateSection needs all populated sensibly. A
        %   handful of standard 10-20 labels is used so FieldTrip's own
        %   10-5 template is virtually guaranteed to resolve every one of
        %   them -- see BuildSourceForwardModel's own header for the
        %   "look up by label, drop anything unresolved" contract this
        %   relies on.
            FieldTripFixtures.require(testCase);
            imagesDir = fullfile(testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture()).Folder, 'ga_images');

            labels = {'Fz', 'Cz', 'Pz', 'Oz', 'Fp1', 'Fp2', 'F3', 'F4', ...
                      'C3', 'C4', 'P3', 'P4', 'O1', 'O2', 'T7', 'T8'};
            nChan = numel(labels);
            nTime = 15;
            nBins = 2;

            rng(7);
            eeg = struct();
            eeg.ScalpChanlocs = struct('labels', labels);
            eeg.ScalpHasPos   = true(nChan, 1);
            eeg.data          = randn(nChan, nTime, nBins) * 1e-6;
            eeg.times         = linspace(-100, 300, nTime);
            eeg.bindesc       = struct('index', {1, 2}, 'label', {'Target', 'Standard'}, ...
                                        'combo', {[], []});

            entries = struct('datasetType', {'grand_average'}, 'EEG', {eeg});

            assets = FieldTripFixtures.quietly(@() ...
                generateSourceEstimateReportAssets(entries, imagesDir, {'mne', 'eloreta'}));

            testCase.verifyNumElements(assets, nBins * 2, ...
                'Expected one row per (bin, method): 2 bins x 2 methods.');
            testCase.verifyEqual(unique({assets.BinLabel}, 'stable'), {'Target', 'Standard'});
            testCase.verifyEqual(unique({assets.Method}, 'stable'), {'mne', 'eloreta'});

            for k = 1:numel(assets)
                imgFile = fullfile(imagesDir, extractAfter(assets(k).ImagePath, '/'));
                testCase.verifyTrue(isfile(imgFile), ...
                    sprintf('Expected a PNG at %s for %s/%s.', imgFile, assets(k).BinLabel, assets(k).Method));
                testCase.verifyTrue(isfinite(assets(k).ResidualVariance));
                testCase.verifyNotEmpty(assets(k).MethodLabel);
                testCase.verifyTrue(ismember(assets(k).InstantMs, eeg.times), ...
                    'InstantMs must be one of the actual sample latencies given.');
            end

            % Feed straight into the text section too, the same way
            % onExportMeasurements does via generateQuartoReport -- a real
            % assets struct renders without erroring against the exact
            % shape this function actually produces, not just the
            % hand-built fixture the other tests above use.
            text = ReportSections.sourceEstimateSection(assets);
            testCase.verifySubstring(text, '## Source Estimate (Exploratory)');
            testCase.verifySubstring(text, '### Target');
        end
    end

    methods (Static, Access = private)
        function assets = emptyAssets()
            assets = struct('BinLabel', {}, 'Method', {}, 'MethodLabel', {}, ...
                'ImagePath', {}, 'ResidualVariance', {}, 'InstantMs', {});
        end

        function assets = twoBinsTwoMethodsAssets()
        %TWOBINSTWOMETHODSASSETS  A small, deterministic, hand-built
        %   ASSETS fixture in generateSourceEstimateReportAssets' own
        %   shape, for tests that only care about sourceEstimateSection's
        %   own text assembly and so should not need FieldTrip to build one.
            assets = struct( ...
                'BinLabel',         {'Target',                      'Target',                        'Standard',                     'Standard'}, ...
                'Method',           {'mne',                         'eloreta',                        'mne',                          'eloreta'}, ...
                'MethodLabel',      {'dSPM (noise-normalized)',     'eLORETA (source amplitude)',     'dSPM (noise-normalized)',      'eLORETA (source amplitude)'}, ...
                'ImagePath',        {'images/source_bin1_mne.png',  'images/source_bin1_eloreta.png', 'images/source_bin2_mne.png',   'images/source_bin2_eloreta.png'}, ...
                'ResidualVariance', {0.09,                          0.20,                              0.30,                          0.25}, ...
                'InstantMs',        {180,                           180,                               110,                           110});
        end
    end
end
