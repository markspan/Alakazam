classdef ClusterStatsReportTest < matlab.unittest.TestCase
%CLUSTERSTATSREPORTTEST  The scalp cluster report's own generated R.
%
%   NOTHING BUILT THIS REPORT BEFORE. generateClusterStatsReport writes a
%   document full of R -- heatmap, topographies, time courses and now a
%   null-distribution figure -- and no test ever called it, so none of that
%   R was ever parsed by anything. The ERP report has had a parse oracle
%   for a while and it has already caught two separate mistakes; this file
%   gives the cluster report the same guard.
%
%   The parse case skips itself when Rscript is absent, so a machine
%   without R loses that one assertion rather than the file.
%
%   Run with: runtests('tests/ClusterStatsReportTest.m').
%
%   See also GENERATECLUSTERSTATSREPORT, QUARTOREPORTRSYNTAXTEST.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'IO')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Support')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'tests')));
        end
    end

    methods (Access = private)
        function summary = summaryFixture(~, correctm, withMass)
        %SUMMARYFIXTURE  A ClusterStats-shaped summary, enough for the
        %   report to build. WITHMASS false models the TFCE case, where a
        %   cluster has no mass to report.
            if withMass
                masses = {41.7, -12.3};
            else
                masses = {NaN, NaN};
            end
            summary = struct();
            summary.contrast = struct('mode', 'paired', 'binA', 'Rare', 'binB', 'Frequent');
            summary.nSubjects = 18;
            summary.opts = struct('correctm', correctm, 'clusteralpha', 0.05, ...
                'alpha', 0.05, 'numrandomization', 1000, 'tail', 0, ...
                'minnbchan', 0, 'statistic', 'depsamplesT');
            summary.clusters = struct( ...
                'sign', {'positive', 'negative'}, ...
                'pValue', {0.012, 0.34}, ...
                'significant', {true, false}, ...
                'channels', {{'Cz', 'Pz'}, {'Fz'}}, ...
                'timeRangeMs', {[300 460], [120 180]}, ...
                'nPoints', {84, 19}, ...
                'clusterIndex', {1, 1}, ...
                'clusterStat', masses);
        end

        function txt = build(testCase, correctm, withMass)
            txt = generateClusterStatsReport(testCase.summaryFixture(correctm, withMass), ...
                'stat.csv', 'wave.csv', 'outline.csv', 'null.csv');
        end
    end

    methods (Test)
        function everyEmittedChunkParses(testCase)
        %EVERYEMITTEDCHUNKPARSES  R's own parser on the whole document.
            testCase.assumeTrue(~isempty(ReportFixtures.rscriptExe()), ...
                'Rscript not found; skipping the generated-R parse check.');

            for correctm = {'cluster', 'tfce'}
                txt = testCase.build(correctm{1}, strcmp(correctm{1}, 'cluster'));
                outcome = parseGeneratedR(txt);
                testCase.verifyEqual(outcome, 'PARSE-OK', ...
                    sprintf('The %s report emitted R that R refuses to parse.', correctm{1}));
            end
        end

        function theNullDistributionSectionIsPresent(testCase)
            txt = testCase.build('cluster', true);
            testCase.verifySubstring(txt, 'label: null-distribution');
            testCase.verifySubstring(txt, 'cluster mass under relabelling');
        end

        function theClusterExtentCaveatIsStated(testCase)
        %THECLUSTEREXTENTCAVEATISSTATED  A cluster p-value says an effect
        %   exists somewhere in the cluster, not where it starts or stops.
        %   The report has to say so, because the figures above it look
        %   exactly like claims about onset and topography.
            txt = testCase.build('cluster', true);
            testCase.verifySubstring(txt, 'Sassenhagen');
            testCase.verifySubstring(txt, 'should not be read as estimates');
        end

        function eachTailGetsItsOwnPanel(testCase)
        %EACHTAILGETSITSOWNPANEL  Overlaying the two would put a negative
        %   cluster mass on the positive null it was never compared with.
            txt = testCase.build('cluster', true);
            testCase.verifySubstring(txt, 'facet_wrap(~ tail');
        end
    end
end

function outcome = parseGeneratedR(qmdText)
%PARSEGENERATEDR  'PARSE-OK', or R's own complaint about the document.
    chunks = ReportFixtures.rChunks(qmdText);
    script = [tempname '.R'];
    fid = fopen(script, 'w');  fwrite(fid, strjoin(chunks, newline));  fclose(fid);

    driver = [tempname '.R'];
    fid = fopen(driver, 'w');
    fprintf(fid, 'r <- tryCatch({parse("%s"); "PARSE-OK"}, error = function(e) conditionMessage(e))\n', ...
        strrep(script, '\', '/'));
    fprintf(fid, 'cat(r)\n');
    fclose(fid);

    [~, out] = system(sprintf('"%s" --vanilla "%s"', ReportFixtures.rscriptExe(), driver));
    outcome = regexprep(strtrim(out), '\s+', ' ');
    delete(script); delete(driver);
end
