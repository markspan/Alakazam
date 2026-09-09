classdef SourceClusterReportTest < matlab.unittest.TestCase
%SOURCECLUSTERREPORTTEST  The source cluster report: its figures, its
%   descriptions, and the claims it is careful not to make.
%
%   MOST OF THIS NEEDS NO FIELDTRIP. A summary struct is plain data, so the
%   text assembly and the cluster bookkeeping can be driven from a
%   hand-built fixture. Only the tests that render onto the real cortical
%   sheet need the template files, and those are tagged 'Slow'.
%
%   The report's job is as much to prevent over-reading as to present
%   results, so several tests here assert that particular sentences are
%   present. That is unusual and deliberate: "a significant cluster does not
%   tell you where the effect is" is not decoration, it is the correct
%   interpretation of the statistic, and a report that dropped it would be
%   misleading rather than merely terser.
%
%   Run with: runtests('tests/SourceClusterReportTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'IO'), ...
                     fullfile(root, 'src', 'Transformations')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        % ---- what the document must say -----------------------------------
        function theInterpretationCaveatComesBeforeTheResults(testCase)
        %THEINTERPRETATIONCAVEATCOMESBEFORETHERESULTS  A caveat placed after
        %   the tables is a caveat read after the tables have already been
        %   misread.
            qmd = generateSourceClusterStatsReport(testCase.summaryFixture(), ...
                testCase.assetFixture());

            caveatAt = strfind(qmd, 'an effect exists, not where it is');
            resultsAt = strfind(qmd, '## Clusters');
            testCase.assertNotEmpty(caveatAt);
            testCase.assertNotEmpty(resultsAt);
            testCase.verifyLessThan(caveatAt(1), resultsAt(1));
        end

        function theQuantitativeLimitsReachTheDocument(testCase)
        %THEQUANTITATIVELIMITSREACHTHEDOCUMENT  The two paragraphs that put
        %   numbers on the caveats. resolutionParagraph existed for a while
        %   without ever being called, so the readme described a statement
        %   no report contained; this fails if either stops being emitted.
            qmd = generateSourceClusterStatsReport(testCase.summaryFixture(), ...
                generateSourceClusterAssetsFixtureEmpty());

            testCase.verifySubstring(qmd, 'How much detail the map can carry');
            testCase.verifySubstring(qmd, 'independent values');
            testCase.verifySubstring(qmd, 'The cortical sheet affects the statistic');
            testCase.verifySubstring(qmd, '38 mm');
        end

        function theCaveatsStayOneBlockquote(testCase)
        %THECAVEATSSTAYONEBLOCKQUOTE  Each appended paragraph continues the
        %   callout it belongs to. A blank line between them would split one
        %   caveat into three and let a reader stop after the first, which
        %   is a rendering detail with a real effect on what gets read.
            qmd = generateSourceClusterStatsReport(testCase.summaryFixture(), ...
                generateSourceClusterAssetsFixtureEmpty());

            block = extractBetween(qmd, '## How to read this', '## ');
            testCase.assertNotEmpty(block, 'The caveat section could not be located.');
            lines = strsplit(block{1}, newline);
            body = lines(3:end - 2);        % past the heading, before the trailing blank
            body = body(~cellfun(@isempty, strtrim(body)));
            starts = cellfun(@(L) startsWith(strtrim(L), '>'), body);
            testCase.verifyTrue(all(starts), ...
                'Every line of the caveat block must continue the blockquote.');
        end

        function theTemplateAndSmoothnessLimitsAreStated(testCase)
            qmd = generateSourceClusterStatsReport(testCase.summaryFixture(), ...
                testCase.assetFixture());

            testCase.verifySubstring(qmd, 'head model is a template');
            testCase.verifySubstring(qmd, 'not independent');
        end

        function theMethodTableReportsWhatActuallyRan(testCase)
        %THEMETHODTABLEREPORTSWHATACTUALLYRAN  Read from summary.opts, not
        %   restated from defaults: resolveNumRandomization can raise the
        %   permutation count to exhaustive without the analyst asking, and
        %   the document has to describe the analysis that happened.
            summary = testCase.summaryFixture();
            summary.opts.numrandomization = 4096;
            summary.opts.correctm = 'tfce';

            qmd = generateSourceClusterStatsReport(summary, testCase.assetFixture());

            testCase.verifySubstring(qmd, '| Permutations | 4096 |');
            testCase.verifySubstring(qmd, 'threshold-free cluster enhancement');
            testCase.verifySubstring(qmd, 'dSPM');
            testCase.verifySubstring(qmd, 'signed, projected onto the cortical normal');
        end

        function aCombinationBinShowsItsConstituentTrialCounts(testCase)
        %ACOMBINATIONBINSHOWSITSCONSTITUENTTRIALCOUNTS  DefineBins records a
        %   difference bin's .n as text ('39-161'), not a number, because it
        %   has no single trial count. Reading it as a number crashed a
        %   completed analysis with "Non-scalar in Uniform Output" from the
        %   provenance bookkeeping, long after the statistics had finished.
        %   The text is worth more than "not recorded", so it is shown.
            summary = testCase.summaryFixture();
            summary.provenance = struct( ...
                'subjects', struct('id', {'sub01', 'sub02'}, 'file', {'', ''}, ...
                    'trials', {NaN, 210}, 'trialsText', {'39-161', ''}, ...
                    'residualVariance', {0.03, 0.04}), ...
                'software', struct('matlab', 'x', 'fieldtrip', 'y', 'alakazam', 'z'));

            qmd = generateSourceClusterStatsReport(summary, testCase.assetFixture());

            testCase.verifySubstring(qmd, '39-161');
            testCase.verifySubstring(qmd, '| 210 |');
            % A subject with no countable trials must not be reported as
            % having had zero of them.
            testCase.verifyEmpty(strfind(qmd, '| sub01 | 0 |'));
        end

        function aClusterTouchingTheWindowEdgeIsFlagged(testCase)
        %ACLUSTERTOUCHINGTHEWINDOWEDGEISFLAGGED  Its reported time range is
        %   then a property of the analysis window, not of the effect, and a
        %   reader would otherwise take it as a measured onset and offset.
            assets = testCase.assetFixture();
            assets(1).TouchesWindowEdge = true;

            qmd = generateSourceClusterStatsReport(testCase.summaryFixture(), assets);

            testCase.verifySubstring(qmd, 'reaches the edge of the tested time window');
        end

        function aClusterInsideTheWindowIsNotFlagged(testCase)
            assets = testCase.assetFixture();
            assets(1).TouchesWindowEdge = false;
            assets(2).TouchesWindowEdge = false;

            qmd = generateSourceClusterStatsReport(testCase.summaryFixture(), assets);

            testCase.verifyEmpty(strfind(qmd, 'reaches the edge of the tested time window'));
        end

        function aNullResultIsReportedAsAResult(testCase)
        %ANULLRESULTISREPORTEDASARESULT  Candidate clusters form from noise
        %   routinely, so "none survived" is a finding and must not read as
        %   a near-miss or a malfunction.
            summary = testCase.summaryFixture();
            [summary.clusters.significant] = deal(false);
            [summary.clusters.pValue] = deal(0.42);

            qmd = generateSourceClusterStatsReport(summary, ...
                generateSourceClusterAssetsFixtureEmpty());

            testCase.verifySubstring(qmd, 'none of which');
            testCase.verifySubstring(qmd, 'null result rather than');
        end

        function noClustersAtAllIsDistinguishedFromNoSignificantOnes(testCase)
            summary = testCase.summaryFixture();
            summary.clusters = summary.clusters([]);

            qmd = generateSourceClusterStatsReport(summary, ...
                generateSourceClusterAssetsFixtureEmpty());

            testCase.verifySubstring(qmd, 'no candidate clusters at all');
        end

        function imageLinksAreAngleBracketed(testCase)
        %IMAGELINKSAREANGLEBRACKETED  The images folder is named after the
        %   analyst's own export name, which may contain spaces or brackets;
        %   an unescaped ")" would silently truncate the link.
            qmd = generateSourceClusterStatsReport(testCase.summaryFixture(), ...
                testCase.assetFixture());

            testCase.verifySubstring(qmd, '](<images/cluster1_positive_map.png>)');
        end

        % ---- the permutation null -------------------------------------------
        function theNullDistributionIsShownWhenTheRunKeptOne(testCase)
        %THENULLDISTRIBUTIONISSHOWNWHENTHERUNKEPTONE  The figure the
        %   p-values were read from. Every other figure says where and when
        %   an effect was; this one is the comparison itself.
            summary = testCase.summaryFixture();
            summary.stat.posdistribution = abs(randn(1, 200)) * 100;
            summary.stat.negdistribution = -abs(randn(1, 200)) * 100;
            summary.stat.stattfce = summary.stat.stat * 500;

            [~, extras] = generateSourceClusterAssets(summary, testCase.tempImages());
            testCase.assertNotEmpty(extras.NullDistributionPath, ...
                'A run with both tails kept should have produced the figure.');

            qmd = generateSourceClusterStatsReport(summary, ...
                generateSourceClusterAssetsFixtureEmpty(), extras);

            testCase.verifySubstring(qmd, '## The permutation null');
            testCase.verifySubstring(qmd, extras.NullDistributionPath);
            testCase.verifySubstring(qmd, 'smallest p this test can report');
        end

        function noNullDistributionMeansNoFigureAndNoClaim(testCase)
        %NONULLDISTRIBUTIONMEANSNOFIGUREANDNOCLAIM  FieldTrip's own TFCE
        %   route returns no per-permutation extremes. The section then has
        %   to say why it is absent: silence would read as "this analysis
        %   had no null distribution", which is wrong.
            summary = testCase.summaryFixture();
            summary.opts.Accelerate = false;

            [~, extras] = generateSourceClusterAssets(summary, testCase.tempImages());
            testCase.verifyEmpty(extras.NullDistributionPath, ...
                'Nothing to draw, so nothing should have been drawn.');

            qmd = generateSourceClusterStatsReport(summary, ...
                generateSourceClusterAssetsFixtureEmpty(), extras);
            testCase.verifySubstring(qmd, 'does not return');
        end

        function theUnthresholdedAppendixReachesTheDocument(testCase)
        %THEUNTHRESHOLDEDAPPENDIXREACHESTHEDOCUMENT  It did not, for as long
        %   as the ribbon action called generateSourceClusterAssets with one
        %   output: the PNG was rendered into the images folder and then
        %   referenced by nothing, while the readme went on claiming the
        %   report carried it. Both halves are checked here, the generator's
        %   and the caller's.
            summary = testCase.summaryFixture();
            [~, extras] = generateSourceClusterAssets(summary, testCase.tempImages());
            testCase.assertNotEmpty(extras.UnthresholdedMapPath);

            qmd = generateSourceClusterStatsReport(summary, ...
                generateSourceClusterAssetsFixtureEmpty(), extras);
            testCase.verifySubstring(qmd, 'Appendix: the unthresholded statistic');

            % The caller, read rather than run: it needs a UI to run, and
            % the defect was exactly that it discarded the second output.
            root = fileparts(fileparts(mfilename('fullpath')));
            src = fileread(fullfile(root, 'src', '@Alakazam', 'onSourceClusterStats.m'));
            testCase.verifySubstring(src, '[assets, extras] = generateSourceClusterAssets(');
            testCase.verifySubstring(src, 'generateSourceClusterStatsReport(summary, assets, extras)');
        end

        function thePointSpreadFigureIsSkippedWithoutAForwardModel(testCase)
        %THEPOINTSPREADFIGUREISSKIPPEDWITHOUTAFORWARDMODEL  The cost decision,
        %   asserted rather than commented. The figure needs the leadfield,
        %   which takes about 18 s to build, and the analyst clicked "run a
        %   cluster test", not "spend a further 18 s on an appendix figure".
        %   So it is drawn only when the model is already cached, and the
        %   fixture's channel labels have no model behind them.
        %
        %   THE ABSENCE MUST BE SILENT IN THE DOCUMENT. A section explaining
        %   that a figure is missing because of what was in memory would be
        %   a fact about the session, not about the analysis, and belongs in
        %   no report.
            summary = testCase.summaryFixture();
            [~, extras] = generateSourceClusterAssets(summary, testCase.tempImages());

            testCase.verifyEmpty(extras.PointSpreadPath, ...
                'A figure was drawn from a forward model that was never built.');
            testCase.verifyEmpty(extras.PointSpread);

            qmd = generateSourceClusterStatsReport(summary, ...
                generateSourceClusterAssetsFixtureEmpty(), extras);
            testCase.verifyEmpty(strfind(qmd, '## What one vertex can resolve'));
        end

        function anOlderExtrasStructIsStillAcceptable(testCase)
        %ANOLDEREXTRASSTRUCTISSTILLACCEPTABLE  A summary and an extras from
        %   before the point-spread figure existed still have to render. The
        %   report reads every extras field through isfield for exactly this
        %   reason, and a missing field must produce a shorter document
        %   rather than an "Unrecognized field name" that throws away a
        %   completed analysis.
            extras = struct('UnthresholdedMapPath', 'images/u.png', ...
                'NullDistributionPath', '');

            qmd = generateSourceClusterStatsReport(testCase.summaryFixture(), ...
                generateSourceClusterAssetsFixtureEmpty(), extras);

            testCase.verifySubstring(qmd, 'Appendix: the unthresholded statistic');
            testCase.verifyEmpty(strfind(qmd, '## What one vertex can resolve'));
        end

        % ---- rendering decisions --------------------------------------------
        function onlySignificantClustersAreRenderedByDefault(testCase)
            summary = testCase.summaryFixture();
            summary.clusters(2).significant = false;

            assets = generateSourceClusterAssets(summary, testCase.tempImages(), ...
                struct('SignificantOnly', true));

            testCase.verifyNumElements(assets, 1);
            testCase.verifyTrue(assets(1).Significant);
        end

        function assetsRecordWhichClusterTheyCameFrom(testCase)
        %ASSETSRECORDWHICHCLUSTERTHEYCAMEFROM  .Index numbers the rendered
        %   figures, .SourceIndex points back into summary.clusters, and the
        %   two differ as soon as a non-significant cluster is skipped.
        %   SourceClusterStatsResultDialog lists every cluster and labels
        %   only the rendered ones, so it needs the second, not the first.
            summary = testCase.summaryFixture();
            summary.clusters(1).significant = false;

            assets = generateSourceClusterAssets(summary, testCase.tempImages(), ...
                struct('SignificantOnly', true));

            testCase.assertNumElements(assets, 1);
            testCase.verifyEqual(assets(1).Index, 1);
            testCase.verifyEqual(assets(1).SourceIndex, 2);
        end

        function everyClusterCanBeRenderedWhenAsked(testCase)
            summary = testCase.summaryFixture();
            summary.clusters(2).significant = false;

            assets = generateSourceClusterAssets(summary, testCase.tempImages(), ...
                struct('SignificantOnly', false));

            testCase.verifyNumElements(assets, 2);
        end
    end

    methods (Test, TestTags = {'Slow'})
        function thePointSpreadFigureReachesTheDocument(testCase)
        %THEPOINTSPREADFIGUREREACHESTHEDOCUMENT  The same guard, and the same
        %   defect, as theUnthresholdedAppendixReachesTheDocument: a figure
        %   rendered into the images folder and then referenced by nothing is
        %   the failure this whole extras path already had once.
        %
        %   Slow because it is the only test here that draws on the real
        %   forward model. It builds it deliberately, which is also what
        %   makes the cache warm: the assets step will not draw the figure
        %   otherwise, and that gate is asserted separately in
        %   thePointSpreadFigureIsSkippedWithoutAForwardModel.
            FieldTripFixtures.require(testCase);
            [summary, montage] = testCase.realSummaryFixture();

            imagesDir = testCase.tempImages();
            [~, extras] = FieldTripFixtures.quietly(@() ...
                generateSourceClusterAssets(summary, imagesDir));

            testCase.assertNotEmpty(extras.PointSpreadPath, sprintf( ...
                ['Nothing was drawn although the forward model for %d channels ' ...
                 'had just been built.'], numel(montage)));
            testCase.verifyEqual(exist(fullfile(imagesDir, 'point_spread.png'), 'file'), 2, ...
                'The report links to a PNG that is not on disk.');

            % The figure's own numbers travel with it, so the report can
            % quote them instead of describing the picture vaguely.
            testCase.assertNotEmpty(extras.PointSpread);
            testCase.verifyTrue(isfinite(extras.PointSpread.PeakErrorMm));
            testCase.verifyTrue(isfinite(extras.PointSpread.DispersionMm));

            qmd = generateSourceClusterStatsReport(summary, ...
                generateSourceClusterAssetsFixtureEmpty(), extras);
            testCase.verifySubstring(qmd, '## What one vertex can resolve');
            testCase.verifySubstring(qmd, extras.PointSpreadPath);
            testCase.verifySubstring(qmd, 'spatial dispersion');
            testCase.verifySubstring(qmd, sprintf('%.0f mm', extras.PointSpread.DispersionMm));

            % The claim the figure exists to support, stated beside it.
            testCase.verifySubstring(qmd, 'not a result');
            testCase.verifySubstring(qmd, 'folding of the cortex');
        end

        function thePointSpreadIsDrawnAtTheAnalysisOwnPeak(testCase)
        %THEPOINTSPREADISDRAWNATTHEANALYSISOWNPEAK  Point spread varies over
        %   the cortex, so a figure drawn at a fixed vertex could flatter or
        %   slander the result standing next to it. It has to be the peak of
        %   the cluster a reader is going to quote.
            FieldTripFixtures.require(testCase);
            [summary, ~, seed] = testCase.realSummaryFixture();

            [~, extras] = FieldTripFixtures.quietly(@() ...
                generateSourceClusterAssets(summary, testCase.tempImages()));

            testCase.assertNotEmpty(extras.PointSpread);
            testCase.verifyEqual(extras.PointSpread.Vertex, seed, ...
                ['The figure was drawn for a different vertex than the one the ' ...
                 'cluster peaks at, so it describes the resolution somewhere ' ...
                 'other than where the result is being read.']);
        end

        function descriptionsNameARegionAndACoordinate(testCase)
        %DESCRIPTIONSNAMEAREGIONANDACOORDINATE  Both, because a name is what
        %   makes a result readable and a coordinate is what makes its
        %   precision checkable -- see TransTools.DescribeCluster.
            FieldTripFixtures.require(testCase);
            sourcemodel = FieldTripFixtures.quietly(@() realSheet());

            mask = false(size(sourcemodel.pos, 1), 1);
            mask(1:400) = true;
            description = FieldTripFixtures.quietly(@() ...
                TransTools.DescribeCluster(mask, sourcemodel, 1, 'aal'));

            testCase.verifyNotEmpty(description.PeakRegion);
            testCase.verifyEqual(numel(description.PeakMni), 3);
            testCase.verifyTrue(all(isfinite(description.PeakMni)));
            testCase.verifySubstring(description.Text, 'mm');
            testCase.verifyEqual(description.NVertices, 400);
        end

        function theTemplateSheetSplitsIntoHemispheresByIndex(testCase)
        %THETEMPLATESHEETSPLITSINTOHEMISPHERESBYINDEX  The cluster map draws
        %   each hemisphere separately, and takes the first half of the
        %   vertices to be the left one. That is a property of the files
        %   FieldTrip ships, not something the code can check per call
        %   without cost, so it is checked here instead: if a future
        %   FieldTrip reordered a mesh, every map would come out with its
        %   panels mislabelled and nothing else would complain.
            FieldTripFixtures.require(testCase);
            for sheet = {'cortex_20484.surf.gii', 'cortex_8196.surf.gii', 'cortex_5124.surf.gii'}
                sm = FieldTripFixtures.quietly(@() namedSheet(sheet{1}));
                half = size(sm.pos, 1) / 2;
                testCase.verifyEqual(mod(size(sm.pos, 1), 2), 0, ...
                    sprintf('%s: an odd vertex count cannot split into hemispheres.', sheet{1}));

                inFirst = false(size(sm.pos, 1), 1);
                inFirst(1:half) = true;
                spanning = sum(any(inFirst(sm.tri), 2) & any(~inFirst(sm.tri), 2));
                testCase.verifyEqual(spanning, 0, ...
                    sprintf('%s: triangles join the two index halves.', sheet{1}));

                testCase.verifyLessThan(mean(sm.pos(1:half, 1)), 0, ...
                    sprintf('%s: the first half is not the left hemisphere.', sheet{1}));
                testCase.verifyGreaterThan(mean(sm.pos(half+1:end, 1)), 0, ...
                    sprintf('%s: the second half is not the right hemisphere.', sheet{1}));
            end
        end

        function unlabelledVerticesAreNamedNotInvented(testCase)
        %UNLABELLEDVERTICESARENAMEDNOTINVENTED  About 12% of the template
        %   sheet falls in unlabelled atlas voxels. Assigning them to a
        %   nearest neighbour would quietly widen every reported cluster, so
        %   they stay 'unlabelled'.
            FieldTripFixtures.require(testCase);
            sourcemodel = FieldTripFixtures.quietly(@() realSheet());
            [vertexLabel, ~] = FieldTripFixtures.quietly(@() ...
                TransTools.AtlasVertexLabels(sourcemodel, 'aal'));
            unlabelled = find(vertexLabel == 0, 1);
            testCase.assumeNotEmpty(unlabelled);

            mask = false(size(sourcemodel.pos, 1), 1);
            mask(unlabelled) = true;
            description = FieldTripFixtures.quietly(@() ...
                TransTools.DescribeCluster(mask, sourcemodel, unlabelled, 'aal'));

            testCase.verifyEqual(description.PeakRegion, 'unlabelled');
        end
    end

    methods (Access = private)
        function summary = summaryFixture(~)
        %SUMMARYFIXTURE  A minimal SourceClusterStats-shaped summary over a
        %   tiny synthetic sheet, so text assembly needs no FieldTrip.
            nTime = 11;
            [x, y, z] = sphere(8);
            pos = unique([x(:), y(:), z(:)], 'rows') * 50;
            % Taken from the mesh rather than assumed: sphere(n) does not
            % yield a count you can predict without checking, and an earlier
            % version of this fixture hardcoded one it did not have.
            nVertex = size(pos, 1);
            summary = struct();
            summary.sourcemodel = struct('pos', pos, 'tri', convhull(pos(:,1), pos(:,2), pos(:,3)));
            summary.vertexLabels = TransTools.SourceVertexLabels(nVertex);
            summary.times = linspace(200, 400, nTime);
            summary.nSubjects = 18;
            summary.contrast = struct('mode', 'paired', 'binA', 'Related', 'binB', 'Unrelated');
            summary.opts = struct('Method', 'mne', 'Orientation', 'normal', ...
                'correctm', 'tfce', 'numrandomization', 1000, 'alpha', 0.05, 'tail', 0, ...
                'SourceSpace', 5124);
            summary.stat = struct('stat', randn(nVertex, nTime));
            % Provenance carries the channel set, which is what lets the
            % resolution paragraph state a rank bound. Without it that
            % paragraph correctly says nothing, and a fixture missing the
            % field would make the test pass by having nothing to check.
            summary.provenance = struct('channels', ...
                {{arrayfun(@(k) sprintf('E%d', k), 1:29, 'UniformOutput', false)}});
            summary.clusters = struct( ...
                'sign', {'positive', 'negative'}, 'pValue', {0.004, 0.021}, ...
                'significant', {true, true}, ...
                'channels', {summary.vertexLabels(1:8), summary.vertexLabels(9:16)}, ...
                'timeRangeMs', {[240 320], [260 340]}, ...
                'nPoints', {40, 35}, 'clusterIndex', {1, 1});
        end

        function assets = assetFixture(testCase)
            assets = generateSourceClusterAssets(testCase.summaryFixture(), ...
                testCase.tempImages());
        end

        function [summary, montage, seed] = realSummaryFixture(testCase)
        %REALSUMMARYFIXTURE  A summary on the REAL cortical sheet, with a
        %   real 10-5 montage and a forward model already built.
        %
        %   The montage deliberately carries two channels the template
        %   cannot position (an EOG pair). That is the ordinary case, it is
        %   why provenance records .montage as well as .channels, and it is
        %   what a fixture using only placeable labels would fail to
        %   exercise: the forward-model cache is keyed on what it was asked
        %   for, so a lookup by .channels alone would miss here.
            montage = [testCase.templateMontage(), {'HEOG', 'VEOG'}];
            [~, sourcemodel, resolved] = FieldTripFixtures.quietly(@() ...
                TransTools.BuildSourceForwardModel(montage, 5124));

            n = size(sourcemodel.pos, 1);
            nTime = 11;

            % A statistic with one real spatial peak, so "the peak of the
            % strongest cluster" is a definite vertex rather than whichever
            % vertex noise happened to favour.
            seed = 1700;
            distance = vecnorm(sourcemodel.pos - sourcemodel.pos(seed, :), 2, 2);
            inCluster = find(distance < 20);

            summary = struct();
            summary.sourcemodel  = sourcemodel;
            summary.vertexLabels = TransTools.SourceVertexLabels(n);
            summary.times        = linspace(200, 400, nTime);
            summary.nSubjects    = 7;
            summary.contrast     = struct('mode', 'paired', 'binA', 'Related', ...
                'binB', 'Unrelated');
            summary.opts = struct('Method', 'mne', 'Orientation', 'normal', ...
                'correctm', 'tfce', 'numrandomization', 1000, 'alpha', 0.05, ...
                'tail', 0, 'SourceSpace', 5124, 'RegParam', 0.05, 'Accelerate', true);
            summary.stat = struct('stat', ...
                (4 * exp(-(distance / 25) .^ 2)) * ones(1, nTime));
            summary.clusters = struct('sign', {'positive'}, 'pValue', {0.004}, ...
                'significant', {true}, 'channels', {summary.vertexLabels(inCluster)}, ...
                'timeRangeMs', {[240 320]}, 'nPoints', {4 * numel(inCluster)}, ...
                'clusterIndex', {1});
            summary.provenance = struct('channels', {{resolved}}, ...
                'montage', {{montage}}, 'nChannels', numel(resolved), ...
                'software', struct('matlab', 'x', 'fieldtrip', 'y', 'alakazam', 'z'));
        end

        function labels = templateMontage(~)
        %TEMPLATEMONTAGE  Labels FieldTrip's own 10-5 template can position.
            labels = {'FP1','FP2','F7','F3','FZ','F4','F8','FC5','FC1','FC2', ...
                      'FC6','T7','C3','CZ','C4','T8','CP5','CP1','CP2','CP6', ...
                      'P7','P3','PZ','P4','P8','O1','OZ','O2','POZ'};
        end

        function dir = tempImages(testCase)
            dir = fullfile(testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture()).Folder, 'images');
        end
    end
