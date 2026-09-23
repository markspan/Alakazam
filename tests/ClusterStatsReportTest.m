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
                fullfile(root, 'src', 'Reports')));
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
            % FieldTrip's own stat, as ClusterStats keeps it: the report reads
            % the size of the tested space off it to say how much of that
            % space each cluster covers.
            summary.stat = struct('label', {{'Cz', 'Pz', 'Fz', 'Oz'}}, ...
                'time', linspace(-0.2, 0.8, 251));
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

        function theAlphaIsASingleBackslashInTheDocument(testCase)
        %THEALPHAISASINGLEBACKSLASHINTHEDOCUMENT  A wrong escape here does
        %   not fail anything: the document renders, and prints "\alpha" as
        %   text where the letter should be. It was written as a sprintf
        %   argument, where '$\\alpha$' passes through untouched, and the
        %   reported symptom was exactly that in the finished report.
            for correctm = {'cluster', 'tfce'}
                txt = testCase.build(correctm{1}, strcmp(correctm{1}, 'cluster'));
                testCase.verifySubstring(txt, '$\alpha$');
                testCase.verifyFalse(contains(txt, '\\alpha'), ...
                    sprintf('The %s report doubled the backslash before alpha.', correctm{1}));
            end
        end

        function tfceReportsNoClusterFormingThreshold(testCase)
        %TFCEREPORTSNOCLUSTERFORMINGTHRESHOLD  clusteralpha is ignored for
        %   TFCE (see ClusterStats' own options), so printing it described a
        %   threshold the test never applied and invited the reader to report
        %   one that had no effect on the result.
            tfce = testCase.build('tfce', false);
            cluster = testCase.build('cluster', true);

            testCase.verifyFalse(contains(tfce, 'cluster-forming *p* <'), ...
                'TFCE names no cluster-forming threshold.');
            testCase.verifySubstring(tfce, 'no cluster-forming threshold is chosen');
            testCase.verifySubstring(cluster, 'cluster-forming *p* < .05', ...
                'The classic recipe still reports the threshold it did use.');
        end

        function theClusterSectionDoesNotPromiseWhereAndWhen(testCase)
        %THECLUSTERSECTIONDOESNOTPROMISEWHEREANDWHEN  The heading used to read
        %   "Where and When: the Strongest Clusters", directly above a
        %   sentence listing channels and a time range, which is precisely
        %   the reading the test cannot support. The caveat was in the
        %   document but further down, so the claim came first.
            txt = testCase.build('cluster', true);

            testCase.verifyFalse(contains(txt, 'Where and When'), ...
                'The heading no longer promises a localisation.');
            testCase.verifySubstring(txt, '## The Strongest Clusters');
            caveat = strfind(txt, 'Sassenhagen');
            heading = strfind(txt, '## The Strongest Clusters');
            testCase.verifyTrue(any(caveat > heading(1) & caveat < heading(1) + 800), ...
                'The caveat sits with the claim rather than in a later section.');
        end

        function theReportSaysWhatCanBeConcludedNotOnlyWhatCannot(testCase)
        %THEREPORTSAYSWHATCANBECONCLUDEDNOTONLYWHATCANNOT  The Sassenhagen
        %   caveat tells a reader what a cluster does not mean, which on its
        %   own leaves them with a significant result and no sentence they
        %   are allowed to write. The positive counterpart has to be there
        %   too: what the test does license, and how a claim about where or
        %   when is bought (by restricting the test in advance).
            txt = testCase.build('cluster', true);

            testCase.verifySubstring(txt, 'licenses you to say');
            testCase.verifySubstring(txt, 'differ somewhere in the space that was tested');
            testCase.verifySubstring(txt, 'restricting the test in advance');
            testCase.verifySubstring(txt, 'is not evidence that the conditions do not differ');
        end

        function aClusterSaysHowMuchOfTheSpaceItCovers(testCase)
            txt = testCase.build('cluster', true);

            testCase.verifySubstring(txt, 'It covers 2 of the 4 channel(s) tested, and 160 of the 1000 ms.');
        end

        function aClusterCoveringMostOfTheSpaceSaysSo(testCase)
        %ACLUSTERCOVERINGMOSTOFTHESPACESAYSSO  The case that is over-read:
        %   nearly every channel and most of the epoch, where the extent
        %   carries almost no information at all.
            summary = testCase.summaryFixture('cluster', true);
            summary.clusters(1).channels = {'Cz', 'Pz', 'Fz', 'Oz'};
            summary.clusters(1).timeRangeMs = [210 795];

            txt = generateClusterStatsReport(summary, 'stat.csv', 'wave.csv', ...
                'outline.csv', 'null.csv');

            testCase.verifySubstring(txt, 'It covers 4 of the 4 channel(s) tested, and 585 of the 1000 ms.');
            testCase.verifySubstring(txt, 'most of the space the test looked at');
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
