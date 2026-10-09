classdef SelectDataTest < matlab.unittest.TestCase
%SELECTDATATEST  Unit tests for src/Transformations/SelectData/SelectData.m.
%
%   THE BUG THIS PINS. SelectDataDialog always builds a time/points range as
%   a ROW vector ([lo.Value hi.Value]), but jsondecode has no notion of row
%   vs column and turns any JSON numeric array back into a COLUMN on Apply
%   Template (confirmed directly: jsondecode(jsonencode([883 8594])) comes
%   back 2x1) -- so a SelectData step with a time or point range, saved as a
%   template and later applied, passed pop_select a column vector, which it
%   rejects outright ("Time/point range must contain 2 columns exactly").
%
%   Exercised here via the 'points' field (sample indices, no event/epoch
%   linkage needed): 'time' and 'points' share the exact same rangeArgs
%   helper and its one (:)' fix, so a bug fixed for one is fixed for both --
%   'time' cropping was separately confirmed end to end via a real
%   pop_epoch-derived dataset (a hand-built fixture has no .event/.epoch
%   linkage back to a continuous recording, which pop_select's own 'time'
%   handling on epoched data needs and this file's fixture does not build).
%   Every test here builds its options the way a template round trip would
%   (an explicit COLUMN, not the row shape the dialog itself produces), so a
%   revert of the (:)' fix in rangeArgs fails these for the right reason.
%
%   THE SECOND BUG THIS PINS. Removing or keeping trials went through
%   pop_select, which renumbers EEG.epoch but not DefineBins' per-bin trial
%   lists (EEG.bindesc(b).trials), and TransTools.BinTrials reads those first.
%   Found on FieldTrip's ERP tutorial recording: 192 trials, trials 1 to 3
%   removed, and Average failed with "Index must not exceed 189" because
%   every bin still listed its old trials. Where the old numbers stay in
%   range it averages the wrong trials instead. These cases cut real trials
%   with DefineBins (binnedTrials), so the bins, events and records are the
%   ones the app makes, and each trial carries a value that names it.
%
%   Run with: runtests('tests/SelectDataTest.m').
%
%   See also SELECTDATADIALOG.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Transformations', 'SelectData'), ...
                     fullfile(root, 'src', 'Transformations', 'DefineBins'), ...
                     fullfile(root, 'src', 'Transformations', 'Average'), ...
                     fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'IO'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function aTemplateRoundTrippedPointRangeStillCropsTheData(testCase)
        %ATEMPLATEROUNDTRIPPEDPOINTRANGESTILLCROPSTHEDATA  A column-shaped
        %   range (what jsondecode actually produces, see this class' own
        %   header comment) must still work, not throw.
            EEG = testCase.completeSet(makeTestEEG('nbchan', 2, 'trials', 2, 'epochMs', [-200, 596]));
            opts = offOptions(EEG);
            opts.points = struct('mode', 'Keep', 'range', [10; 50]); % COLUMN, not row
            result = SelectData(EEG, opts);
            testCase.verifyEqual(size(result.data, 2), 40);
            testCase.verifyLessThan(size(result.data, 2), size(EEG.data, 2), ...
                'The point-range crop should have dropped some samples.');
        end

        function aRowShapedRangeStillWorksToo(testCase)
        %AROWSHAPEDRANGESTILLWORKSTOO  The dialog's own native shape (a row)
        %   must keep working -- (:)' is a no-op on a row, not a special case.
            EEG = testCase.completeSet(makeTestEEG('nbchan', 2, 'trials', 2, 'epochMs', [-200, 596]));
            opts = offOptions(EEG);
            opts.points = struct('mode', 'Keep', 'range', [10, 50]); % ROW
            result = SelectData(EEG, opts);
            testCase.verifyEqual(size(result.data, 2), 40);
        end

        function removingTrialsAveragesEachBinOverTheTrialsLeft(testCase)
        %REMOVINGTRIALSAVERAGESEACHBINOVERTHETRIALSLEFT  The reported case:
        %   remove trials 1 to 3, then Average. Bin A held trials 1 3 5 7
        %   and keeps 5 and 7; bin B held 2 4 6 8 and keeps 4 6 8.
            epoched = binnedTrials(testCase);
            opts = offOptions(epoched);
            opts.trials = struct('mode', 'Remove', 'indices', [1 2 3]);

            averaged = Average(SelectData(epoched, opts));

            testCase.verifyEqual(averaged.data(:, :, 1), mean(epoched.data(:, :, [5 7]), 3), ...
                'AbsTol', 1e-12, 'Bin A should be the mean of trials 5 and 7.');
            testCase.verifyEqual(averaged.data(:, :, 2), mean(epoched.data(:, :, [4 6 8]), 3), ...
                'AbsTol', 1e-12, 'Bin B should be the mean of trials 4, 6 and 8.');
            testCase.verifyEqual([averaged.bindesc.n], [2 3]);
        end

        function removingTrialsRenumbersEachBinsTrialList(testCase)
        %REMOVINGTRIALSRENUMBERSEACHBINSTRIALLIST  The lists themselves, and
        %   what runs beside them: each kept trial keeps its own reaction
        %   time and event, and the count follows. Trials 4 to 8 become 1 to
        %   5, so A (old 5 7) is 2 4 and B (old 4 6 8) is 1 3 5.
            epoched = binnedTrials(testCase);
            opts = offOptions(epoched);
            opts.trials = struct('mode', 'Remove', 'indices', [1 2 3]);

            result = SelectData(epoched, opts);

            testCase.verifyEqual(result.bindesc(1).trials, [2 4]);
            testCase.verifyEqual(result.bindesc(2).trials, [1 3 5]);
            testCase.verifyEqual(result.bindesc(1).rt, [100 140], 'AbsTol', 1e-9, ...
                'Trial k answered after 20k ms, so A keeps the reaction times of 5 and 7.');
            testCase.verifyEqual(result.bindesc(2).rt, [80 120 160], 'AbsTol', 1e-9);
            testCase.verifyEqual(result.bindesc(1).events, epoched.bindesc(1).events([3 4]));
            testCase.verifyEqual(result.bindesc(2).events, epoched.bindesc(2).events([2 3 4]));
            testCase.verifyEqual([result.bindesc.n], [2 3]);
        end

        function keepingTrialsRenumbersInTheOrderEeglabKeepsThem(testCase)
        %KEEPINGTRIALSRENUMBERSINTHEORDEREEGLABKEEPSTHEM  pop_select sorts
        %   the trials it keeps and drops repeats, so keeping 8 2 5 2 keeps
        %   2 5 8 as trials 1 2 3: A (old 5) is 2, B (old 2 8) is 1 3.
            epoched = binnedTrials(testCase);
            opts = offOptions(epoched);
            opts.trials = struct('mode', 'Keep', 'indices', [8 2 5 2]);

            result = SelectData(epoched, opts);
            averaged = Average(result);

            testCase.verifyEqual(result.bindesc(1).trials, 2);
            testCase.verifyEqual(result.bindesc(2).trials, [1 3]);
            testCase.verifyEqual(result.bindesc(2).rt, [40 160], 'AbsTol', 1e-9);
            testCase.verifyEqual(averaged.data(:, :, 1), epoched.data(:, :, 5), 'AbsTol', 1e-12);
            testCase.verifyEqual(averaged.data(:, :, 2), mean(epoched.data(:, :, [2 8]), 3), ...
                'AbsTol', 1e-12);
            testCase.verifyEqual([averaged.bindesc.n], [1 2]);
        end

        function perTrialRecordsFollowTheKeptTrials(testCase)
        %PERTRIALRECORDSFOLLOWTHEKEPTTRIALS  The records kept beside the
        %   trials in EEG.etc.alz: the interpolation mask (channels x
        %   trials), and DefineBins' epochStart and epochNeighbours.
            epoched = binnedTrials(testCase);
            mask = false(2, 8);
            mask(1, [3 5]) = true;
            mask(2, [4 8]) = true;
            epoched.etc.alz.interpolated = mask;
            opts = offOptions(epoched);
            opts.trials = struct('mode', 'Remove', 'indices', [1 2 3]);

            result = SelectData(epoched, opts);

            kept = 4:8;
            testCase.verifyEqual(result.etc.alz.interpolated, mask(:, kept));
            testCase.verifyEqual(result.etc.alz.epochStart, epoched.etc.alz.epochStart(kept));
            neighbours = result.etc.alz.epochNeighbours;
            testCase.verifyEqual(neighbours.next, epoched.etc.alz.epochNeighbours.next(:, kept));
            testCase.verifyEqual(neighbours.previous, ...
                epoched.etc.alz.epochNeighbours.previous(:, kept));
            testCase.verifyEqual(neighbours.trials, 5);
        end
    end

    methods (Access = private)
        function EEG = completeSet(~, EEG)
        %COMPLETESET  The fixture laid over EEGLAB's own empty set, so
        %   pop_select finds every field it reads (.etc, chaninfo, dipfit,
        %   ...) instead of discovering them one error at a time. Same
        %   pattern as ReRefTest's/NativeExportEquivalenceTest's own
        %   completeSet.
            base = eeg_emptyset();
            f = fieldnames(EEG);
            for k = 1:numel(f)
                base.(f{k}) = EEG.(f{k});
            end
            EEG = base;
            EEG.xmin = EEG.times(1);
            EEG.xmax = EEG.times(end);
            EEG.setname = 'fixture';
        end

        function epoched = binnedTrials(testCase)
        %BINNEDTRIALS  Eight trials cut by DefineBins from a continuous
        %   recording, alternating between bin A (odd trials) and bin B (even
        %   trials). Trial k holds k^2 on Fz and -k on Cz for its whole epoch,
        %   so a mean says which trials it was taken over, and its response
        %   follows it by 20k ms, so each reaction time says which trial it
        %   belongs to.
            srate = 250;
            nTrials = 8;
            onset = 200 + (0:nTrials - 1) * 250;   % samples, one second apart
            data = zeros(2, 2200);
            types = cell(1, 2 * nTrials);
            latencies = zeros(1, 2 * nTrials);
            for k = 1:nTrials
                data(:, onset(k) - 25:onset(k) + 74) = repmat([k^2; -k], 1, 100);
                types{2 * k - 1} = char('A' + mod(k + 1, 2));   % A for odd k, B for even
                latencies(2 * k - 1) = onset(k);
                types{2 * k} = 'R';
                latencies(2 * k) = onset(k) + 5 * k;       % 20k ms later
            end
            continuous = makeTestEEG('nbchan', 2, 'labels', {'Fz', 'Cz'}, ...
                'DataFormat', 'CONTINUOUS', 'epochMs', [0, (size(data, 2) - 1) / srate * 1000]);
            continuous.data = data;
            continuous.times = (0:size(data, 2) - 1) / srate;
            continuous.event = struct('type', types, 'latency', num2cell(latencies));
            continuous = testCase.completeSet(continuous);

            script = sprintf(['epoch [-100,300] ms\n' ...
                'bin 1 "A" : "A" and next("R") within (0,600] ms\n' ...
                'bin 2 "B" : "B" and next("R") within (0,600] ms']);
            epoched = DefineBins(continuous, struct('script', script));

            testCase.assertEqual(size(epoched.data, 3), nTrials);
            testCase.assertEqual(epoched.bindesc(1).trials, [1 3 5 7]);
            testCase.assertEqual(epoched.bindesc(2).trials, [2 4 6 8]);
            testCase.assertEqual(squeeze(epoched.data(1, 1, :))', (1:nTrials).^2);
        end
    end
end

function opts = offOptions(EEG)
%OFFOPTIONS  Every SelectData field switched off, matching SelectDataDialog's
%   own default shape -- a test then turns on just the one field it exercises.
    opts = struct( ...
        'channels', struct('mode', '(off)', 'labels', {{}}), ...
        'time',     struct('mode', '(off)', 'range', [0 0]), ...
        'points',   struct('mode', '(off)', 'range', [1, size(EEG.data, 2)]), ...
        'trials',   struct('mode', '(off)', 'indices', []));
end