end

% ======================================================================= %
function assets = generateSourceClusterAssetsFixtureEmpty()
%GENERATESOURCECLUSTERASSETSFIXTUREEMPTY  The empty ASSETS shape, for the
%   null-result tests where nothing is rendered.
    assets = struct('Index', {}, 'SourceIndex', {}, 'Sign', {}, 'PValue', {}, 'Significant', {}, ...
        'TimeRangeMs', {}, 'TouchesWindowEdge', {}, 'NVertices', {}, ...
        'Description', {}, 'MapPath', {}, 'TimeCoursePath', {});
end

function sourcemodel = namedSheet(name)
%NAMEDSHEET  One of FieldTrip's template cortical sheets, by file name.
    TransTools.EnsureGiftiReader();
    ftRoot = fileparts(which('ft_defaults'));
    sourcemodel = ft_read_headshape(fullfile(ftRoot, 'template', 'sourcemodel', name));
end

function sourcemodel = realSheet()
    % Guarded because a previous test class may have torn the gifti reader
    % off the path -- see TransTools.EnsureGiftiReader.
    TransTools.EnsureGiftiReader();
    ftRoot = fileparts(which('ft_defaults'));
    sourcemodel = ft_convert_units(ft_read_headshape(fullfile(ftRoot, 'template', ...
        'sourcemodel', 'cortex_20484.surf.gii')), 'mm');
end
