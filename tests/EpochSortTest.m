classdef EpochSortTest < matlab.unittest.TestCase
%EPOCHSORTTEST  EpochView's "Sort by": which per-trial values it offers
%   (epochSortKeys), the row order they give (EpochView.sortWithinGroups),
%   and, in one Slow case, a real view doing both.
%
%   THE VALUE HAS TO BELONG TO ITS OWN TRIAL, which is what most of these
%   pin. A reaction time is stored per bin, beside that bin's trial indices;
%   an event field lives on an event the trial points at, and a later
%   eeg_checkset can renumber the events under it. Either read wrongly gives
%   a sorted-looking image of the wrong order, which nothing on screen would
%   reveal.
%
%   Run with: runtests('tests/EpochSortTest.m').
%
%   See also EPOCHSORTKEYS, EPOCHVIEW.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Views'), fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Transformations', 'DefineBins'), fullfile(root, 'src', 'IO')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        % ---- what can be sorted by -------------------------------------- %
        function reactionTimesFollowTheirOwnTrials(testCase)
        %REACTIONTIMESFOLLOWTHEIROWNTRIALS  Stored per bin, beside that bin's
        %   trial indices and in their order, not the trials' own order.
            EEG = EpochSortTest.epoched();
            EEG.bindesc(1).trials = [3 1];
            EEG.bindesc(1).rt = [300 100];
            EEG.bindesc(2).trials = [2 4];
            EEG.bindesc(2).rt = [NaN 400];

            key = EpochSortTest.keyWithId(epochSortKeys(EEG), 'rt');

            testCase.verifyEqual(key.values, [100 NaN 300 400]);
            testCase.verifyTrue(key.timeMs);
        end

        function durationIsInMilliseconds(testCase)
        %DURATIONISINMILLISECONDS  EEGLAB keeps it in samples; the line it is
        %   drawn as sits on a time axis in ms.
            EEG = EpochSortTest.epoched();     % 500 Hz

            key = EpochSortTest.keyWithId(epochSortKeys(EEG), 'field:duration');

            testCase.verifyEqual(key.values, [100 50 150 75] * 2);
            testCase.verifyEqual(key.label, 'Event duration (ms)');
            testCase.verifyTrue(key.timeMs);
        end

        function aFieldThatIsNotATimeIsNotDrawn(testCase)
            key = EpochSortTest.keyWithId(epochSortKeys(EpochSortTest.epoched()), 'field:pupil');

            testCase.verifyEqual(key.values, [4 3 2 1]);
            testCase.verifyFalse(key.timeMs);
        end

        function whatEveryTrialSharesIsNotOffered(testCase)
        %WHATEVERYTRIALSHARESISNOTOFFERED  EYE-EEG writes 0 into every field
        %   that does not apply, so each fixation "has" a saccade amplitude of
        %   0; sorting by it would change nothing.
            ids = {epochSortKeys(EpochSortTest.epoched()).id};

            testCase.verifyFalse(ismember('field:sac_amplitude', ids));
            testCase.verifyFalse(ismember('field:latency', ids), ...
                'The latency is the trial''s place in the recording, which recording order already is.');
            testCase.verifyFalse(ismember('rt', ids), 'There is no reaction time here.');
        end

        function aRenumberedEventListStillFindsEachTrialsEvent(testCase)
        %ARENUMBEREDEVENTLISTSTILLFINDSEACHTRIALSEVENT  epoch(t).event is
        %   trusted only while that event still says it belongs to trial t.
            EEG = EpochSortTest.epoched();
            EEG.event = EEG.event([2 1 4 3]);         % renumbered under the epochs

            key = EpochSortTest.keyWithId(epochSortKeys(EEG), 'field:pupil');

            testCase.verifyEqual(key.values, [4 3 2 1]);
        end

        % ---- neighbouring events ----------------------------------------- %
        function neighboursAreMeasuredOnBothSidesWithinTheWindow(testCase)
        %NEIGHBOURSAREMEASUREDONBOTHSIDESWITHINTHEWINDOW  At 100 Hz: two
        %   trials locked to "stim" at samples 100 and 300, a "sac" between
        %   them, a boundary that is not an event of interest, and a "button"
        %   too late for the first trial's window.
            events = struct('type', {'stim', 'sac', 'boundary', 'stim', 'button'}, ...
                'latency', {100, 150, 200, 300, 395});

            context = TransTools.EpochNeighbours(events, [100 300], 100, [-2000 1000]);

            testCase.verifyEqual(context.types, {'stim', 'sac', 'button'});
            testCase.verifyEqual(context.trials, 2);
            testCase.verifyEqual(context.next(2, :), [500 NaN]);
            testCase.verifyEqual(context.previous(2, :), [NaN -1500]);
            testCase.verifyEqual(context.next(1, :), [NaN NaN], ...
                'The next stim is 2000 ms on, past the window, and a trial is not its own neighbour.');
            testCase.verifyEqual(context.previous(1, :), [NaN -2000], ...
                'The window''s own edge still counts.');
            testCase.verifyEqual(context.next(3, :), [NaN 950]);
        end

        function neighboursAreOfferedPerType(testCase)
            EEG = EpochSortTest.epoched();
            EEG.etc.alz.epochNeighbours = struct('types', {{'sac', 'button'}}, ...
                'next', [300 120 NaN 450; NaN NaN NaN NaN], ...
                'previous', [-50 -80 -20 -60; -900 -700 -800 -950], 'trials', 4);

            keys = epochSortKeys(EEG);

            next = EpochSortTest.keyWithId(keys, 'next:sac');
            testCase.verifyEqual(next.values, [300 120 NaN 450]);
            testCase.verifyEqual(next.label, 'Next sac (ms)');
            testCase.verifyTrue(next.timeMs);
            previous = EpochSortTest.keyWithId(keys, 'previous:button');
            testCase.verifyEqual(previous.values, [-900 -700 -800 -950]);
            testCase.verifyFalse(ismember('next:button', {keys.id}), ...
                'No trial has a button after it, so there is nothing to sort by.');
        end

        function aNeighbourTableThatNoLongerFitsIsIgnored(testCase)
        %ANEIGHBOURTABLETHATNOLONGERFITSISIGNORED  One column per trial, or
        %   nothing: a column that belongs to another trial would sort the
        %   image wrongly and look right.
            EEG = EpochSortTest.epoched();
            EEG.etc.alz.epochNeighbours = struct('types', {{'sac'}}, ...
                'next', [300 120 450], 'previous', [-50 -80 -20], 'trials', 3);

            ids = {epochSortKeys(EEG).id};

            testCase.verifyFalse(any(startsWith(ids, {'next:', 'previous:'})));
        end

        function defineBinsRecordsTheNeighboursWhenItCutsEpochs(testCase)
        %DEFINEBINSRECORDSTHENEIGHBOURSWHENITCUTSEPOCHS  Measured while the
        %   latencies are still the recording's, before epoching rewrites
        %   them; a trial without a response in its window has none.
            srate = 100;
            EEG = struct('data', randn(2, 2000), 'srate', srate, 'pnts', 2000, 'trials', 1, ...
                'nbchan', 2, 'xmin', 0, 'xmax', 19.99, 'times', (0:1999) * 10, ...
                'DataFormat', 'CONTINUOUS', 'chanlocs', struct('labels', {'Cz', 'Pz'}), ...
                'event', struct('type', {'S1', 'R', 'S1', 'S1', 'R'}, ...
                                'latency', {300, 345, 800, 1300, 1362}));

            epoched = DefineBins(EEG, struct('script', 'bin 1 "Stimulus" "S1"', ...
                'epoch', struct('lo', -200, 'hi', 800, 'unit', 'ms')));

            context = epoched.etc.alz.epochNeighbours;
            response = strcmp(context.types, 'R');
            testCase.verifyEqual(context.trials, 3);
            testCase.verifyEqual(context.next(response, :), [450 NaN 620]);
            key = EpochSortTest.keyWithId(epochSortKeys(epoched), 'next:R');
            testCase.verifyEqual(key.values, [450 NaN 620]);
        end

        function aSingleTrialOffersNothing(testCase)
            EEG = EpochSortTest.epoched();
            EEG.data = EEG.data(:, :, 1);

            testCase.verifyEmpty(epochSortKeys(EEG));
        end

        % ---- the order they give ---------------------------------------- %
        function groupsStayWhole(testCase)
            order = EpochView.sortWithinGroups(1:6, [1 1 2 2 2 3], [5 4 3 9 1 2]);

            testCase.verifyEqual(order, [2 1 5 3 4 6]);
        end

        function tiesKeepRecordingOrderAndMissingValuesGoLast(testCase)
            order = EpochView.sortWithinGroups(1:5, zeros(1, 5), [2 NaN 1 2 NaN]);

            testCase.verifyEqual(order, [3 1 4 2 5]);
        end

        function reversedTheLargestComesFirstAndMissingValuesStillGoLast(testCase)
        %REVERSEDTHELARGESTCOMESFIRSTANDMISSINGVALUESSTILLGOLAST  The
        %   "Reverse the sort" setting: largest at the top, as EEGLAB's
        %   erpimage draws it, ties still in recording order, and a trial
        %   without a value still at the bottom rather than on top.
            order = EpochView.sortWithinGroups(1:5, zeros(1, 5), [2 NaN 1 2 NaN], true);

            testCase.verifyEqual(order, [1 4 3 2 5]);
            testCase.verifyEqual(EpochView.sortWithinGroups(1:6, [1 1 2 2 2 3], [5 4 3 9 1 2], true), ...
                [1 2 4 3 5 6], 'Groups stay whole when reversed too.');
        end

        function aTrialInTwoBinsIsSortedInEach(testCase)
        %ATRIALINTWOBINSISSORTEDINEACH  Grouped by bin, a trial in two bins
        %   is two rows; each is placed by the same value within its own bin.
            order = EpochView.sortWithinGroups([1 2 3 2 3], [1 1 1 2 2], [30 10 20]);

            testCase.verifyEqual(order, [2 3 1 2 3]);
        end
    end

    methods (Test, TestTags = {'Slow'})
        function theViewSortsItsRowsAndDrawsTheTimes(testCase)
            try
                fig = uifigure('Visible', 'off');
            catch ME
                testCase.assumeFail(['A uifigure could not be created here: ' ME.message]);
            end
            closeFig = onCleanup(@() delete(fig));
            view = EpochView(uitab(uitabgroup(fig)), EpochSortTest.epoched());
            labels = view.SortDropdown.Items;
            testCase.assertTrue(ismember('Event duration (ms)', labels));
            testCase.verifyTrue(all(isnan(view.SortLine.XData)), 'Recording order draws no line.');

            % The user's own "group by bin" and "reverse the sort" settings
            % decide whether the sort runs over all four trials or within
            % each bin (A: 1 and 3; B: 2 and 4), and in which direction;
            % every combination is checked rather than any skipped.
            grouped = AlakazamSettings.get("graphics", "epochImage", "groupByBin");
            reversed = AlakazamSettings.get("graphics", "epochImage", "reverseSort");
            if grouped && reversed
                byDuration = [3 1 4 2];
                byPupil = [1 3 2 4];
            elseif grouped
                byDuration = [1 3 2 4];
                byPupil = [3 1 4 2];
            elseif reversed
                byDuration = [3 1 4 2];
                byPupil = [1 2 3 4];
            else
                byDuration = [2 4 1 3];
                byPupil = [4 3 2 1];
            end
            durations = [200 100 300 150];

            view.SortDropdown.Value = find(strcmp(labels, 'Event duration (ms)')) - 1;
            view.redraw();

            testCase.verifyEqual(view.TrialOrder, byDuration);
            testCase.verifyEqual(view.SortLine.XData, durations(byDuration));
            testCase.verifyEqual(view.SortLine.YData, 1:4);
            testCase.verifySubstring(char(view.HeatAxes.Title.String), 'sorted by Event duration');

            view.SortDropdown.Value = find(strcmp(labels, 'Event: pupil')) - 1;
            view.redraw();
            testCase.verifyEqual(view.TrialOrder, byPupil);
            testCase.verifyTrue(all(isnan(view.SortLine.XData)), ...
                'A pupil size has no place on the time axis.');
        end
    end

    methods (Static)
        function EEG = epoched()
        %EPOCHED  Four trials at 500 Hz, each locked to its own event, with
        %   a duration (samples), a pupil size and a constant saccade
        %   amplitude, in DefineBins' epoched shape.
            srate = 500;
            times = -100:2:398;
            EEG = struct('data', randn(2, numel(times), 4), 'srate', srate, ...
                'times', times, 'pnts', numel(times), 'trials', 4, 'nbchan', 2, ...
                'xmin', times(1) / 1000, 'xmax', times(end) / 1000, 'DataFormat', 'EPOCHED', ...
                'chanlocs', struct('labels', {'Cz', 'Pz'}));
            EEG.event = struct('type', {'fix', 'fix', 'fix', 'fix'}, ...
                'latency', {51, 301, 551, 801}, 'duration', {100, 50, 150, 75}, ...
                'pupil', {4, 3, 2, 1}, 'sac_amplitude', {0, 0, 0, 0}, ...
                'bini', {1, 2, 1, 2}, 'epoch', {1, 2, 3, 4});
            EEG.epoch = struct('event', {1, 2, 3, 4}, 'eventtype', {'fix', 'fix', 'fix', 'fix'}, ...
                'eventlatency', {0, 0, 0, 0}, 'bini', {1, 2, 1, 2});
            EEG.bindesc = struct('index', {1, 2}, 'label', {'A', 'B'}, 'combo', {[], []}, ...
                'trials', {[1 3], [2 4]}, 'rt', {[NaN NaN], [NaN NaN]});
        end

        function key = keyWithId(keys, id)
            key = keys(strcmp({keys.id}, id));
            assert(isscalar(key), 'No sort key "%s".', id);
        end
    end
end
