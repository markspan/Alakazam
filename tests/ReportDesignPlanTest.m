classdef ReportDesignPlanTest < matlab.unittest.TestCase
%REPORTDESIGNPLANTEST  Unit tests for src/IO/reportDesignPlan.m.
%
%   The report engine decides which model to fit. Until recently that
%   decision lived inside emitted R, where the only way to check it was to
%   render a report and read the output, which is why QuartoReportKnownGapTest
%   exists at all. reportDesignPlan pulls the decision back into MATLAB so
%   it can be tested directly, and these are those tests.
%
%   They go through the REAL path -- designRecords, then deriveDesign, then
%   reportDesignPlan -- rather than handing the plan a design built by hand
%   (see planFor at the foot of this file). That is deliberate: the plan
%   used to derive the design itself, separately from the Design panel, and
%   the two could disagree about the same recordings. Exercising the seam
%   here is what keeps them one answer.
%
%   Two of them matter more than the rest. The random effect moving from
%   the recording to the person must change nothing for a single-session
%   study, or every existing result silently shifts. And a design that
%   cannot support session must fall back rather than be fitted anyway: an
%   unestimable interaction does not announce itself in lmer's output.
%
%   Run with: runtests('tests/ReportDesignPlanTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'IO')));
        end
    end

    methods (Test)
        % ---- the random effect ------------------------------------------
        function theRandomEffectIsOnThePerson(testCase)
            plan = planFor(oneSessionStudy());

            testCase.verifyEqual(plan.random, '(1 + bin | person_id)');
            testCase.verifyEqual(plan.randomFallback, '(1 | person_id)');
        end

        function aSingleSessionStudyIsUnchangedByThat(testCase)
        %ASINGLESESSIONSTUDYISUNCHANGEDBYTHAT  The one result that must not
        %   move. Where personFor has not been set it returns the recording's
        %   own name, so person_id and dataset are the same column and
        %   grouping by either gives an identical fit. If this ever fails,
        %   every published single-session result from an earlier version
        %   disagrees with the current one.
            entries = oneSessionStudy();
            testCase.assertEqual({entries.person}, {entries.subject}, ...
                'The fixture must model the default: person defaults to the recording.');

            plan = planFor(entries);
            testCase.verifyEqual(plan.fixed, 'bin');
            testCase.verifyFalse(plan.usedFallback);
        end

        % ---- which factors are used -------------------------------------
        function binsAloneGiveTheSimplestModel(testCase)
            plan = planFor(oneSessionStudy());

            testCase.verifyEqual(plan.fixed, 'bin');
            testCase.verifyEqual(plan.withinFactors, {'bin'});
            testCase.verifyEmpty(plan.betweenFactors);
        end

        function twoGroupsAddGroup(testCase)
            entries = [ ...
                rec('s1', 'young', 's1', ''), rec('s2', 'young', 's2', ''), ...
                rec('s3', 'old', 's3', ''),   rec('s4', 'old', 's4', '')];

            plan = planFor(entries);
            testCase.verifyEqual(plan.fixed, 'bin * group');
            testCase.verifyEqual(plan.betweenFactors, {'group'});
        end

        function twoSessionsAddSession(testCase)
            plan = planFor(repeatedMeasures());

            testCase.verifyEqual(plan.fixed, 'bin * session');
            testCase.verifyEqual(plan.withinFactors, {'bin', 'session'});
            testCase.verifyFalse(plan.usedFallback);
        end

        function sessionIsAutomatic(testCase)
        %SESSIONISAUTOMATIC  No opt-in switch. An analyst who has labelled
        %   two sessions has already described the design, and a second
        %   declaration is only an opportunity for the two to disagree.
            plan = planFor(repeatedMeasures());

            testCase.verifyEqual(plan.sessionLevels, {'pre', 'post'});
        end

        function allThreeFactorsDropTheThreeWayInteraction(testCase)
        %ALLTHREEFACTORSDROPTHETHREEWAYINTERACTION  "^2" is R for every main
        %   effect and every two-way interaction and nothing further, so the
        %   formula states the omission rather than leaving it to be noticed
        %   from a missing row in the output.
            plan = planFor(fullCrossing());

            testCase.verifyEqual(plan.fixed, '(bin + session + group)^2');
            testCase.verifyFalse(contains(plan.fixed, '*'), ...
                'A "*" here would silently reinstate the three-way term.');
            testCase.verifyFalse(plan.usedFallback);
        end

        % ---- falling back ------------------------------------------------
        function sessionNeedsPeopleMeasuredTwice(testCase)
        %SESSIONNEEDSPEOPLEMEASUREDTWICE  Two session labels are not a
        %   within-subject factor if nobody appears under both: session is
        %   then confounded with person and the model cannot separate them.
            entries = [ ...
                rec('a_pre', '', 'a', 'pre'), rec('b_post', '', 'b', 'post'), ...
                rec('c_pre', '', 'c', 'pre'), rec('d_post', '', 'd', 'post')];

            plan = planFor(entries);
            testCase.verifyTrue(plan.usedFallback);
            testCase.verifyEqual(plan.fixed, 'bin');
            testCase.verifySubstring(plan.fallbackReason, 'within subjects');
        end

        function anEmptyCellDropsSession(testCase)
        %ANEMPTYCELLDROPSSESSION  Nobody in old/post, so the interaction
        %   involving session cannot be estimated. Group survives: only the
        %   factor that caused the problem is given up.
            entries = [ ...
                rec('a_pre', 'young', 'a', 'pre'), rec('a_post', 'young', 'a', 'post'), ...
                rec('b_pre', 'young', 'b', 'pre'), rec('b_post', 'young', 'b', 'post'), ...
                rec('c_pre', 'old', 'c', 'pre'),   rec('d_pre', 'old', 'd', 'pre')];

            plan = planFor(entries);
            testCase.verifyTrue(plan.usedFallback);
            testCase.verifyEqual(plan.fixed, 'bin * group');
            testCase.verifySubstring(plan.fallbackReason, 'old');
            testCase.verifySubstring(plan.fallbackReason, 'post');
        end

        function aCellOfOneDropsSession(testCase)
        %ACELLOFONEDROPSSESSION  One subject in a cell is enough for lmer to
        %   return a fit and not enough for that fit to mean anything.
            entries = [ ...
                rec('a_pre', 'young', 'a', 'pre'), rec('a_post', 'young', 'a', 'post'), ...
                rec('b_pre', 'young', 'b', 'pre'), rec('b_post', 'young', 'b', 'post'), ...
                rec('c_pre', 'old', 'c', 'pre'),   rec('c_post', 'old', 'c', 'post')];

            plan = planFor(entries);
            testCase.verifyTrue(plan.usedFallback);
            testCase.verifySubstring(plan.fallbackReason, 'one subject');
        end

        function fallingBackAlwaysSaysWhy(testCase)
        %FALLINGBACKALWAYSSAYSWHY  The report prints this sentence verbatim.
        %   A silent fallback would present a simpler model as though it
        %   were the intended one.
            entries = [ ...
                rec('a_pre', '', 'a', 'pre'), rec('b_post', '', 'b', 'post')];

            plan = planFor(entries);
            testCase.assertTrue(plan.usedFallback);
            testCase.verifyNotEmpty(plan.fallbackReason);
            testCase.verifySubstring(plan.fallbackReason, 'simpler model');
        end

        function noSessionAtAllIsNotAFallback(testCase)
        %NOSESSIONATALLISNOTAFALLBACK  Nothing was given up, so there is
        %   nothing to explain, and a report on a single-session study should
        %   not carry a caveat about a factor nobody recorded.
            plan = planFor(oneSessionStudy());

            testCase.verifyFalse(plan.usedFallback);
            testCase.verifyEmpty(plan.fallbackReason);
        end

        % ---- what counts as a level --------------------------------------
        function blankLabelsAreNotLevels(testCase)
            entries = [ ...
                rec('a', '', 'a', ''), rec('b', '', 'b', '   '), rec('c', '', 'c', '')];

            plan = planFor(entries);
            testCase.verifyEmpty(plan.sessionLevels);
            testCase.verifyFalse(plan.usedFallback);
        end

        function oneGroupLabelIsNotAFactor(testCase)
            entries = [rec('a', 'young', 'a', ''), rec('b', 'young', 'b', '')];

            plan = planFor(entries);
            testCase.verifyEmpty(plan.betweenFactors);
            testCase.verifyEqual(plan.fixed, 'bin');
        end

        function grandAveragesDoNotContributeLevels(testCase)
        %GRANDAVERAGESDONOTCONTRIBUTELEVELS  A grand average is a summary
        %   over people, not a person, and carries blank group and session
        %   anyway, but it must not be counted as a subject in a cell.
            entries = [repeatedMeasures(), grandAverage('GA young')];

            plan = planFor(entries);
            testCase.verifyEqual(plan.fixed, 'bin * session');
        end

        function noEntriesGiveTheDefaultPlan(testCase)
            plan = planFor(struct('subject', {}, 'datasetType', {}, ...
                'group', {}, 'person', {}, 'session', {}));

            testCase.verifyEqual(plan.fixed, 'bin');
            testCase.verifyEqual(plan.random, '(1 + bin | person_id)');
            testCase.verifyFalse(plan.usedFallback);
        end
    end
end

% ======================================================================= %
function plan = planFor(entries)
%PLANFOR  The plan for ENTRIES, through the whole real chain: report
%   entries -> designRecords -> deriveDesign -> reportDesignPlan. One
%   derivation, the same one the Design panel reads.
    plan = reportDesignPlan(deriveDesign(designRecords(entries)));
end

function e = rec(subject, group, person, session)
    e = struct('subject', subject, 'datasetType', 'subject', ...
        'group', group, 'person', person, 'session', session);
end

function e = grandAverage(name)
    e = struct('subject', name, 'datasetType', 'grand_average', ...
        'group', '', 'person', name, 'session', '');
end

function entries = oneSessionStudy()
%ONESESSIONSTUDY  The shape every existing Alakazam study has: one
%   recording per person, no session label, and .person left at its default
%   (the recording's own name).
    entries = [rec('s1', '', 's1', ''), rec('s2', '', 's2', ''), ...
        rec('s3', '', 's3', ''), rec('s4', '', 's4', '')];
end

function entries = repeatedMeasures()
    entries = [ ...
        rec('a_pre', '', 'a', 'pre'), rec('a_post', '', 'a', 'post'), ...
        rec('b_pre', '', 'b', 'pre'), rec('b_post', '', 'b', 'post'), ...
        rec('c_pre', '', 'c', 'pre'), rec('c_post', '', 'c', 'post')];
end

function entries = fullCrossing()
    entries = [ ...
        rec('a_pre', 'young', 'a', 'pre'), rec('a_post', 'young', 'a', 'post'), ...
        rec('b_pre', 'young', 'b', 'pre'), rec('b_post', 'young', 'b', 'post'), ...
        rec('c_pre', 'old', 'c', 'pre'),   rec('c_post', 'old', 'c', 'post'), ...
        rec('d_pre', 'old', 'd', 'pre'),   rec('d_post', 'old', 'd', 'post')];
end
