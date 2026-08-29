classdef QuartoReportPersonGroupingTest < matlab.unittest.TestCase
%QUARTOREPORTPERSONGROUPINGTEST  The random effect is grouped by the
%   person, not by the recording.
%
%   WHY THIS IS ITS OWN FILE. Until sessions existed, one recording was one
%   subject: WorkSpace.personFor falls back to the recording's own name, so
%   (1 + bin | dataset) was right by accident rather than by design. The
%   moment one person contributes two sessions it stops being right, and
%   stops loudly: lme4 fits happily, the output looks entirely healthy, and
%   the degrees of freedom are inflated because one person's two visits
%   were counted as two independent subjects.
%
%   There is no way to notice that from a rendered report, which is why the
%   change is pinned here instead. Two things are being held down. The
%   emitted models must group by person_id, and a single-session study must
%   be UNCHANGED by that -- person_id and dataset are then the same column,
%   so every result published from an earlier version still stands.
%
%   Run with: runtests('tests/QuartoReportPersonGroupingTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
        %ADDSOURCETOPATH  src/IO (generateQuartoReport + the +ReportSections
        %   package), src/Support (measureRowTypes and friends) and the
        %   tests folder itself, so ReportFixtures resolves however the
        %   suite was launched. Same three as every sibling report test.
            here = fileparts(mfilename('fullpath'));
            root = fileparts(here);
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'IO')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Support')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(here));
        end
    end

    methods (Test)
        % ---- the models --------------------------------------------------
        function theWithinModelGroupsByPerson(testCase)
            qmd = generateQuartoReport(ReportFixtures.erpEntries( ...
                'Bindesc', ReportFixtures.bindesc({'A', 'B', 'C'})), 'x.csv');

            testCase.verifySubstring(qmd, 'value ~ bin + (1 + bin | person_id)');
            testCase.verifySubstring(qmd, 'value ~ bin + (1 | person_id)');
        end

        function theMixedModelGroupsByPerson(testCase)
            qmd = generateQuartoReport(ReportFixtures.erpEntries( ...
                'Bindesc', ReportFixtures.bindesc({'A', 'B', 'C'}), ...
                'Groups', {'young', 'young', 'old', 'old'}), 'x.csv');

            testCase.verifySubstring(qmd, 'value ~ bin * group + (1 + bin | person_id)');
            testCase.verifySubstring(qmd, 'value ~ bin * group + (1 | person_id)');
        end

        function noModelIsStillGroupedByTheRecording(testCase)
        %NOMODELISSTILLGROUPEDBYTHERECORDING  The regression guard. A new
        %   section copied from an old one would reintroduce the bug
        %   silently, and every other assertion here would still pass.
            for entries = {ReportFixtures.erpEntries('Bindesc', ReportFixtures.bindesc({'A', 'B', 'C'})), ...
                    ReportFixtures.erpEntries('Bindesc', ReportFixtures.bindesc({'A', 'B', 'C'}), ...
                        'Groups', {'young', 'young', 'old', 'old'})}
                qmd = generateQuartoReport(entries{1}, 'x.csv');

                % Specifically the RANDOM-EFFECT form. A bare "| dataset)"
                % would also match the Friedman check below, which stays on
                % the recording deliberately.
                testCase.verifyEmpty(strfind(qmd, '(1 + bin | dataset)'), ...
                    'A random slope is still grouped by the recording.'); %#ok<STREMP>
                testCase.verifyEmpty(strfind(qmd, '(1 | dataset)'), ...
                    'A random intercept is still grouped by the recording.'); %#ok<STREMP>
            end
        end

        % ---- unchanged for a single-session study -------------------------
        function personDefaultsToTheRecording(testCase)
        %PERSONDEFAULTSTOTHERECORDING  The fixture models WorkSpace.personFor's
        %   own default. If this drifts, the test below proves nothing.
            entries = ReportFixtures.erpEntries();

            testCase.verifyEqual({entries.person}, {entries.subject});
        end

        function theCsvPersonColumnMatchesTheDatasetColumn(testCase)
        %THECSVPERSONCOLUMNMATCHESTHEDATASETCOLUMN  The concrete statement
        %   of "nothing moves". Grouping by person_id rather than dataset
        %   can only change a fit if the two columns differ, and for a
        %   single-session export they do not.
            folder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture()).Folder;
            [~, csvFile] = ReportFixtures.writeReport( ...
                ReportFixtures.erpEntries(), folder, 'single_session');

            datasets = ReportFixtures.csvColumn(csvFile, 'dataset');
            persons = ReportFixtures.csvColumn(csvFile, 'person_id');

            testCase.assertNotEmpty(datasets);
            testCase.verifyEqual(persons, datasets);
        end

        function repeatedSessionsMakeTheColumnsDiffer(testCase)
        %REPEATEDSESSIONSMAKETHECOLUMNSDIFFER  The other half: the test
        %   above is only meaningful if the columns CAN differ. Here one
        %   person contributes two recordings, which is exactly the case
        %   grouping by dataset would get wrong.
            folder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture()).Folder;
            entries = ReportFixtures.erpEntries( ...
                'Groups', {'', '', '', ''}, ...
                'Subjects', {'a_pre', 'a_post', 'b_pre', 'b_post'}, ...
                'Persons', {'a', 'a', 'b', 'b'}, ...
                'Sessions', {'pre', 'post', 'pre', 'post'});
            [~, csvFile] = ReportFixtures.writeReport(entries, folder, 'two_sessions');

            datasets = ReportFixtures.csvColumn(csvFile, 'dataset');
            persons = ReportFixtures.csvColumn(csvFile, 'person_id');

            testCase.verifyNotEqual(persons, datasets);
            testCase.verifyEqual(numel(unique(persons)), 2);
            testCase.verifyEqual(numel(unique(datasets)), 4);
        end

        % ---- the preamble -------------------------------------------------
        function thePreambleFallsBackToTheRecording(testCase)
        %THEPREAMBLEFALLSBACKTOTHERECORDING  A CSV written before person_id
        %   existed, or one with the column left blank, must still render:
        %   person then falls back to the recording, which is what
        %   personFor itself does when nobody has said otherwise.
            qmd = generateQuartoReport(ReportFixtures.erpEntries(), 'x.csv');

            testCase.verifySubstring(qmd, 'if (!"person_id" %in% names(dat))');
            testCase.verifySubstring(qmd, 'if (!"session" %in% names(dat))');
            testCase.verifySubstring(qmd, 'as.character(dataset), person_id)');
        end

        % ---- the deliberate exception --------------------------------------
        function theFriedmanCheckStaysOnTheRecording(testCase)
        %THEFRIEDMANCHECKSTAYSONTHERECORDING  Not an oversight. A rank test
        %   over a subject x bin table needs one value per cell, which a
        %   person with two sessions does not have. It is a robustness check
        %   on the recordings; the mixed model above is the statement about
        %   people. Pinned so it is not "corrected" to match the model.
            qmd = generateQuartoReport(ReportFixtures.erpEntries( ...
                'Bindesc', ReportFixtures.bindesc({'A', 'B', 'C'})), 'x.csv');

            testCase.verifySubstring(qmd, 'friedman_test(data = d_complete, value ~ bin | dataset)');
        end
    end
end
