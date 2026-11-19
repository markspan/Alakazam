classdef UreventTest < matlab.unittest.TestCase
%UREVENTTEST  EEG.urevent, EEGLAB's table of a recording's original events, as
%   Alakazam keeps it (TransTools.AlignUrevents at the seam of every step).
%
%   THE RULES ARE EEGLAB'S, so the checks that matter most are EEGLAB's own
%   functions: the table made here is the one eeg_checkset(EEG, 'makeur') makes,
%   a latency is taken back across a cut as eeg_urlatency takes it, and after
%   DefineBins, a selection of trials and an export, eeg_context still finds the
%   event after each trial, though that event is no longer in the dataset.
%
%   Run with: runtests('tests/UreventTest.m').
%
%   See also TRANSTOOLS.ALIGNUREVENTS, TRANSTOOLS.INVOKE.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'IO'), fullfile(root, 'src', 'Views'), ...
                     fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Transformations', 'DefineBins'), ...
                     fullfile(root, 'src', 'Transformations', 'SelectData'), ...
                     fullfile(root, 'src', 'Transformations', 'Resample'), ...
                     fullfile(root, 'src', 'Transformations', 'EventEditor'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        % ---- made once, as EEGLAB makes it -------------------------------- %
        function theTableIsTheOneEeglabMakes(testCase)
            testCase.assumeEeglab();
            EEG = UreventTest.continuousSet();

            ours = TransTools.AlignUrevents(EEG);
            theirs = eeg_checkset(EEG, 'makeur');

            testCase.verifyEqual(ours.urevent, theirs.urevent);
            testCase.verifyEqual(ours.event, theirs.event);
        end

        function aTableAlreadyThereIsKept(testCase)
        %ATABLEALREADYTHEREISKEPT  From a reader that makes it, or a .set saved
        %   after events were removed: what it holds beyond the events stays.
            EEG = TransTools.AlignUrevents(UreventTest.recording());
            removed = EEG;
            removed.event(2) = [];

            again = TransTools.AlignUrevents(removed);

            testCase.verifyEqual(again, removed);
        end

        function aTableMadeAfterACutHoldsTheRecordingsLatencies(testCase)
        %ATABLEMADEAFTERACUTHOLDSTHERECORDINGSLATENCIES  A .set or a cached node
        %   can reach its first table with data already cut out of it.
            testCase.assumeEeglab();
            EEG = UreventTest.recording();
            EEG.event(1).type = 'boundary';
            EEG.event(1).duration = 50;

            after = TransTools.AlignUrevents(EEG);

            testCase.verifyEqual([after.urevent.latency], [100 250 350 450]);
            testCase.verifyEqual(after.urevent(2).latency, eeg_urlatency(EEG.event, 200));
        end

        function aBreakInTheRecordingTookNothingOut(testCase)
        %ABREAKINTHERECORDINGTOOKNOTHINGOUT  A boundary with NaN for a duration
        %   marks where a recording stopped and went on, as eeg_urlatency reads it.
            EEG = UreventTest.recording();
            EEG.event(1).type = 'boundary';
            EEG.event(1).duration = NaN;

            after = TransTools.AlignUrevents(EEG);

            testCase.verifyEqual([after.urevent.latency], [100 200 300 400]);
        end

        function everyImportMakesTheTable(testCase)
        %EVERYIMPORTMAKESTHETABLE  Only some of EEGLAB's readers make it, so
        %   every way a recording arrives has to. The readers themselves need a
        %   running workspace; ALL OF THEM is what this pins.
            root = fileparts(fileparts(mfilename('fullpath')));
            for name = {'loadRawFile', 'loadSETFile', 'loadBVAFile', 'loadMATFile'}
                source = fileread(fullfile(root, 'src', '@WorkSpace', [name{1} '.m']));
                testCase.verifySubstring(source, 'EEG = TransTools.AlignUrevents(EEG);', name{1});
            end
        end

        function averagesAndTrialsAreNotGivenATable(testCase)
        %AVERAGESANDTRIALSARENOTGIVENATABLE  Their latencies are not the
        %   recording's, so a table made from them would claim what it cannot
        %   know.
            EEG = UreventTest.recording();
            EEG.DataFormat = 'EPOCHED';
            testCase.verifyFalse(isfield(TransTools.AlignUrevents(EEG), 'urevent'));
            EEG.DataFormat = 'AVERAGED';
            testCase.verifyFalse(isfield(TransTools.AlignUrevents(EEG), 'urevent'));
        end

        % ---- what a step does to the events ------------------------------ %
        function aRemovedEventLeavesTheTableAlone(testCase)
            before = TransTools.AlignUrevents(UreventTest.recording());
            result = before;
            result.event(2) = [];

            after = TransTools.AlignUrevents(result, before);

            testCase.verifyEqual(after.urevent, before.urevent);
            testCase.verifyEqual([after.event.urevent], [1 3 4]);
        end

        function anAddedEventGoesInAtItsPlace(testCase)
        %ANADDEDEVENTGOESINATITSPLACE  The table stays in latency order, and
        %   every pointer still names its own event.
            before = TransTools.AlignUrevents(UreventTest.recording());
            result = UreventTest.withEvent(before, 'heartbeat', 250);

            after = TransTools.AlignUrevents(result, before);

            testCase.verifyEqual([after.urevent.latency], [100 200 250 300 400]);
            testCase.verifyEqual(after.urevent(3).type, 'heartbeat');
            UreventTest.verifyPointers(testCase, after);
        end

        function eeglabsOwnCheckFindsNothingToChange(testCase)
        %EEGLABSOWNCHECKFINDSNOTHINGTOCHANGE  eeg_checkset's 'checkur' sorts the
        %   table and remaps the pointers. Here that has already been done.
            testCase.assumeEeglab();
            before = TransTools.AlignUrevents(UreventTest.continuousSet());
            result = UreventTest.withEvent(before, 'heartbeat', 500);

            after = TransTools.AlignUrevents(result, before);
            checked = eeg_checkset(after, 'checkur');

            testCase.verifyEqual(checked.urevent, after.urevent);
            testCase.verifyEqual([checked.event.urevent], [after.event.urevent]);
        end

        function aNewEntryHasADuration(testCase)
        %ANEWENTRYHASADURATION  EEGLAB's insert gives a new event none, and its
        %   readers of the field assume a number.
            before = TransTools.AlignUrevents(UreventTest.recording());
            result = UreventTest.withEvent(before, 'heartbeat', 250);
            result.event(strcmp({result.event.type}, 'heartbeat')).duration = [];

            after = TransTools.AlignUrevents(result, before);

            testCase.verifyEqual(after.urevent(3).duration, 0);
        end

        function aNewEventsOwnFieldsAreKeptAndBookkeepingIsNot(testCase)
        %ANEWEVENTSOWNFIELDSAREKEPTANDBOOKKEEPINGISNOT  A beat's .ibi is what
        %   eeg_context can read back; its bins are a later step's.
            before = TransTools.AlignUrevents(UreventTest.recording());
            result = UreventTest.withEvent(before, 'heartbeat', 250);
            [result.event.ibi] = deal([]);
            [result.event.bini] = deal([]);
            beat = strcmp({result.event.type}, 'heartbeat');
            result.event(beat).ibi = 812;
            result.event(beat).bini = 3;

            after = TransTools.AlignUrevents(result, before);

            testCase.verifyEqual(after.urevent(3).ibi, 812);
            testCase.verifyEmpty(after.urevent(1).ibi);
            testCase.verifyFalse(isfield(after.urevent, 'bini'));
        end

        function anEventAddedAgainIsNotCopied(testCase)
        %ANEVENTADDEDAGAINISNOTCOPIED  Heartbeats replaces the beats of an
        %   earlier run; those at the same place keep the entry they had.
            before = TransTools.AlignUrevents(UreventTest.recording());
            once = TransTools.AlignUrevents(UreventTest.withEvent(before, 'heartbeat', 250), before);
            kept = once;
            kept.event(strcmp({kept.event.type}, 'heartbeat')) = [];

            again = TransTools.AlignUrevents(UreventTest.withEvent(kept, 'heartbeat', 250), kept);

            testCase.verifyEqual(numel(again.urevent), 5);
            UreventTest.verifyPointers(testCase, again);
        end

        function aToolboxsOwnEntriesStayAsItLeftThem(testCase)
        %ATOOLBOXSOWNENTRIESSTAYASITLEFTTHEM  As EYE-EEG's addevents leaves them:
        %   appended, with pointers already right. Its order is the toolbox's, on
        %   any data (see TransTools.AlignUrevents). An event a later step adds
        %   is what sorts the table, as EEGLAB's own insert does.
            for format = {'CONTINUOUS', 'EPOCHED'}
                before = TransTools.AlignUrevents(UreventTest.recording());
                before.DataFormat = format{1};
                result = before;
                result.urevent(end + 1) = result.urevent(1);
                result.urevent(end).type = 'L_saccade';
                result.urevent(end).latency = 150;
                added = result.event(1);
                added.type = 'L_saccade';
                added.latency = 150;
                added.urevent = numel(result.urevent);
                result.event = [result.event(1), added, result.event(2:end)];

                after = TransTools.AlignUrevents(result, before);

                testCase.verifyEqual(after, result, format{1});
            end

            result.DataFormat = 'CONTINUOUS';
            later = TransTools.AlignUrevents(UreventTest.withEvent(result, 'heartbeat', 250), result);
            testCase.verifyEqual([later.urevent.latency], [100 150 200 250 300 400]);
            UreventTest.verifyPointers(testCase, later);
        end

        function anotherTypeAtTheSamePlaceIsANewEntry(testCase)
            before = TransTools.AlignUrevents(UreventTest.recording());

            after = TransTools.AlignUrevents(UreventTest.withEvent(before, 'heartbeat', 200), before);

            testCase.verifyEqual(sort({after.urevent.type}), sort({'S1', 'R', 'heartbeat', 'S1', 'R'}));
            UreventTest.verifyPointers(testCase, after);
        end

        function aLatencyIsTakenBackAcrossACut(testCase)
        %ALATENCYISTAKENBACKACROSSACUT  50 samples were cut before latency 150,
        %   so what lies at 170 now lay at 220, by eeg_urlatency's sum.
            testCase.assumeEeglab();
            before = TransTools.AlignUrevents(UreventTest.recording());
            cut = before;
            cut.event(1).latency = 100;
            for k = 2:numel(cut.event)
                cut.event(k).latency = cut.event(k).latency - 50;
            end
            cut.event(end + 1) = cut.event(1);
            cut.event(end).type = 'boundary';
            cut.event(end).latency = 149.5;
            cut.event(end).duration = 50;
            cut.event(end).urevent = [];
            [~, order] = sort([cut.event.latency]);
            cut.event = cut.event(order);

            after = TransTools.AlignUrevents(UreventTest.withEvent(cut, 'heartbeat', 170), cut);

            at = find(strcmp({after.urevent.type}, 'heartbeat'));
            testCase.verifyEqual(after.urevent(at).latency, eeg_urlatency(cut.event, 170));
            testCase.verifyEqual(after.urevent(at).latency, 220);
        end

        function aBoundaryIsNotAnEventOfTheRecording(testCase)
            before = TransTools.AlignUrevents(UreventTest.recording());

            after = TransTools.AlignUrevents(UreventTest.withEvent(before, 'boundary', 250), before);

            testCase.verifyEqual(numel(after.urevent), numel(before.urevent));
            at = strcmp({after.event.type}, 'boundary');
            testCase.verifyEmpty(after.event(at).urevent);

            after = TransTools.AlignUrevents(UreventTest.withEvent(before, '-99', 250), before);
            testCase.verifyEqual(numel(after.urevent), numel(before.urevent), ...
                'EEGLAB''s other spelling of a boundary.');
        end

        function aTableLostByAStepComesBack(testCase)
        %ATABLELOSTBYASTEPCOMESBACK  eeg_checkset removes it when a step's new
        %   event list has no pointers. The events find their entries again, and
        %   what the step removed is still there, which a table made anew would
        %   not hold.
            before = TransTools.AlignUrevents(UreventTest.recording());
            result = before;
            result.event(2) = [];
            result.event = rmfield(result.event, 'urevent');
            result.urevent = [];

            after = TransTools.AlignUrevents(result, before);

            testCase.verifyEqual(after.urevent, before.urevent);
            testCase.verifyEqual([after.event.urevent], [1 3 4]);
        end

        function aTableLostWithTheRateChangedIsMadeAnew(testCase)
        %ATABLELOSTWITHTHERATECHANGEDISMADEANEW  The old table's latencies count
        %   samples of the old rate, so restoring it would misplace everything.
            before = TransTools.AlignUrevents(UreventTest.recording());
            result = before;
            result.srate = 50;
            result.event = rmfield(result.event, 'urevent');
            result.urevent = [];
            latency = num2cell([result.event.latency] / 2);
            [result.event.latency] = latency{:};

            after = TransTools.AlignUrevents(result, before);

            testCase.verifyEqual([after.urevent.latency], [50 100 150 200]);
        end

        function aTableEmptiedOnTrialsLeavesNoPointers(testCase)
        %ATABLEEMPTIEDONTRIALSLEAVESNOPOINTERS  pop_resample empties it on
        %   epoched data, which it cannot rescale, and leaves the pointers.
            EEG = TransTools.AlignUrevents(UreventTest.recording());
            EEG.DataFormat = 'EPOCHED';
            EEG.urevent = [];

            after = TransTools.AlignUrevents(EEG, EEG);

            testCase.verifyFalse(isfield(after.event, 'urevent'));
        end

        % ---- at the seam ---------------------------------------------------- %
        function aStepsNewEventGetsItsEntryWithoutKnowingOfTheTable(testCase)
        %ASTEPSNEWEVENTGETSITSENTRYWITHOUTKNOWINGOFTHETABLE  As Heartbeats and
        %   EyeTracking add events: a plain append, through TransTools.invoke.
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            fid = fopen(fullfile(folder, 'AddsAnEventStandIn.m'), 'w');
            fprintf(fid, '%s\n', 'function [EEG, options] = AddsAnEventStandIn(input, varargin)', ...
                'EEG = input;', 'added = EEG.event(1);', 'added.type = ''beat'';', ...
                'added.latency = 150;', 'added.urevent = [];', ...
                'EEG.event = [EEG.event(1), added, EEG.event(2:end)];', ...
                'options = struct();', 'end');
            fclose(fid);
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(folder));

            result = TransTools.invoke('AddsAnEventStandIn', UreventTest.recording(), struct());

            testCase.verifyEqual({result.urevent.type}, {'S1', 'beat', 'R', 'S1', 'R'});
            UreventTest.verifyPointers(testCase, result);
        end

        function aFirstStepThatRemovesEventsLeavesThemInTheTable(testCase)
        %AFIRSTSTEPTHATREMOVESEVENTSLEAVESTHEMINTHETABLE  A node with no table
        %   yet, a workspace saved before there was one, gets it from what the
        %   step received, not from what it kept.
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            fid = fopen(fullfile(folder, 'RemovesAnEventStandIn.m'), 'w');
            fprintf(fid, '%s\n', 'function [EEG, options] = RemovesAnEventStandIn(input, varargin)', ...
                'EEG = input;', 'EEG.event(2) = [];', 'options = struct();', 'end');
            fclose(fid);
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(folder));

            result = TransTools.invoke('RemovesAnEventStandIn', UreventTest.recording(), struct());

            testCase.verifyEqual({result.urevent.type}, {'S1', 'R', 'S1', 'R'});
            testCase.verifyEqual([result.event.urevent], [1 3 4]);
        end

        function eyeEegsEventsStayAsItLeftThem(testCase)
        %EYEEEGSEVENTSSTAYASITLEFTTHEM  Its own addevents through the seam, as the
        %   EyeTracking plugin reaches it: the result is exactly the one addevents
        %   gives, whose table is out of order (see TransTools.AlignUrevents). The
        %   entries keep their own fields, and the epoch view, which does not walk
        %   the table by position, still measures the next saccade correctly.
            testCase.assumeEeglab();
            root = EEGLabEnvironment.findInstalled('eye-eeg', 'pop_importeyetracker.m', 'eye-eeg-1.01');
            testCase.assumeNotEmpty(root, 'EYE-EEG is not installed.');
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'internal')));
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            fid = fopen(fullfile(folder, 'AddsSaccadesStandIn.m'), 'w');
            fprintf(fid, '%s\n', 'function [EEG, options] = AddsSaccadesStandIn(input, varargin)', ...
                'EEG = addevents(input, [320 5 1.2; 810 6 2.2; 1310 4 3.1], ...', ...
                '    {''latency'', ''duration'', ''sac_amplitude''}, ''L_saccade'');', ...
                'options = struct();', 'end');
            fclose(fid);
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(folder));
            EEG = UreventTest.continuousSet();
            EEG.event = EEG.event(strcmp({EEG.event.type}, 'S1'));

            result = TransTools.invoke('AddsSaccadesStandIn', EEG, struct());

            direct = addevents(TransTools.AlignUrevents(EEG), [320 5 1.2; 810 6 2.2; 1310 4 3.1], ...
                {'latency', 'duration', 'sac_amplitude'}, 'L_saccade');
            testCase.verifyEqual(result.urevent, direct.urevent);
            testCase.verifyEqual(result.event, direct.event);
            UreventTest.verifyPointers(testCase, result);
            saccade = strcmp({result.urevent.type}, 'L_saccade');
            testCase.verifyEqual([result.urevent(saccade).sac_amplitude], [1.2 2.2 3.1]);

            key = epochSortKeys(pop_epoch(result, {'S1'}, [-0.2 0.8]));
            key = key(strcmp({key.id}, 'next:L_saccade'));
            testCase.verifyEqual(key.values, [200 100 100], 'AbsTol', 1e-6);
        end

        function aRealCutLeavesTheTableAndItsBoundaryOut(testCase)
        %AREALCUTLEAVESTHETABLEANDITSBOUNDARYOUT  SelectData through EEGLAB's
        %   pop_select: the boundary it inserts is no event of the recording,
        %   and what is added afterwards is placed where it lay in it.
            testCase.assumeEeglab();
            EEG = UreventTest.continuousSet();
            options = UreventTest.selection(EEG, struct('mode', '(off)', 'indices', []));
            options.time = struct('mode', 'Remove', 'range', [5 7]);
            cut = TransTools.invoke('SelectData', EEG, options);

            testCase.verifyEqual(numel(cut.urevent), numel(EEG.event));
            testCase.verifyEqual([cut.urevent.latency], [EEG.event.latency]);
            atCut = strcmp({cut.event.type}, 'boundary');
            testCase.verifyEqual(nnz(atCut), 1);
            testCase.verifyEmpty(cut.event(atCut).urevent);

            added = cut.event(atCut).latency + 10;
            result = UreventTest.withEvent(cut, 'heartbeat', added);
            after = TransTools.AlignUrevents(result, cut);
            at = strcmp({after.urevent.type}, 'heartbeat');
            testCase.verifyEqual(after.urevent(at).latency, eeg_urlatency(cut.event, added));
            testCase.verifyGreaterThan(after.urevent(at).latency, 700);
        end

        function eeglabsOwnContextFindsTheEventAfterEachTrial(testCase)
        %EEGLABSOWNCONTEXTFINDSTHEEVENTAFTEREACHTRIAL  What the table is for.
        %   Trials are cut, one is removed and the dataset exported, by now
        %   holding only the stimuli; eeg_context still finds the response
        %   after each of them, in the table.
            testCase.assumeEeglab();
            EEG = UreventTest.continuousSet();
            cut = TransTools.invoke('DefineBins', EEG, struct('script', 'bin 1 "S" "S1"', ...
                'epoch', struct('lo', -200, 'hi', 800, 'unit', 'ms')));
            testCase.verifyEqual(numel(cut.urevent), 6, 'The responses stay in the table.');
            kept = TransTools.invoke('SelectData', cut, ...
                UreventTest.selection(cut, struct('mode', 'Remove', 'indices', 1)));
            exported = eeg_checkset(prepareSetExport(kept));

            testCase.verifyFalse(any(strcmp({exported.event.type}, 'R')), ...
                'The responses are no longer events of the dataset.');
            [~, ~, ~, delays] = eeg_context(exported, {'S1'}, {'R'}, 1);

            testCase.verifyEqual(delays', [300 620], 'AbsTol', 1e-6);
        end

        function resamplingKeepsTheTableInStep(testCase)
        %RESAMPLINGKEEPSTHETABLEINSTEP  pop_resample rescales it; the seam
        %   leaves that alone, and a delay in ms comes out the same.
            testCase.assumeEeglab();
            EEG = UreventTest.continuousSet();

            result = TransTools.invoke('Resample', EEG, struct('NewRate', 50));

            testCase.verifyEqual(numel(result.urevent), numel(result.event));
            UreventTest.verifyPointers(testCase, result);
            latency = [result.urevent.latency];
            testCase.verifyEqual((latency(2) - latency(1)) / 50 * 1000, 450, 'AbsTol', 20);
        end

        function anExportedSetKeepsTheTable(testCase)
        %ANEXPORTEDSETKEEPSTHETABLE  Through EEGLAB's own file, so a colleague
        %   opening it in EEGLAB gets what eeg_context needs.
            testCase.assumeEeglab();
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            EEG = UreventTest.continuousSet();
            cut = TransTools.invoke('DefineBins', EEG, struct('script', 'bin 1 "S" "S1"', ...
                'epoch', struct('lo', -200, 'hi', 800, 'unit', 'ms')));

            pop_saveset(prepareSetExport(cut), 'filename', 'x.set', 'filepath', folder);
            loaded = pop_loadset('filename', 'x.set', 'filepath', folder);

            testCase.verifyEqual(numel(loaded.urevent), 6);
            [~, ~, ~, delays] = eeg_context(loaded, {'S1'}, {'R'}, 1);
            testCase.verifyEqual(delays', [450 300 620], 'AbsTol', 1e-6);
        end
    end

    methods
        function assumeEeglab(testCase)
            testCase.assumeNotEmpty(which('eeg_checkset'), 'EEGLAB is not on the path.');
        end
    end

    methods (Static)
        function EEG = recording()
        %RECORDING  Four events, plain enough to read the table by eye.
            EEG = struct('srate', 100, 'data', zeros(1, 1000), 'DataFormat', 'CONTINUOUS', ...
                'event', struct('type', {'S1', 'R', 'S1', 'R'}, 'latency', {100, 200, 300, 400}, ...
                    'duration', {0, 0, 0, 0}));
        end

        function EEG = withEvent(EEG, type, latency)
        %WITHEVENT  EEG with one event added at LATENCY, no pointer, in order.
            added = EEG.event(1);
            added.type = type;
            added.latency = latency;
            added.urevent = [];
            EEG.event(end + 1) = added;
            [~, order] = sort([EEG.event.latency]);
            EEG.event = EEG.event(order);
        end

        function verifyPointers(testCase, EEG)
        %VERIFYPOINTERS  Every event's entry is that event: its type, at its
        %   latency (these fixtures have no cuts).
            for i = 1:numel(EEG.event)
                entry = EEG.urevent(EEG.event(i).urevent);
                testCase.verifyEqual(entry.type, EEG.event(i).type);
                testCase.verifyEqual(entry.latency, EEG.event(i).latency);
            end
        end

        function EEG = continuousSet()
        %CONTINUOUSSET  A real EEGLAB set at 100 Hz: three stimuli, with a
        %   response 450, 300 and 620 ms after them.
            base = eeg_emptyset();
            base.data = randn(2, 2000);
            base.nbchan = 2;
            base.pnts = 2000;
            base.trials = 1;
            base.srate = 100;
            base.xmin = 0;
            base.xmax = 19.99;
            base.times = (0:1999) / 100;
            base.chanlocs = struct('labels', {'Cz', 'Pz'});
            base.DataFormat = 'CONTINUOUS';
            base.DataType = 'TIMEDOMAIN';
            base.setname = 'fixture';
            base.event = struct('type', {'S1', 'R', 'S1', 'R', 'S1', 'R'}, ...
                'latency', {300, 345, 800, 830, 1300, 1362});
            EEG = base;
        end

        function opts = selection(EEG, trials)
        %SELECTION  SelectData's options with only a trial selection on.
            opts = struct( ...
                'channels', struct('mode', '(off)', 'labels', {{}}), ...
                'time',     struct('mode', '(off)', 'range', [0 0]), ...
                'points',   struct('mode', '(off)', 'range', [1, size(EEG.data, 2)]), ...
                'trials',   trials);
        end
    end
end
