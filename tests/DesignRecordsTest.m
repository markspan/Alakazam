classdef DesignRecordsTest < matlab.unittest.TestCase
%DESIGNRECORDSTEST  The seam that gave the Design panel and the statistical
%   report one derivation of the design instead of two.
%
%   Alakazam.collectDesignRecordings (for the panel) and
%   collectEntriesWithField (for the report) walk the same tree and record
%   the same facts under different field names. That difference alone was
%   enough that reportDesignPlan could not reuse deriveDesign, so it grew a
%   second derivation with its own rules for blank labels, its own cell
%   counting and its own idea of when a cell is too small -- and the panel
%   could state one design while the report fitted another.
%
%   designRecords is the mapping that removed the second derivation. The
%   last test here is the one that matters: the same study, described in
%   both shapes, must derive the same design.
%
%   Run with: runtests('tests/DesignRecordsTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            here = fileparts(mfilename('fullpath'));
            root = fileparts(here);
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'IO')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(here));
        end
    end

    methods (Test)
        % ---- the mapping ---------------------------------------------------
        function fieldsAreMappedAcross(testCase)
            records = designRecords(entry('a_pre', 'young', 'a', 'pre'));

            testCase.assertNumElements(records, 1);
            testCase.verifyEqual(records.name, 'a_pre');
            testCase.verifyEqual(records.person, 'a');
            testCase.verifyEqual(records.group, 'young');
            testCase.verifyEqual(records.session, 'pre');
        end

        function everythingReachingHereIsInTheStudy(testCase)
        %EVERYTHINGREACHINGHEREISINTHESTUDY  collectEntriesWithField applies
        %   WorkSpace.includedFor before it loads anything, so an excluded
        %   recording never becomes an entry at all.
            records = designRecords([entry('a', '', 'a', ''), entry('b', '', 'b', '')]);

            testCase.verifyTrue(all([records.included]));
        end

        function grandAveragesAreDropped(testCase)
        %GRANDAVERAGESAREDROPPED  A grand average is a summary OVER people,
        %   not a person; counting one would inflate every cell it fell in.
            entries = [entry('a', '', 'a', ''), grandAverage('GA'), entry('b', '', 'b', '')];

            records = designRecords(entries);
            testCase.verifyEqual({records.name}, {'a', 'b'});
        end

        function personFallsBackToTheRecording(testCase)
        %PERSONFALLSBACKTOTHERECORDING  What WorkSpace.personFor itself does
        %   when nobody has set a person. A blank must not merge every
        %   unlabelled recording into one phantom person.
            e = entry('sub01', '', '', '');
            records = designRecords(e);

            testCase.verifyEqual(records.person, 'sub01');
        end

        function binsComeFromTheBindesc(testCase)
            e = entry('a', '', 'a', '');
            e.EEG = struct('bindesc', struct('label', {'Rare', 'Frequent'}));

            records = designRecords(e);
            testCase.verifyEqual(records.bins, {'Rare', 'Frequent'});
        end

        function aMissingBindescIsNotAnError(testCase)
        %AMISSINGBINDESCISNOTANERROR  The design of the OTHER factors is
        %   still worth reading, and several fixtures carry no bindesc.
            e = entry('a', '', 'a', '');
            e.EEG = [];

            records = designRecords(e);
            testCase.verifyEmpty(records.bins);
        end

        function noEntriesGiveNoRecords(testCase)
            records = designRecords(struct('subject', {}, 'datasetType', {}, ...
                'group', {}, 'person', {}, 'session', {}, 'EEG', {}));

            testCase.verifyEmpty(records);
        end

        % ---- the property the whole change exists for -----------------------
        function bothShapesDeriveTheSameDesign(testCase)
        %BOTHSHAPESDERIVETHESAMEDESIGN  The same study, described the way the
        %   Design panel sees it and the way the report sees it, must produce
        %   the same design. Before designRecords the two shapes went through
        %   two different derivations and there was nothing that could have
        %   caught them diverging.
            panelRecords = testCase.twoByTwoAsPanelSeesIt();
            reportEntries = testCase.twoByTwoAsReportSeesIt();

            fromPanel = deriveDesign(panelRecords);
            fromReport = deriveDesign(designRecords(reportEntries));

            testCase.verifyEqual(fromReport.nPersons, fromPanel.nPersons);
            testCase.verifyEqual(fromReport.nRecordings, fromPanel.nRecordings);
            testCase.verifyEqual({fromReport.cells.group}, {fromPanel.cells.group});
            testCase.verifyEqual({fromReport.cells.session}, {fromPanel.cells.session});
            testCase.verifyEqual([fromReport.cells.nPersons], [fromPanel.cells.nPersons]);

            for name = {'bin', 'session', 'group'}
                testCase.verifyEqual(levelsOf(fromReport, name{1}), ...
                    levelsOf(fromPanel, name{1}), ...
                    sprintf('The two shapes disagree about the levels of %s.', name{1}));
            end
        end

        function bothShapesChooseTheSameModel(testCase)
        %BOTHSHAPESCHOOSETHESAMEMODEL  The consequence of the above, stated
        %   in the terms an analyst would notice: the same study cannot be
        %   given one model by the panel's reading and another by the
        %   report's.
            fromPanel = reportDesignPlan(deriveDesign(testCase.twoByTwoAsPanelSeesIt()));
            fromReport = reportDesignPlan(deriveDesign(designRecords( ...
                testCase.twoByTwoAsReportSeesIt())));

            testCase.verifyEqual(fromReport.fixed, fromPanel.fixed);
            testCase.verifyEqual(fromReport.random, fromPanel.random);
            testCase.verifyEqual(fromReport.usedFallback, fromPanel.usedFallback);
            testCase.verifyEqual(fromReport.fallbackReason, fromPanel.fallbackReason);
        end
    end

    methods (Access = private)
        function records = twoByTwoAsPanelSeesIt(~)
        %TWOBYTWOASPANELSEESIT  collectDesignRecordings' own shape: two
        %   groups x two sessions, two people per group.
            records = struct('name', {}, 'person', {}, 'group', {}, ...
                'session', {}, 'bins', {}, 'included', {}, 'file', {});
            spec = {
                'a1', 'a', 'young', 'pre'; 'a2', 'a', 'young', 'post'
                'b1', 'b', 'young', 'pre'; 'b2', 'b', 'young', 'post'
                'c1', 'c', 'old',   'pre'; 'c2', 'c', 'old',   'post'
                'd1', 'd', 'old',   'pre'; 'd2', 'd', 'old',   'post'};
            for k = 1:size(spec, 1)
                records(end + 1) = struct('name', spec{k, 1}, 'person', spec{k, 2}, ...
                    'group', spec{k, 3}, 'session', spec{k, 4}, ...
                    'bins', {{'Rare', 'Frequent'}}, 'included', true, 'file', ''); %#ok<AGROW>
            end
        end

        function entries = twoByTwoAsReportSeesIt(~)
        %TWOBYTWOASREPORTSEESIT  The identical study in collectEntriesWithField's
        %   shape, down to the bin labels.
            entries = struct('subject', {}, 'datasetType', {}, 'group', {}, ...
                'person', {}, 'session', {}, 'EEG', {});
            spec = {
                'a1', 'a', 'young', 'pre'; 'a2', 'a', 'young', 'post'
                'b1', 'b', 'young', 'pre'; 'b2', 'b', 'young', 'post'
                'c1', 'c', 'old',   'pre'; 'c2', 'c', 'old',   'post'
                'd1', 'd', 'old',   'pre'; 'd2', 'd', 'old',   'post'};
            EEG = struct('bindesc', struct('label', {'Rare', 'Frequent'}));
            for k = 1:size(spec, 1)
                entries(end + 1) = struct('subject', spec{k, 1}, 'datasetType', 'subject', ...
                    'group', spec{k, 3}, 'person', spec{k, 2}, 'session', spec{k, 4}, ...
                    'EEG', EEG); %#ok<AGROW>
            end
        end
    end
end

% ======================================================================= %
function e = entry(subject, group, person, session)
    e = struct('subject', subject, 'datasetType', 'subject', 'group', group, ...
        'person', person, 'session', session, 'EEG', []);
end

function e = grandAverage(name)
    e = struct('subject', name, 'datasetType', 'grand_average', 'group', '', ...
        'person', name, 'session', '', 'EEG', []);
end

function levels = levelsOf(design, factorName)
    match = design.factors(strcmp({design.factors.name}, factorName));
    levels = match(1).levels;
end
