classdef DeriveDesignTest < matlab.unittest.TestCase
%DERIVEDESIGNTEST  Unit tests for src/IO/deriveDesign.m.
%
%   The derivation exists to be diagnostic: an empty cell, an unbalanced
%   pair of groups, or a subject recorded under two group labels should be
%   visible before a report is run rather than inferred afterwards from a
%   surprising result. Most of these tests are therefore about the
%   WARNINGS, which are the part that earns the feature.
%
%   The counting rule is the other thing worth pinning. Group partitions
%   people, session partitions a person's recordings, and bin partitions
%   nothing at all -- every Average carries every bin. Counting bins into
%   the cells would multiply every n by the number of conditions.
%
%   Run with: runtests('tests/DeriveDesignTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'IO')));
        end
    end

    methods (Test)
        % ---- the empty case ---------------------------------------------
        function noRecordingsIsExplained(testCase)
            design = deriveDesign(testCase.emptyRecordings());

            testCase.verifyEqual(design.nRecordings, 0);
            testCase.verifyNotEmpty(design.warnings);
            testCase.verifySubstring(design.warnings{1}, 'no design to read');
        end

        % ---- factors ----------------------------------------------------
        function binLevelsComeFromTheDatasets(testCase)
            design = deriveDesign(testCase.simpleStudy());

            bin = testCase.factor(design, 'bin');
            testCase.verifyEqual(bin.type, 'within');
            testCase.verifyEqual(sort(bin.levels), {'Frequent', 'Rare'});
        end

        function groupIsBetweenAndSessionIsWithin(testCase)
            design = deriveDesign(testCase.twoByTwoStudy());

            testCase.verifyEqual(testCase.factor(design, 'group').type, 'between');
            testCase.verifyEqual(testCase.factor(design, 'session').type, 'within');
        end

        function anUnusedFactorIsListedWithAReason(testCase)
        %ANUNUSEDFACTORISLISTEDWITHAREASON  "You have no groups" is exactly
        %   what a reader needs to see when they expected a between-subjects
        %   test and did not get one.
            design = deriveDesign(testCase.simpleStudy());

            group = testCase.factor(design, 'group');
            testCase.verifyEmpty(group.levels);
            testCase.verifySubstring(group.note, 'within-subject');
        end

        function aSingleLevelFactorSaysSo(testCase)
            recordings = testCase.simpleStudy();
            [recordings.group] = deal('control');

            design = deriveDesign(recordings);

            testCase.verifySubstring(testCase.factor(design, 'group').note, 'only one level');
        end

        function mismatchedBinsAreReported(testCase)
            recordings = testCase.simpleStudy();
            recordings(2).bins = {'Rare', 'Odd'};

            design = deriveDesign(recordings);

            testCase.verifySubstring(testCase.factor(design, 'bin').note, 'same bins');
            testCase.verifyTrue(any(contains(design.warnings, 'Bins:')));
        end

        % ---- cells and counting -----------------------------------------
        function cellsCrossGroupAndSessionOnly(testCase)
        %CELLSCROSSGROUPANDSESSIONONLY  Bin is within a recording, so it
        %   does not split anyone; crossing it in would make a four-person
        %   study look like eight.
            design = deriveDesign(testCase.twoByTwoStudy());

            testCase.verifyNumElements(design.cells, 4);   % 2 groups x 2 sessions
            testCase.verifyEqual(sum([design.cells.nPersons]), 8);
        end

        function cellsAreCountedInPeopleNotFiles(testCase)
        %CELLSARECOUNTEDINPEOPLENOTFILES  One person recorded twice is one
        %   subject, and a between-subjects n of two would be wrong.
            recordings = testCase.twoSessionsOfOnePerson();

            design = deriveDesign(recordings);

            testCase.verifyEqual(design.nPersons, 1);
            testCase.verifyEqual(design.nRecordings, 2);
            testCase.verifyEqual(sum([design.cells.nPersons]), 2, ...
                'The one person appears once in each session cell.');
            testCase.verifyTrue(all([design.cells.nPersons] <= 1));
        end

        function anEmptyCellIsWarnedAbout(testCase)
            recordings = testCase.twoByTwoStudy();
            recordings = recordings(~(strcmp({recordings.group}, 'patient') & ...
                strcmp({recordings.session}, 'Day 2')));

            design = deriveDesign(recordings);

            testCase.verifyTrue(any(contains(design.warnings, 'No recordings in patient / Day 2')));
        end

        function unassignedFieldsGetTheirOwnCell(testCase)
        %UNASSIGNEDFIELDSGETTHEIROWNCELL  A blank group is a real state, not
        %   an absent one: those recordings are what grouped tests silently
        %   drop, so they need to be visible rather than collapsed away.
            design = deriveDesign(testCase.simpleStudy());

            testCase.verifyNumElements(design.cells, 1);
            testCase.verifyEqual(design.cells(1).group, '(no group)');
            testCase.verifyEqual(design.cells(1).session, '(no session)');
            testCase.verifyEqual(design.cells(1).nPersons, 2);
        end

        % ---- warnings that catch real mistakes --------------------------
        function markedImbalanceIsWarnedAbout(testCase)
            recordings = testCase.emptyRecordings();
            for k = 1:9
                recordings(end + 1) = testCase.recording(sprintf('c%02d', k), 'control', ''); %#ok<AGROW>
            end
            for k = 1:2
                recordings(end + 1) = testCase.recording(sprintf('p%02d', k), 'patient', ''); %#ok<AGROW>
            end

            design = deriveDesign(recordings);

            testCase.verifyTrue(any(contains(design.warnings, 'markedly unbalanced')));
        end

        function aBalancedStudyIsNotWarnedAbout(testCase)
            design = deriveDesign(testCase.twoByTwoStudy());

            testCase.verifyFalse(any(contains(design.warnings, 'unbalanced')));
        end

        function aPersonInTwoGroupsIsWarnedAbout(testCase)
        %APERSONINTWOGROUPSISWARNEDABOUT  Impossible by construction, so it
        %   means a mistyped group or a mislinked person, and every grouped
        %   test is silently reading one of the two.
            recordings = testCase.emptyRecordings();
            recordings(1) = testCase.recording('day1', 'control', 'Day 1');
            recordings(2) = testCase.recording('day2', 'patient', 'Day 2');
            [recordings.person] = deal('sub01');

            design = deriveDesign(recordings);

            testCase.verifyTrue(any(contains(design.warnings, 'more than one group')));
            testCase.verifyEqual(design.nPersons, 1);
        end

        function aRepeatedSessionIsWarnedAbout(testCase)
            recordings = testCase.twoSessionsOfOnePerson();
            recordings(2).session = 'Day 1';   % same label twice

            design = deriveDesign(recordings);

            testCase.verifyTrue(any(contains(design.warnings, 'same session')));
        end

        function anUngroupedSubjectIsWarnedAbout(testCase)
        %ANUNGROUPEDSUBJECTISWARNEDABOUT  Today a blank group quietly
        %   removes that subject from every grouped test. Saying so is the
        %   whole point of the panel. Both of this person's recordings are
        %   blanked, since one labelled recording is enough to group them.
            recordings = testCase.twoByTwoStudy();
            mine = strcmp({recordings.person}, 'c01');
            [recordings(mine).group] = deal('');

            design = deriveDesign(recordings);

            testCase.verifyTrue(any(contains(design.warnings, 'no group assigned')));
        end

        function aPartlyLabelledSubjectIsWarnedAbout(testCase)
        %APARTLYLABELLEDSUBJECTISWARNEDABOUT  Filled in for day 1 and
        %   forgotten for day 2. The group still resolves from the labelled
        %   recording, so nothing downstream complains and the study looks
        %   complete; found because an earlier version of this test assumed
        %   the opposite.
            recordings = testCase.twoByTwoStudy();
            first = find(strcmp({recordings.person}, 'c01'), 1);
            recordings(first).group = '';

            design = deriveDesign(recordings);

            testCase.verifyTrue(any(contains(design.warnings, 'on 1 of 2 recordings')));
            testCase.verifyEqual(testCase.personNamed(design, 'c01').group, 'control', ...
                'The group should still resolve from the labelled recording.');
        end

        function aCleanStudyRaisesNothing(testCase)
            design = deriveDesign(testCase.twoByTwoStudy());

            testCase.verifyEmpty(design.warnings);
        end

        % ---- explicit exclusion -----------------------------------------
        function anExcludedRecordingLeavesTheStudy(testCase)
        %ANEXCLUDEDRECORDINGLEAVESTHESTUDY  Excluded means excluded: it must
        %   not contribute to a cell count, or the panel would report a
        %   study larger than the one being analysed.
            recordings = testCase.twoByTwoStudy();
            mine = strcmp({recordings.person}, 'c01');
            [recordings(mine).included] = deal(false);

            design = deriveDesign(recordings);

            testCase.verifyEqual(design.nRecordings, 6);
            testCase.verifyEqual(design.nPersons, 3);
            testCase.verifyEqual(design.nExcluded, 2);
            testCase.verifyFalse(any(strcmp({design.persons.name}, 'c01')));
        end

        function exclusionsAreNamedNotJustCounted(testCase)
        %EXCLUSIONSARENAMEDNOTJUSTCOUNTED  The point of making the rule
        %   explicit is that the decision is visible; a silent drop is what
        %   this replaces.
            recordings = testCase.twoByTwoStudy();
            recordings(1).included = false;

            design = deriveDesign(recordings);

            testCase.verifyTrue(any(contains(design.warnings, 'excluded from the study')));
            testCase.verifyTrue(any(contains(design.warnings, recordings(1).name)));
        end

        function excludingEverythingSaysSoPlainly(testCase)
            recordings = testCase.twoByTwoStudy();
            [recordings.included] = deal(false);

            design = deriveDesign(recordings);

            testCase.verifyEqual(design.nRecordings, 0);
            testCase.verifyEqual(design.nExcluded, 8);
            testCase.verifyTrue(any(contains(design.warnings, 'nothing to analyse')));
        end

        function anExcludedRecordingDoesNotCreateALevel(testCase)
        %ANEXCLUDEDRECORDINGDOESNOTCREATEALEVEL  A group that only an
        %   excluded recording belonged to is not a level of the design, and
        %   listing it would promise a comparison that cannot run.
            recordings = testCase.simpleStudy();
            recordings(1).group = 'pilot';
            recordings(1).included = false;
            recordings(2).group = 'control';

            design = deriveDesign(recordings);

            testCase.verifyEqual(testCase.factor(design, 'group').levels, {'control'});
        end

        function recordingsWithoutTheFieldAreIncluded(testCase)
        %RECORDINGSWITHOUTTHEFIELDAREINCLUDED  A caller predating exclusion,
        %   or a workspace saved before it existed, describes a study where
        %   everything counts. Reading that silence as "excluded" would
        %   empty an existing study on first open.
            recordings = testCase.twoByTwoStudy();
            testCase.assertFalse(isfield(recordings, 'included'), ...
                'The fixture should not carry the field for this test.');

            design = deriveDesign(recordings);

            testCase.verifyEqual(design.nRecordings, 8);
            testCase.verifyEqual(design.nExcluded, 0);
        end

        function anEmptyIncludedFieldMeansIncluded(testCase)
            recordings = testCase.twoByTwoStudy();
            [recordings.included] = deal([]);

            design = deriveDesign(recordings);

            testCase.verifyEqual(design.nRecordings, 8);
        end

        % ---- the derivation must not alter anything ---------------------
        function derivingDoesNotChangeItsInput(testCase)
        %DERIVINGDOESNOTCHANGEITSINPUT  Read-only is the promise this phase
        %   makes: nothing in the app behaves differently for having looked.
            before = testCase.twoByTwoStudy();
            after = before;

            deriveDesign(after);

            testCase.verifyEqual(after, before);
        end
    end

    % ==================================================================== %
    methods
        function f = factor(testCase, design, name)
            hit = design.factors(strcmp({design.factors.name}, name));
            testCase.assertNotEmpty(hit, sprintf('No "%s" factor was derived.', name));
            f = hit(1);
        end

        function p = personNamed(testCase, design, name)
            hit = design.persons(strcmp({design.persons.name}, name));
            testCase.assertNotEmpty(hit, sprintf('No person "%s" was derived.', name));
            p = hit(1);
        end

        function r = emptyRecordings(~)
            r = struct('name', {}, 'person', {}, 'group', {}, 'session', {}, 'bins', {});
        end

        function r = recording(~, name, group, session)
            r = struct('name', name, 'person', name, 'group', group, ...
                'session', session, 'bins', {{'Rare', 'Frequent'}});
        end

        function r = simpleStudy(testCase)
        %SIMPLESTUDY  Two recordings, nothing assigned: the default state of
        %   a workspace nobody has grouped.
            r = testCase.emptyRecordings();
            r(1) = testCase.recording('sub01', '', '');
            r(2) = testCase.recording('sub02', '', '');
        end

        function r = twoByTwoStudy(testCase)
        %TWOBYTWOSTUDY  Two groups x two sessions, two people per group,
        %   each recorded twice. Eight recordings, four people.
            r = testCase.emptyRecordings();
            for g = {'control', 'patient'}
                for p = 1:2
                    person = sprintf('%s%02d', g{1}(1), p);
                    for s = {'Day 1', 'Day 2'}
                        entry = testCase.recording([person '_' s{1}], g{1}, s{1});
                        entry.person = person;
                        r(end + 1) = entry; %#ok<AGROW>
                    end
                end
            end
        end

        function r = twoSessionsOfOnePerson(testCase)
            r = testCase.emptyRecordings();
            r(1) = testCase.recording('visit1', 'control', 'Day 1');
            r(2) = testCase.recording('visit2', 'control', 'Day 2');
            [r.person] = deal('sub01');
        end
    end
end
