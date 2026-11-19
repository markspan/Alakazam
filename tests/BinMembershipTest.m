classdef BinMembershipTest < matlab.unittest.TestCase
%BINMEMBERSHIPTEST  TransTools.BinMembership: the one store of which trials
%   (or events) are in which bin, and the conversion of datasets saved
%   before it.
%
%   THE STORE is .bini and .binrt on each trial (EEG.epoch) of epoched data
%   and on each event of continuous data; EEG.bindesc lists no members. The
%   cases pinned here are what that has to mean: DefineBins writes it, with a
%   reaction time per bin, so a trial in two bins keeps two; every reader
%   gets the same answer from it; and an old dataset, whose bins listed
%   their trials, reads exactly as the old readers read it (the list
%   believed, the trial tags only where a bin had none) and is converted
%   before a step sees it. SelectData's part (the tags follow pop_select)
%   is in SelectDataTest.
%
%   Run with: runtests('tests/BinMembershipTest.m').
%
%   See also TRANSTOOLS.BINMEMBERSHIP, DEFINEBINS.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Transformations', 'DefineBins'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        % ---- what DefineBins writes --------------------------------------- %
        function definedBinsAreOnTheEventsWithTheirReactionTimes(testCase)
        %DEFINEDBINSAREONTHEEVENTSWITHTHEIRREACTIONTIMES  Continuous data:
        %   each event carries its bins and, beside them, what each bin
        %   captured; the bins list no members.
            EEG = DefineBins(BinMembershipTest.recording(), struct('script', ...
                'bin 1 "Answered" "S1" and next("R") within (0,1000] ms', 'tagsOnly', true));

            testCase.verifyFalse(any(isfield(EEG.bindesc, {'events', 'trials', 'rt'})));
            [members, rts] = TransTools.BinMembership.of(EEG, 1);
            testCase.verifyEqual(members, [1 4 7], 'The stimuli at 300, 800 and 1600 ms.');
            testCase.verifyEqual(rts, [450 300 620], 'AbsTol', 1e-9);
            testCase.verifyEqual(EEG.event(1).binrt, 450, 'AbsTol', 1e-9);
            testCase.verifyEqual(EEG.bindesc(1).n, 3);
        end

        function aTrialInTwoBinsKeepsTwoReactionTimes(testCase)
        %ATRIALINTWOBINSKEEPSTWOREACTIONTIMES  One stimulus, two bins that
        %   capture different responses: the trial is in both, with the time
        %   of each bin's own response, which one list per bin could not hold
        %   for a trial in one place.
            EEG = DefineBins(BinMembershipTest.recording(), struct('script', sprintf( ...
                ['bin 1 "To R" "S1" and next("R") within (0,1000] ms\n' ...
                 'bin 2 "To Q" "S1" and next("Q") within (0,1000] ms']), ...
                'epoch', struct('lo', -200, 'hi', 800, 'unit', 'ms')));

            testCase.verifyEqual(EEG.epoch(1).bini, [1 2]);
            testCase.verifyEqual(EEG.epoch(1).binrt, [450 700], 'AbsTol', 1e-9);
            [~, toR] = TransTools.BinMembership.of(EEG, 1);
            [~, toQ] = TransTools.BinMembership.of(EEG, 2);
            testCase.verifyEqual(toR(1), 450, 'AbsTol', 1e-9);
            testCase.verifyEqual(toQ(1), 700, 'AbsTol', 1e-9);
            testCase.verifyEqual(TransTools.BinMembership.ofTrial(EEG, 1), [1 2]);
        end

        function epochedTrialsCarryTheirBins(testCase)
            EEG = DefineBins(BinMembershipTest.recording(), struct('script', sprintf( ...
                'bin 1 "Stimulus" "S1"\nbin 2 "Answered" "S1" and next("R") within (0,1000] ms'), ...
                'epoch', struct('lo', -200, 'hi', 800, 'unit', 'ms')));

            testCase.verifyFalse(any(isfield(EEG.bindesc, {'events', 'trials', 'rt'})));
            testCase.verifyEqual(TransTools.BinTrials(EEG, 1), 1:4);
            testCase.verifyEqual(TransTools.BinTrials(EEG, 2), [1 2 4]);
            testCase.verifyEqual(TransTools.BinMembership.ofTrial(EEG, 3), 1);
            testCase.verifyEqual({EEG.epoch.binrt}, {[NaN 450], [NaN 300], NaN, [NaN 620]});
        end

        function taggingEpochedDataAgainUpdatesTheTrials(testCase)
        %TAGGINGEPOCHEDDATAAGAINUPDATESTHETRIALS  DefineBins without a
        %   window on trials already cut tags the events; the trials take the
        %   new tags, or every reader would still see the old bins.
            EEG = DefineBins(BinMembershipTest.recording(), struct('script', ...
                'bin 1 "Stimulus" "S1"', 'epoch', struct('lo', -200, 'hi', 800, 'unit', 'ms')));

            again = DefineBins(EEG, struct('script', 'bin 7 "Seven" "S1"'));

            testCase.verifyEqual([again.epoch.bini], [7 7 7 7]);
            testCase.verifyEqual(TransTools.BinTrials(again, 1), 1:4);
        end

        % ---- reading ---------------------------------------------------------- %
        function aSingleTrialIsReadFromItsEvent(testCase)
        %ASINGLETRIALISREADFROMITSEVENT  pop_select clears EEG.epoch when it
        %   leaves one trial, and the event's .epoch with it.
            EEG = struct('data', zeros(1, 10), 'DataFormat', 'EPOCHED', ...
                'event', struct('type', 'S1', 'latency', 3, 'bini', [1 2], 'binrt', [NaN 250]), ...
                'epoch', [], 'bindesc', struct('index', {1, 2}, 'label', {'A', 'B'}, 'combo', {[], []}));

            [members, rts] = TransTools.BinMembership.of(EEG, 2);

            testCase.verifyEqual(members, 1);
            testCase.verifyEqual(rts, 250);
        end

        function anAverageHasNoTrials(testCase)
            EEG = struct('data', zeros(2, 10, 2), 'DataFormat', 'AVERAGED', ...
                'bindesc', struct('index', {1, 2}, 'label', {'A', 'B'}, 'trials', {[1 2], [3 4]}));

            testCase.verifyEmpty(TransTools.BinMembership.of(EEG, 1));
            migrated = TransTools.BinMembership.migrate(EEG);
            testCase.verifyFalse(isfield(migrated.bindesc, 'trials'));
        end

        % ---- old datasets ----------------------------------------------------- %
        function anOldEpochedDatasetIsReadByItsLists(testCase)
        %ANOLDEPOCHEDDATASETISREADBYITSLISTS  The lists were believed over the
        %   trial tags, which could be stale; they still are, and the
        %   reaction times come along.
            EEG = struct('data', zeros(1, 10, 4), 'DataFormat', 'EPOCHED', ...
                'epoch', struct('bini', {1, 1, 1, 1}), ...
                'bindesc', struct('index', {1, 2}, 'label', {'A', 'B'}, 'combo', {[], []}, ...
                    'events', {[5 6], [7 8]}, 'trials', {[1 2], [3 4]}, 'rt', {[100 200], [NaN 400]}));

            testCase.verifyEqual(TransTools.BinTrials(EEG, 2), [3 4]);
            migrated = TransTools.BinMembership.migrate(EEG);
            testCase.verifyEqual({migrated.epoch.bini}, {1, 1, 2, 2});
            testCase.verifyEqual({migrated.epoch.binrt}, {100, 200, NaN, 400});
            testCase.verifyFalse(any(isfield(migrated.bindesc, {'events', 'trials', 'rt'})));
            testCase.verifyEqual(TransTools.BinMembership.migrate(migrated), migrated, ...
                'A dataset in the new form is left as it is.');
        end

        function anOldBinWithoutAListReadsTheTrialTags(testCase)
            EEG = struct('data', zeros(1, 10, 3), 'DataFormat', 'EPOCHED', ...
                'epoch', struct('bini', {[1 2], 2, 1}), ...
                'bindesc', struct('index', {1, 2}, 'label', {'A', 'B'}, 'trials', {[1 3], []}));

            testCase.verifyEqual(TransTools.BinTrials(EEG, 1), [1 3]);
            testCase.verifyEqual(TransTools.BinTrials(EEG, 2), [1 2]);
        end

        function anOldContinuousDatasetGetsItsReactionTimesOnTheEvents(testCase)
            EEG = struct('data', zeros(1, 1000), 'DataFormat', 'CONTINUOUS', ...
                'event', struct('type', {'S1', 'R', 'S1'}, 'latency', {10, 50, 300}, ...
                    'bini', {1, [], 1}), ...
                'bindesc', struct('index', 1, 'label', 'A', 'combo', [], ...
                    'events', [1 3], 'rt', [400 NaN], 'n', 2));

            migrated = TransTools.BinMembership.migrate(EEG);

            testCase.verifyEqual({migrated.event.binrt}, {400, zeros(1, 0), NaN});
            testCase.verifyFalse(any(isfield(migrated.bindesc, {'events', 'rt'})));
            [members, rts] = TransTools.BinMembership.of(EEG, 1);
            testCase.verifyEqual(members, [1 3]);
            testCase.verifyEqual(rts, [400 NaN]);
        end

        function aStepNeverSeesTheOldForm(testCase)
        %ASTEPNEVERSEESTHEOLDFORM  TransTools.invoke converts the input, so no
        %   transformation has to know the lists existed.
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            fid = fopen(fullfile(folder, 'RecordInputStandIn.m'), 'w');
            fprintf(fid, '%s\n', 'function [EEG, options] = RecordInputStandIn(input, varargin)', ...
                'setappdata(groot, ''BinMembershipTestInput'', input);', ...
                'EEG = input;', 'options = struct();', 'end');
            fclose(fid);
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(folder));
            testCase.addTeardown(@() rmappdata(groot, 'BinMembershipTestInput'));
            old = struct('data', zeros(1, 10, 2), 'DataFormat', 'EPOCHED', ...
                'chanlocs', struct('labels', 'Cz'), ...
                'bindesc', struct('index', 1, 'label', 'A', 'trials', 2, 'rt', 330));

            TransTools.invoke('RecordInputStandIn', old, struct());

            seen = getappdata(groot, 'BinMembershipTestInput');
            testCase.verifyFalse(isfield(seen.bindesc, 'trials'));
            testCase.verifyEqual({seen.epoch.bini}, {zeros(1, 0), 1});
            testCase.verifyEqual(seen.epoch(2).binrt, 330);
        end

        function recountCountsWhatIsThere(testCase)
            EEG = struct('data', zeros(1, 10, 3), 'DataFormat', 'EPOCHED', ...
                'epoch', struct('bini', {[1 2], 2, 1}, 'binrt', {[NaN NaN], NaN, NaN}), ...
                'bindesc', struct('index', {1, 2, 3}, 'label', {'A', 'B', 'D'}, ...
                    'combo', {[], [], struct('bin', 1, 'coeff', 1)}, 'n', {9, 9, 'kept'}));

            EEG = TransTools.BinMembership.recount(EEG);

            testCase.verifyEqual({EEG.bindesc.n}, {2, 2, 'kept'});
        end
    end

    methods (Static)
        function EEG = recording()
        %RECORDING  100 Hz, 20 s: four stimuli, responses R within a second
        %   of three of them (450, 300 and 620 ms; the third stimulus's next R
        %   is 3.6 s on) and a Q 700 ms after the first. Sorted by latency,
        %   the stimuli are events 1, 4, 6 and 7.
            srate = 100;
            EEG = struct('data', randn(2, 2000), 'srate', srate, 'pnts', 2000, 'trials', 1, ...
                'nbchan', 2, 'xmin', 0, 'xmax', 19.99, 'times', (0:1999) * 10, ...
                'DataFormat', 'CONTINUOUS', 'chanlocs', struct('labels', {'Cz', 'Pz'}), ...
                'event', struct('type', {'S1', 'R', 'S1', 'R', 'S1', 'S1', 'R', 'Q'}, ...
                                'latency', {300, 345, 800, 830, 1300, 1600, 1662, 370}));
            [~, order] = sort([EEG.event.latency]);
            EEG.event = EEG.event(order);
        end
    end
end
