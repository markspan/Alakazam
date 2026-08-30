classdef EventEditorTest < matlab.unittest.TestCase
%EVENTEDITORTEST  The event-table editor, and the property its whole design
%   rests on.
%
%   EventEditor stores an ordered list of OPERATIONS rather than the event
%   table those operations produce. Storing the table would be simpler and
%   catastrophic: replaying subject 1's finished events onto subject 2 would
%   overwrite subject 2's events with subject 1's, silently, and the tree
%   would record it as a successful step. That single distinction is what
%   most of this file is about.
%
%   The dialog is not tested here: MATLAB's -batch refuses blocking dialogs,
%   and the arithmetic that can be wrong lives in applyEventOps, which is a
%   pure function of its inputs.
%
%   Run with: runtests('tests/EventEditorTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations', 'EventEditor')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations')));
        end
    end

    methods (Test)
        % ---- the operations -------------------------------------------------
        function renamingChangesOnlyTheMatchingType(testCase)
            events = testCase.events({'112', '122', '112'}, [100, 200, 300]);
            ops = testCase.op('renameType', 'from', '112', 'to', '121');

            out = applyEventOps(events, ops, 250, 1000);

            testCase.verifyEqual({out.type}, {'121', '122', '121'});
        end

        function renamingComparesTypesAsText(testCase)
        %RENAMINGCOMPARESTYPESASTEXT  A trigger recorded as the number 112
        %   and one recorded as the string "112" are the same code, which is
        %   the rule the bin language already uses.
            events = testCase.events({112, '112'}, [100, 200]);
            ops = testCase.op('renameType', 'from', '112', 'to', '121');

            out = applyEventOps(events, ops, 250, 1000);

            testCase.verifyEqual(numel(out), 2);
            testCase.verifyEqual(char(string(out(2).type)), '121');
        end

        function renamingKeepsANumericTypeNumeric(testCase)
        %RENAMINGKEEPSANUMERICTYPENUMERIC  EEG.event(i).type is numeric in
        %   some recordings and char in others; a struct array holding both
        %   is a nuisance for everything downstream.
            events = testCase.events({112, 122}, [100, 200]);
            ops = testCase.op('renameType', 'from', '112', 'to', '121');

            out = applyEventOps(events, ops, 250, 1000);

            testCase.verifyTrue(isnumeric(out(1).type));
            testCase.verifyEqual(out(1).type, 121);
        end

        function deleteAndKeepAreOpposites(testCase)
            events = testCase.events({'A', 'B', 'C', 'B'}, [100, 200, 300, 400]);

            dropped = applyEventOps(events, testCase.op('deleteType', 'types', {'B'}), 250, 1000);
            kept = applyEventOps(events, testCase.op('keepTypes', 'types', {'B'}), 250, 1000);

            testCase.verifyEqual({dropped.type}, {'A', 'C'});
            testCase.verifyEqual({kept.type}, {'B', 'B'});
        end

        function shiftIsInMillisecondsNotSamples(testCase)
        %SHIFTISINMILLISECONDSNOTSAMPLES  The correction an analyst knows is
        %   "the triggers are 16 ms late", and that stays true across
        %   recordings at different sampling rates. A sample count would not.
            events = testCase.events({'S'}, 100);

            at250 = applyEventOps(events, testCase.op('shiftLatency', 'types', {}, 'ms', -16), 250, 1000);
            at500 = applyEventOps(events, testCase.op('shiftLatency', 'types', {}, 'ms', -16), 500, 1000);

            testCase.verifyEqual(at250.latency, 100 - 4, 'AbsTol', 1e-9);   % 16 ms @250Hz = 4 samples
            testCase.verifyEqual(at500.latency, 100 - 8, 'AbsTol', 1e-9);   % 16 ms @500Hz = 8
        end

        function shiftCanTargetOneType(testCase)
            events = testCase.events({'A', 'B'}, [100, 200]);
            ops = testCase.op('shiftLatency', 'types', {'B'}, 'ms', 40);

            out = applyEventOps(events, ops, 250, 1000);

            testCase.verifyEqual(out(1).latency, 100);
            testCase.verifyEqual(out(2).latency, 210);   % 40 ms @250Hz = 10 samples
        end

        % ---- keeping the table valid -----------------------------------------
        function eventsPushedOutsideTheDataAreDropped(testCase)
        %EVENTSPUSHEDOUTSIDETHEDATAAREDROPPED  A negative or past-the-end
        %   latency is not merely odd: it makes epoching fail later, in a
        %   way that is hard to trace back to an edit made here.
            events = testCase.events({'A', 'B'}, [10, 500]);
            ops = testCase.op('shiftLatency', 'types', {}, 'ms', -200);   % -50 samples

            [out, notes] = applyEventOps(events, ops, 250, 1000);

            testCase.verifyEqual(numel(out), 1);
            testCase.verifyTrue(any(contains(notes, 'outside the data')));
        end

        function theTableIsResortedAfterAShift(testCase)
        %THETABLEISRESORTEDAFTERASHIFT  EEGLAB assumes EEG.event is ordered
        %   by latency, and shifting one type past another breaks that.
            events = testCase.events({'A', 'B'}, [100, 200]);
            ops = testCase.op('shiftLatency', 'types', {'A'}, 'ms', 800);  % +200 samples

            [out, notes] = applyEventOps(events, ops, 250, 1000);

            testCase.verifyEqual([out.latency], sort([out.latency]));
            testCase.verifyEqual({out.type}, {'B', 'A'});
            testCase.verifyTrue(any(contains(notes, 're-sorted')));
        end

        function operationsApplyInOrder(testCase)
        %OPERATIONSAPPLYINORDER  Renaming then deleting is not the same as
        %   deleting then renaming, so the list is a sequence, not a set.
            events = testCase.events({'A', 'B'}, [100, 200]);

            renameThenDelete = [testCase.op('renameType', 'from', 'A', 'to', 'B'), ...
                                testCase.op('deleteType', 'types', {'B'})];
            deleteThenRename = [testCase.op('deleteType', 'types', {'B'}), ...
                                testCase.op('renameType', 'from', 'A', 'to', 'B')];

            testCase.verifyEmpty(applyEventOps(events, renameThenDelete, 250, 1000));
            testCase.verifyEqual(numel(applyEventOps(events, deleteThenRename, 250, 1000)), 1);
        end

        % ---- the property the design exists for -------------------------------
        function aHandEditIsSkippedWhenItsTargetDiffers(testCase)
        %AHANDEDITISSKIPPEDWHENITSTARGETDIFFERS  The load-bearing test. A
        %   hand edit is recorded against a POSITION, and position means
        %   nothing in another recording: event 2 here is a different event
        %   there. So the operation carries a fingerprint of what the event
        %   looked like when it was edited, and replay refuses to apply it to
        %   something else. Without this, replaying across twenty subjects
        %   would corrupt one event in each of them, invisibly.
            edited = testCase.op('setValue', 'index', 2, 'field', 'type', ...
                'value', 'FIXED', 'wasType', 'B', 'wasLatency', 200);

            sameRecording = testCase.events({'A', 'B'}, [100, 200]);
            otherSubject  = testCase.events({'A', 'Z'}, [100, 200]);

            [applied, noNotes] = applyEventOps(sameRecording, edited, 250, 1000);
            [skipped, notes] = applyEventOps(otherSubject, edited, 250, 1000);

            testCase.verifyEqual(char(string(applied(2).type)), 'FIXED');
            testCase.verifyEmpty(noNotes);

            testCase.verifyEqual(char(string(skipped(2).type)), 'Z', ...
                'A hand edit was applied to an event it was not recorded against.');
            testCase.verifyTrue(any(contains(notes, 'skipped')));
        end

        function aHandEditPastTheEndIsSkipped(testCase)
            edited = testCase.op('setValue', 'index', 9, 'field', 'type', ...
                'value', 'X', 'wasType', 'B', 'wasLatency', 200);

            [out, notes] = applyEventOps(testCase.events({'A'}, 100), edited, 250, 1000);

            testCase.verifyEqual(numel(out), 1);
            testCase.verifyTrue(any(contains(notes, 'does not have')));
        end

        function aRuleCarriesToAnotherSubjectWhereAHandEditDoesNot(testCase)
        %ARULECARRIESTOANOTHERSUBJECTWHEREAHANDEDITDOESNOT  The distinction
        %   the dialog puts on screen, stated as a test: the same recorded
        %   correction applied to two different recordings.
            ops = testCase.op('renameType', 'from', '112', 'to', '121');

            one = applyEventOps(testCase.events({'112', '99'}, [100, 200]), ops, 250, 1000);
            two = applyEventOps(testCase.events({'7', '112', '112'}, [50, 150, 250]), ops, 250, 1000);

            testCase.verifyEqual({one.type}, {'121', '99'});
            testCase.verifyEqual({two.type}, {'7', '121', '121'});
        end

        % ---- the transformation contract ---------------------------------------
        function replayWithNoOperationsLeavesTheDatasetAlone(testCase)
            EEG = testCase.eeg({'A', 'B'}, [100, 200]);

            [out, opts] = EventEditor(EEG, struct('ops', []));

            testCase.verifyEqual(out.event, EEG.event);
            testCase.verifyTrue(isstruct(opts));
        end

        function replayAppliesTheStoredOperations(testCase)
            EEG = testCase.eeg({'112', '122'}, [100, 200]);
            opts = struct('ops', testCase.op('renameType', 'from', '112', 'to', '121'));

            out = EventEditor(EEG, opts);

            testCase.verifyEqual(char(string(out.event(1).type)), '121');
        end

        function aDatasetWithNoEventFieldIsRefused(testCase)
            testCase.verifyError(@() EventEditor(struct('srate', 250), struct('ops', [])), ...
                'Alakazam:EventEditor');
        end

        function whatDidNotApplyIsKeptWithTheResult(testCase)
        %WHATDIDNOTAPPLYISKEPTWITHTHERESULT  A replay across twenty subjects
        %   should not stop at the first one whose events differ, but it
        %   must not pretend everything applied either.
            EEG = testCase.eeg({'A'}, 100);
            opts = struct('ops', testCase.op('renameType', 'from', 'NOPE', 'to', 'X'));

            out = testCase.verifyWarning(@() EventEditor(EEG, opts), ...
                'Alakazam:EventEditor:note');

            testCase.verifyNotEmpty(out.EventEditNotes);
        end
    end

    methods (Access = private)
        function e = events(~, types, latencies)
            e = struct('type', types, 'latency', num2cell(latencies));
        end

        function EEG = eeg(testCase, types, latencies)
            EEG = struct('srate', 250, 'pnts', 1000, ...
                'event', testCase.events(types, latencies));
        end

        function op = op(~, name, varargin)
        %OP  One operation, every field present so a struct array of them
        %   stays homogeneous (see EventEditorDialog's own emptyOps note).
            % {{}} here, not {}: struct() unwraps one cell level, so
            % 'types', {} would make a 0x0 struct array rather than a scalar
            % with an empty cell field. Field ASSIGNMENT below needs no such
            % wrapping, which is the asymmetry that caused this in the first
            % place.
            op = struct('op', name, 'from', '', 'to', '', 'types', {{}}, 'ms', 0, ...
                'index', 0, 'field', '', 'value', [], 'wasType', '', 'wasLatency', 0);
            for k = 1:2:numel(varargin)
                op.(varargin{k}) = varargin{k + 1};
            end
        end
    end
end
