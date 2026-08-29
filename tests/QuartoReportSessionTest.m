classdef QuartoReportSessionTest < matlab.unittest.TestCase
%QUARTOREPORTSESSIONTEST  Session as a real factor: dispatch, formula and
%   the two things that make it safe to turn on automatically.
%
%   Session becomes a factor whenever the recordings support one -- no
%   opt-in switch, because an analyst who has labelled two sessions has
%   already described the design, and a second declaration would only be
%   an opportunity for the two to disagree. That makes two properties
%   load-bearing, and both are pinned here.
%
%   A study WITHOUT sessions must render exactly as before. Automatic
%   behaviour that changed existing reports would be a silent rewrite of
%   results nobody asked to have rewritten.
%
%   A study whose sessions cannot support the model must fall back AND SAY
%   SO. lmer's own answer to an unestimable interaction is not a refusal:
%   it returns something that looks entirely healthy.
%
%   Run with: runtests('tests/QuartoReportSessionTest.m').

    properties (Constant)
        CsvName = 'x.csv'
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
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
        % ---- dispatch ----------------------------------------------------
        function repeatedSessionsGetTheSessionSection(testCase)
            txt = QuartoReportSessionTest.withinSessions();
            labels = ReportFixtures.chunkLabels(txt);

            testCase.verifyTrue(any(startsWith(labels, 'session-')), ...
                sprintf('Expected a session- chunk, got: %s', strjoin(labels, ', ')));
            testCase.verifyFalse(any(startsWith(labels, 'anova-')), ...
                'The plain within-subjects section should have been replaced.');
        end

        function theWithinOnlyModelCrossesBinWithSession(testCase)
            txt = QuartoReportSessionTest.withinSessions();

            testCase.verifySubstring(txt, 'value ~ bin * session + (1 + bin | person_id)');
            testCase.verifySubstring(txt, 'value ~ bin * session + (1 | person_id)');
        end

        function theGroupedModelDropsTheThreeWayInteraction(testCase)
        %THEGROUPEDMODELDROPSTHETHREEWAYINTERACTION  "^2" is R for every
        %   main effect and every two-way interaction and nothing further.
        %   A bin x session x group term is rarely supportable by the
        %   number of subjects an ERP study has, and the formula states its
        %   absence rather than leaving it to be inferred.
            txt = QuartoReportSessionTest.groupedSessions();

            testCase.verifySubstring(txt, 'value ~ (bin + session + group)^2 + (1 + bin | person_id)');
            testCase.verifyEmpty(strfind(txt, 'bin * session * group'), ...
                'The three-way interaction has come back.'); %#ok<STREMP>
        end

        function theGroupedSessionSectionReplacesTheMixedOne(testCase)
            labels = ReportFixtures.chunkLabels(QuartoReportSessionTest.groupedSessions());

            testCase.verifyTrue(any(startsWith(labels, 'session-')));
            testCase.verifyFalse(any(startsWith(labels, 'mixed-')));
        end

        % ---- nothing changes without sessions ------------------------------
        function aSingleSessionStudyIsUntouched(testCase)
        %ASINGLESESSIONSTUDYISUNTOUCHED  The whole risk of making this
        %   automatic. No session chunk, no design note, and the section
        %   that always ran still runs.
            txt = generateQuartoReport(ReportFixtures.erpEntries( ...
                'Bindesc', ReportFixtures.bindesc({'A', 'B', 'C'})), ...
                QuartoReportSessionTest.CsvName);
            labels = ReportFixtures.chunkLabels(txt);

            testCase.verifyFalse(any(startsWith(labels, 'session-')));
            testCase.verifyTrue(any(startsWith(labels, 'anova-')));
            testCase.verifyEmpty(strfind(txt, '## Design'), ...
                'A study with no sessions should not carry a design note.'); %#ok<STREMP>
        end

        function twoBinsWithoutSessionsStillPair(testCase)
            labels = ReportFixtures.chunkLabels(generateQuartoReport( ...
                ReportFixtures.erpEntries('Bindesc', ReportFixtures.bindesc({'A', 'B'})), ...
                QuartoReportSessionTest.CsvName));

            testCase.verifyTrue(any(startsWith(labels, 'paired-')), ...
                sprintf('Expected the paired section, got: %s', strjoin(labels, ', ')));
        end

        % ---- falling back --------------------------------------------------
        function sessionsNobodyRepeatedFallBackAndSaySo(testCase)
        %SESSIONSNOBODYREPEATEDFALLBACKANDSAYSO  Two session labels are not
        %   a within-subject factor when nobody appears under both: session
        %   is confounded with person and the model cannot separate them.
            txt = generateQuartoReport(ReportFixtures.erpEntries( ...
                'Bindesc', ReportFixtures.bindesc({'A', 'B', 'C'}), ...
                'Groups', {'', '', '', ''}, ...
                'Subjects', {'p', 'q', 'r', 's'}, ...
                'Persons', {'p', 'q', 'r', 's'}, ...
                'Sessions', {'pre', 'post', 'pre', 'post'}), ...
                QuartoReportSessionTest.CsvName);
            labels = ReportFixtures.chunkLabels(txt);

            testCase.verifyFalse(any(startsWith(labels, 'session-')));
            testCase.verifyTrue(any(startsWith(labels, 'anova-')));
            testCase.verifySubstring(txt, 'A simpler model than the data seemed to offer');
            testCase.verifySubstring(txt, 'within subjects');
        end

        function theFallbackNoticeIsAbsentWhenNothingWasGivenUp(testCase)
            txt = QuartoReportSessionTest.withinSessions();

            testCase.verifyEmpty(strfind(txt, 'A simpler model than the data seemed to offer'), ...
                'A design that fitted fully should carry no apology for it.'); %#ok<STREMP>
        end

        % ---- strict post-hoc ------------------------------------------------
        function postHocContrastsAreGatedOnSignificance(testCase)
        %POSTHOCCONTRASTSAREGATEDONSIGNIFICANCE  At most one family, and
        %   only following a term that reached significance. A report that
        %   runs every family it can think of has spent its alpha before
        %   anyone decided what the question was.
            txt = QuartoReportSessionTest.withinSessions();

            testCase.verifySubstring(txt, 'if (!is.na(p_head) && p_head < .05) {');
            testCase.verifySubstring(txt, '} else if (!is.na(p_bin) && p_bin < .05) {');
            testCase.verifySubstring(txt, 'pairwise ~ bin | session');
            testCase.verifySubstring(txt, 'No post-hoc contrasts were run');
        end

        function onlyOneContrastFamilyCanRun(testCase)
        %ONLYONECONTRASTFAMILYCANRUN  Both emmeans calls sit in the two
        %   branches of one if/else, so exactly one of them is reachable
        %   per channel. Counting them is the cheap way to notice a third
        %   being added unconditionally later.
            txt = QuartoReportSessionTest.withinSessions();
            labels = ReportFixtures.chunkLabels(txt);
            idx = find(startsWith(labels, 'session-'), 1);
            testCase.assertNotEmpty(idx, 'No session chunk to inspect.');
            body = ReportFixtures.chunkFor(txt, labels{idx});

            testCase.verifyEqual(numel(strfind(body, 'emmeans::emmeans(')), 2, ...
                'The session section should offer exactly two mutually exclusive contrast families.');
        end

        function theAnalystIsToldHowToAddMore(testCase)
        %THEANALYSTISTOLDHOWTOADDMORE  Being strict is only defensible if
        %   the report says what to do about it.
            txt = QuartoReportSessionTest.withinSessions();

            testCase.verifySubstring(txt, '`emmeans` is loaded and the fitted model is in scope');
        end

        % ---- the design note -------------------------------------------------
        function theDesignNoteStatesTheModel(testCase)
            txt = QuartoReportSessionTest.withinSessions();

            testCase.verifySubstring(txt, '## Design');
            testCase.verifySubstring(txt, 'Session is treated as a within-subjects factor');
            testCase.verifySubstring(txt, '`bin * session`');
        end

        function onlyAThreeFactorDesignMentionsTheThreeWay(testCase)
        %ONLYATHREEFACTORDESIGNMENTIONSTHETHREEWAY  A two-factor model has
        %   no three-way interaction to omit, so describing that decision
        %   would describe one that was never available.
            testCase.verifyEmpty(strfind(QuartoReportSessionTest.withinSessions(), ...
                'deliberately omitted'), ...
                'A bin x session model has no three-way term to omit.'); %#ok<STREMP>
            testCase.verifySubstring(QuartoReportSessionTest.groupedSessions(), ...
                'deliberately omitted');
        end

        % ---- R that R itself accepts -----------------------------------------
        function bothSessionDesignsParseAsR(testCase)
        %BOTHSESSIONDESIGNSPARSEASR  The check that actually matters. Every
        %   assertion above is a substring match against text this same file
        %   generated, which cannot notice an unbalanced brace, a stray
        %   comma, or a sprintf whose format string lost an argument. Both
        %   session designs emit a large new chunk, so both are handed to R
        %   and R is asked whether it will parse them.
        %
        %   Skips rather than fails where Rscript is absent -- it is not on
        %   PATH in a stock Windows R install, and a machine without R is
        %   not a broken report.
            testCase.assumeTrue(~isempty(ReportFixtures.rscriptExe()), ...
                'Rscript not found; skipping the generated-R parse check.');

            folder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture()).Folder;

            cases = struct( ...
                'name', {'within', 'grouped'}, ...
                'text', {QuartoReportSessionTest.withinSessions(), ...
                         QuartoReportSessionTest.groupedSessions()});

            driver = {};
            for k = 1:numel(cases)
                file = fullfile(folder, [cases(k).name '.R']);
                fid = fopen(file, 'w');
                testCase.assertGreaterThan(fid, 0);
                fwrite(fid, ReportFixtures.rCode(cases(k).text));
                fclose(fid);

                % Forward slashes: a Windows path inside an R string literal
                % would otherwise carry backslash escapes R reads as its own.
                rPath = strrep(file, '\', '/');
                driver{end + 1} = sprintf([ ...
                    'cat(tryCatch({ parse(file = "%s"); "%s OK" },' ...
                    ' error = function(e) paste("%s FAIL:", conditionMessage(e))), "\\n")'], ...
                    rPath, cases(k).name, cases(k).name); %#ok<AGROW>
            end

            [status, output] = ReportFixtures.runRscript(strjoin(driver, newline));
            testCase.assertEqual(status, 0, ...
                sprintf('The parse driver itself failed to run.\nRscript said:\n%s', output));
            testCase.verifyEmpty(strfind(output, 'FAIL'), ...
                sprintf('R refuses to parse the generated session section:\n%s', output)); %#ok<STREMP>
            for k = 1:numel(cases)
                testCase.verifySubstring(output, [cases(k).name ' OK'], ...
                    sprintf('The driver never reported on the %s design.', cases(k).name));
            end
        end
    end

    methods (Static)
        function txt = withinSessions()
        %WITHINSESSIONS  Two people, each measured pre and post, no groups.
            txt = generateQuartoReport(ReportFixtures.erpEntries( ...
                'Bindesc', ReportFixtures.bindesc({'A', 'B', 'C'}), ...
                'Groups', {'', '', '', ''}, ...
                'Subjects', {'a_pre', 'a_post', 'b_pre', 'b_post'}, ...
                'Persons', {'a', 'a', 'b', 'b'}, ...
                'Sessions', {'pre', 'post', 'pre', 'post'}), ...
                QuartoReportSessionTest.CsvName);
        end

        function txt = groupedSessions()
        %GROUPEDSESSIONS  Two groups of two people, each measured twice:
        %   the full crossing, with every cell occupied.
            txt = generateQuartoReport(ReportFixtures.erpEntries( ...
                'Bindesc', ReportFixtures.bindesc({'A', 'B', 'C'}), ...
                'Groups', {'young', 'young', 'young', 'young', 'old', 'old', 'old', 'old'}, ...
                'Subjects', {'a1', 'a2', 'b1', 'b2', 'c1', 'c2', 'd1', 'd2'}, ...
                'Persons', {'a', 'a', 'b', 'b', 'c', 'c', 'd', 'd'}, ...
                'Sessions', {'pre', 'post', 'pre', 'post', 'pre', 'post', 'pre', 'post'}), ...
                QuartoReportSessionTest.CsvName);
        end
    end
end
