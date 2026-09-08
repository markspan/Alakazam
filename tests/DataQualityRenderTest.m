classdef DataQualityRenderTest < matlab.unittest.TestCase
%DATAQUALITYRENDERTEST  The data-quality report's own R, executed against
%   data whose answer is known in closed form.
%
%   WHY A RENDER AND NOT A TEXT ASSERTION. Every other data-quality test
%   reasons about the generated .qmd as MATLAB text: it can pin which
%   section was emitted and which literals it carries, and it is blind to
%   whether the R inside computes anything, let alone the right thing. The
%   dependability section fits a mixed model, reads variance components out
%   of it and turns them into a trial count an analyst may act on. A
%   substring check cannot tell a correct decomposition from one that reads
%   the residual variance where it meant the person variance, and both
%   render into a table that looks equally authoritative.
%
%   GROUND TRUTH, NOT A REGRESSION BASELINE. Single-trial values are built
%   from a known between-person effect and a known within-person spread, so
%   the realised variance components are computable here in MATLAB and
%     phi(n) = var_p / (var_p + var_e / n)
%   is arithmetic. The test compares the report's number against that,
%   which is why it would catch a wrong decomposition rather than merely
%   noticing that the number changed.
%
%   The REALISED components are the truth, not the ones the data was
%   generated from: with twenty people the sampling error on a between-
%   person variance is large (this fixture's realised value is nearly twice
%   its nominal one), and an estimator that recovered the nominal value
%   would be the broken one.
%
%   Skips cleanly when R, Quarto or the report's packages are missing, the
%   same guards QuartoReportRenderTest uses, so no unit test can reach the
%   network through the setup chunk's install.packages() branch.
%
%   Run with: runtests('tests/DataQualityRenderTest.m').
%
%   See also GENERATEDATAQUALITYREPORT, QUARTOREPORTRENDERTEST.

    properties
        Folder
        Truth
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'IO'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'tests'), fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end

        function requireTools(testCase)
            testCase.assumeTrue( ...
                ~isempty(ReportFixtures.rscriptExe()) && ~isempty(ReportFixtures.quartoExe()), ...
                'R and/or Quarto not found; skipping the data-quality render.');
            testCase.assumeTrue(ReportFixtures.rPackagesPresent({'tidyverse', 'gt', 'lme4'}), ...
                ['tidyverse, gt or lme4 is not installed; skipping rather than letting ' ...
                 'the setup chunk''s own install.packages() branch reach the network.']);
        end
    end

    methods (Test, TestTags = {'Slow', 'External'})
        function dependabilityMatchesItsClosedForm(testCase)
            temporary = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            [truth, measureName] = testCase.writeKnownVarianceMeasures(temporary.Folder);

            html = testCase.renderReport(temporary.Folder, measureName);
            text = fileread(html);

            reported = regexp(text, 'at (\d\.\d+) with ([\d.]+) trials per person', ...
                'tokens', 'once');
            testCase.assertNotEmpty(reported, sprintf( ...
                'The dependability sentence is missing from the rendered report: %s', html));

            testCase.verifyEqual(str2double(reported{1}), truth.phi, 'AbsTol', 0.005, ...
                'The reported dependability does not match its closed form.');
            testCase.verifyEqual(str2double(reported{2}), truth.nTrials, 'AbsTol', 0.05, ...
                'The reported trials per person is not the number in the file.');

            needed = regexp(text, 'take about (\d+) trials per person', 'tokens', 'once');
            testCase.assertNotEmpty(needed, 'The trials-to-reach-.80 sentence is missing.');
            testCase.verifyEqual(str2double(needed{1}), truth.neededFor80, 'AbsTol', 1, ...
                'The trial count for a dependability of .80 does not match its closed form.');
        end

        function noMeasureFileSaysSoAndNamesTheFix(testCase)
        %NOMEASUREFILESAYSSOANDNAMESTHEFIX  The common case: a workspace
        %   that never ran Measure on epoched data. The section has to say
        %   what is missing and how to produce it, rather than vanishing,
        %   because a reader cannot tell an absent section from an absent
        %   feature.
            temporary = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            html = testCase.renderReport(temporary.Folder, '');
            text = fileread(html);

            testCase.verifySubstring(text, 'Dependability');
            testCase.verifySubstring(text, 'epoched');
            testCase.verifyEmpty(strfind(text, 'least dependable'), ...
                'Nothing was fitted, so no result should be narrated.'); %#ok<STRIFCND>
        end
    end

    methods (Access = private)
        function [truth, measureName] = writeKnownVarianceMeasures(~, folder)
        %WRITEKNOWNVARIANCEMEASURES  Single-trial values with a known
        %   decomposition, and the closed-form answers for them.
            rng(11);
            nPeople = 20;
            nTrials = 40;
            personEffect = 2 * randn(1, nPeople);       % sd 2 between people
            values = zeros(nPeople, nTrials);
            for p = 1:nPeople
                for t = 1:nTrials
                    values(p, t) = 5 + personEffect(p) + 5 * randn();   % sd 5 within
                end
            end

            % The realised components, by the method of moments, which is
            % what a correct mixed-model fit has to recover on balanced data.
            varE = mean(var(values, 0, 2));
            varP = var(mean(values, 2)) - varE / nTrials;
            truth = struct( ...
                'phi', varP / (varP + varE / nTrials), ...
                'nTrials', nTrials, ...
                'neededFor80', ceil((varE * 0.80) / (varP * 0.20)));

            measureName = 'dq_measures.csv';
            fid = fopen(fullfile(folder, measureName), 'w');
            closeFile = onCleanup(@() fclose(fid));
            fprintf(fid, ['dataset,dataset_type,group,person_id,session,trial,bin,channel,' ...
                'window,measure_type,window_start_ms,window_stop_ms,value\n']);
            for p = 1:nPeople
                for t = 1:nTrials
                    fprintf(fid, ['sub%02d,subject,,p%02d,,%d,Target,Cz,N400,' ...
                        'mean_amplitude,300,500,%.6f\n'], p, p, t, values(p, t));
                end
            end
        end

        function html = renderReport(testCase, folder, measureName)
        %RENDERREPORT  The whole document, through the real generator and
        %   the real renderQuartoReport.
            entries = testCase.qualityEntries();
            stem = fullfile(folder, 'dq');
            [summaryCsv, trialCsv, smeCsv] = exportDataQualityCSVs(entries, stem);
            [~, s] = fileparts(summaryCsv);
            [~, t] = fileparts(trialCsv);
            [~, m] = fileparts(smeCsv);

            qmd = generateDataQualityReport(entries, [s '.csv'], [t '.csv'], [m '.csv'], ...
                measureName);
            qmdFile = fullfile(folder, 'dq.qmd');
            writeQmdFile(qmdFile, qmd, 'Alakazam:DataQualityRenderTest');

            [html, errorMessage] = renderQuartoReport(qmdFile);
            testCase.assertEmpty(errorMessage, sprintf( ...
                'quarto could not render the data-quality report:\n%s', errorMessage));
        end

        function entries = qualityEntries(~)
        %QUALITYENTRIES  Two subjects in the shape collectDataQualityEntries
        %   returns, so the rest of the report has something to narrate.
            entries = struct('subject', {}, 'group', {}, 'session', {}, 'quality', {});
            for s = 1:2
                EEG = makeTestEEG('trials', 8, 'nbchan', 2);
                EEG.bindesc = struct('label', {'A', 'B'}, 'index', {1, 2}, ...
                    'trials', {1:4, 5:8});
                EEG.data(:, :, s) = NaN;
                entries(s) = struct('subject', sprintf('s%02d', s), 'group', '', ...
                    'session', '', 'quality', dataQualityMetrics(EEG));
            end
        end
    end
end
