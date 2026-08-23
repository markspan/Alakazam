classdef ManualRejectTest < matlab.unittest.TestCase
%MANUALREJECTTEST  Unit tests for
%   src/Transformations/ManualReject/ManualReject.m.
%
%   ManualReject is always called in "script mode" here (a stored
%   options struct with .flags/.scope/.channelMode, exactly what
%   ManualRejectDialog itself returns), never interactively -- the dialog
%   is a uifigure and is not exercised by this file. What IS genuinely
%   Alakazam's own and worth testing: the two validation guards, the
%   Whole-epoch/This-channel-only Scope branches (plain NaN assignment,
%   the same as ArtefactDetect's own), the "nothing flagged" no-op
%   shortcut, and the mismatched-flags-shape replay guard.
%
%   The Interpolate channel-mode calls straight into EEGLAB's own
%   eeg_interp -- not tested for numerical correctness here, matching
%   InterpolateTest.m's own stated philosophy for pop_interp. What IS
%   tested (interpolatedCellIsScopedToItsOwnTrialOnly, gated behind an
%   assumeTrue skip if EEGLAB is unavailable) is that ManualReject's own
%   per-trial scoping actually works: flagging one trial does not touch
%   the same channel in any other trial.
%
%   Run with: runtests('tests/ManualRejectTest.m').
%
%   See also MAKETESTEEG, ARTEFACTDETECTTEST, INTERPOLATETEST.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations', 'ManualReject')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'tests', 'fixtures')));
        end
    end

    methods (Test)
        function rejectsDataWithNoData(testCase)
            EEG = struct('data', [], 'DataFormat', 'EPOCHED');
            testCase.verifyError(@() ManualReject(EEG, struct('flags', [])), 'Alakazam:ManualReject');
        end

        function rejectsContinuousData(testCase)
            EEG = makeTestEEG('DataFormat', 'CONTINUOUS');
            testCase.verifyError(@() ManualReject(EEG, struct('flags', [])), 'Alakazam:ManualReject');
        end

        function noFlagsIsANoOp(testCase)
            EEG = makeTestEEG();
            flags = false(EEG.nbchan, EEG.trials);
            opts = struct('flags', flags, 'scope', 'Whole epoch', 'channelMode', 'NaN');

            [result, ~] = ManualReject(EEG, opts);

            testCase.verifyEqual(result.data, EEG.data);
        end

        function wholeEpochScopeNansEveryFlaggedTrial(testCase)
        %WHOLEEPOCHSCOPENANSEVERYFLAGGEDTRIAL  Flagging just one channel in
        %   a trial, under Whole-epoch scope, NaNs the ENTIRE trial (every
        %   channel), leaving every other trial untouched -- the same
        %   "one bad channel condemns the whole epoch" rule
        %   ArtefactDetect's own Whole-epoch scope applies.
            EEG = makeTestEEG();
            flags = false(EEG.nbchan, EEG.trials);
            flags(1, 2) = true;   % channel 1, trial 2 only
            opts = struct('flags', flags, 'scope', 'Whole epoch', 'channelMode', 'NaN');

            [result, ~] = ManualReject(EEG, opts);

            testCase.verifyTrue(all(isnan(result.data(:, :, 2)), 'all'));
            testCase.verifyEqual(result.data(:, :, [1 3 4]), EEG.data(:, :, [1 3 4]));
        end

        function singleChannelScopeNansOnlyTheFlaggedCell(testCase)
        %SINGLECHANNELSCOPENANSONLYTHEFLAGGEDCELL  Under This-channel-only
        %   scope with NaN treatment, only the flagged (channel, trial)
        %   cell is NaN'd -- the rest of that trial's other channels, and
        %   this channel's other trials, are untouched.
            EEG = makeTestEEG();
            flags = false(EEG.nbchan, EEG.trials);
            flags(1, 2) = true;
            opts = struct('flags', flags, 'scope', 'This channel only', 'channelMode', 'NaN');

            [result, ~] = ManualReject(EEG, opts);

            testCase.verifyTrue(all(isnan(result.data(1, :, 2))));
            testCase.verifyEqual(result.data(2:end, :, 2), EEG.data(2:end, :, 2));
            testCase.verifyEqual(result.data(:, :, [1 3 4]), EEG.data(:, :, [1 3 4]));
        end

        function mismatchedFlagsShapeThrowsAFriendlyError(testCase)
        %MISMATCHEDFLAGSSHAPETHROWSAFRIENDLYERROR  Replaying flags whose
        %   size does not match this dataset's own channel/trial count
        %   (e.g. recorded by walking through a different recording) is
        %   rejected rather than silently misapplied to the wrong cells.
            EEG = makeTestEEG();
            opts = struct('flags', false(1, 1), 'scope', 'Whole epoch', 'channelMode', 'NaN');

            try
                ManualReject(EEG, opts);
                testCase.verifyFail('Expected ManualReject to throw.');
            catch err
                testCase.verifyEqual(err.identifier, 'Alakazam:ManualReject');
                testCase.verifySubstring(err.message, 'do not match this dataset''s shape');
            end
        end

        function interpolatedCellIsScopedToItsOwnTrialOnly(testCase)
        %INTERPOLATEDCELLISSCOPEDTOITSOWNTRIALONLY  Flagging (channel 1,
        %   trial 2) with Interpolate treatment changes only that cell:
        %   it is no longer equal to (or NaN like) the original data, but
        %   channel 1's OTHER trials are untouched -- proving
        %   interpolateFlaggedCells' own per-trial copy actually scopes
        %   EEGLAB's reconstruction to the one flagged trial, not the
        %   whole channel. Does not check the reconstructed VALUE itself
        %   (that is EEGLAB's own eeg_interp maths, out of scope here,
        %   same as InterpolateTest.m's own stated philosophy for
        %   pop_interp).
            testCase.assumeTrue(~isempty(which('eeglab')), ...
                'EEGLAB not found on the MATLAB path -- skipping this test.');
            if isempty(which('eeg_interp'))
                eeglab('nogui');
            end
            testCase.assumeFalse(isempty(which('eeg_interp')), ...
                'EEGLAB''s eeg_interp is not available -- skipping this test.');

            % eeg_interp's own internals (via pop_select) reach for several
            % standard EEGLAB fields (xmin/xmax, .etc, .setname, ...)
            % makeTestEEG's minimal hand-built fixture does not carry -- its
            % own header comment says exactly this ("a transformation that
            % DOES call an EEGLAB pop_* function... still needs EEGLAB
            % initialised... this fixture does not attempt to hide that").
            % Start from EEGLAB's own eeg_emptyset() instead, which is a
            % complete, valid (if empty) EEG struct, then overlay this
            % test's own data/chanlocs/times onto it.
            labels = {'Fz', 'Cz', 'Pz', 'C3', 'C4'};
            fixture = makeTestEEG('nbchan', numel(labels), 'labels', labels);
            EEG = eeg_emptyset();
            EEG.data     = fixture.data;
            EEG.srate    = fixture.srate;
            EEG.nbchan   = fixture.nbchan;
            EEG.trials   = fixture.trials;
            EEG.pnts     = fixture.pnts;
            EEG.times    = fixture.times;
            EEG.xmin     = fixture.times(1) / 1000;
            EEG.xmax     = fixture.times(end) / 1000;
            EEG.chanlocs = TransTools.TemplateScalpLocs(fixture.chanlocs, ...
                TransTools.Dipfit1005File('ManualRejectTest'));
            EEG = eeg_checkset(EEG);

            flags = false(EEG.nbchan, EEG.trials);
            flags(1, 2) = true;   % Fz, trial 2 only
            opts = struct('flags', flags, 'scope', 'This channel only', 'channelMode', 'Interpolate');

            [result, ~] = ManualReject(EEG, opts);

            testCase.verifyFalse(isequaln(result.data(1, :, 2), EEG.data(1, :, 2)));
            testCase.verifyFalse(any(isnan(result.data(1, :, 2))));
            testCase.verifyEqual(result.data(1, :, [1 3 4]), EEG.data(1, :, [1 3 4]));
        end
    end
end
