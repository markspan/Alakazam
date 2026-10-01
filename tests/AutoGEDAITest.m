classdef AutoGEDAITest < matlab.unittest.TestCase
%AUTOGEDAITEST  What AutoGEDAI hands GEDAI, and what it leaves behind.
%
%   GEDAI is replaced by a stand-in (tests/fixtures/GEDAIStandIn) that
%   records its arguments and returns the data unchanged, so these cases
%   need neither the plugin nor its computation. They need EEGLAB, for
%   pop_select and the electrode template, and skip without it.
%
%   Two things are pinned. The dialog's epoch size and sliding window reach
%   GEDAI, and settings stored before they were offered still run with
%   GEDAI's defaults for them. And GEDAI v1.7 switches every MATLAB warning
%   off and leaves them so, which silenced every warning for the rest of
%   the session; the stand-in does the same, and AutoGEDAI has to put the
%   state back.
%
%   Run with: runtests('tests/AutoGEDAITest.m').
%
%   See also AUTOGEDAI.

    properties (Access = private)
        % The temporary folder the stand-in runs from, first on the path.
        StandIn char
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Transformations', 'AutoGEDAI'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end

        function requireEEGLab(testCase)
            try
                EEGLabEnvironment.ensure();
            catch
            end
            testCase.assumeTrue(exist('pop_select', 'file') == 2 && exist('readlocs', 'file') == 2, ...
                'EEGLAB is not on the path.');
        end
    end

    methods (TestMethodSetup)
        function putTheStandInFirst(testCase)
            testCase.addTeardown(@warning, warning());
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture()).Folder;
            root = fileparts(fileparts(mfilename('fullpath')));
            copyfile(fullfile(root, 'tests', 'fixtures', 'GEDAIStandIn', 'GEDAI.m'), folder);
            mkdir(fullfile(folder, 'auxiliaries'));
            copyfile(TransTools.Template1005File('Alakazam:AutoGEDAITest'), ...
                fullfile(folder, 'auxiliaries', 'standard_1005.elc'));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(folder));
            testCase.StandIn = folder;
        end
    end

    methods (Test)
        function theWindowSettingsReachGEDAI(testCase)
            opts = options(struct('EpochCycles', 8, 'SlidingWindow', 60));

            AutoGEDAI(recording(), opts);

            call = testCase.lastCall();
            testCase.verifyEqual(call.epoch_size_in_cycles, 8);
            testCase.verifyEqual(call.smoothing_window_seconds, 60);
        end

        function settingsStoredBeforeTheWindowsRunWithGEDAIsDefaults(testCase)
        %SETTINGSSTOREDBEFORETHEWINDOWSRUNWITHGEDAISDEFAULTS  A step saved
        %   before the epoch size and sliding window were offered, such as
        %   the library's N400 template, ran with 12 cycles and Inf. It must
        %   replay with them, and say so in what it stores.
            [EEG, used] = AutoGEDAI(recording(), options(struct()));

            call = testCase.lastCall();
            testCase.verifyEqual(call.epoch_size_in_cycles, 12);
            testCase.verifyEqual(call.smoothing_window_seconds, Inf);
            testCase.verifyEqual([used.EpochCycles, used.SlidingWindow], [12, Inf]);
            testCase.verifyEqual([EEG.etc.GEDAI.options.EpochCycles, ...
                EEG.etc.GEDAI.options.SlidingWindow], [12, Inf]);
        end

        function theOtherSettingsStillReachGEDAI(testCase)
            AutoGEDAI(recording(), options(struct('Strength', 'auto-', 'LowCut', 1)));

            call = testCase.lastCall();
            testCase.verifyEqual(call.artifact_threshold_type, 'auto-');
            testCase.verifyEqual(call.lowcut_frequency, 1);
            testCase.verifyEqual(call.ref_matrix_type, 'precomputed');
            testCase.verifyEqual(call.signal_type, 'eeg');
        end

        function GEDAILeavesTheWarningStateAsItFoundIt(testCase)
        %GEDAILEAVESTHEWARNINGSTATEASITFOUNDIT  GEDAI v1.7 switches every
        %   warning off and never on again. After AutoGEDAI the state is
        %   what it was before.
            warning('on', 'all');
            before = warning();

            AutoGEDAI(recording(), options(struct()));

            testCase.verifyEmpty(WarningStateGuardPlugin.stateChanges(before, warning()));
        end

        function aChannelGEDAICannotUseComesBackUntouched(testCase)
            EEG = recording();
            veog = strcmp({EEG.chanlocs.labels}, 'VEOG');

            out = AutoGEDAI(EEG, options(struct()));

            testCase.verifyEqual(out.data(veog, :), EEG.data(veog, :));
            testCase.verifyEqual(out.etc.GEDAI.excludedChannels, {'VEOG'});
        end
    end

    methods (Access = private)
        function call = lastCall(testCase)
        %LASTCALL  The arguments the stand-in was last called with.
            saved = load(fullfile(testCase.StandIn, 'lastCall.mat'), 'call');
            call = saved.call;
        end
    end
end

% ======================================================================= %
function EEG = recording()
%RECORDING  Ten seconds on the 10-20 channels and a VEOG, which is not in
%   GEDAI's electrode set and so is left out of it.
    EEG = makeScalpEEG('DataFormat', 'CONTINUOUS', 'seconds', 10, 'extra', {'VEOG'});
    EEG.File = fullfile(tempdir, 'sub01.vhdr');
end

function opts = options(changes)
%OPTIONS  AutoGEDAI's settings as the dialog stores them, without the
%   epoch size and sliding window, with CHANGES applied.
    opts = struct('Strength', 'auto', 'Leadfield', 'precomputed', 'LowCut', 0.5, ...
        'RejectEpochs', 'no', 'EpochENOVA', 0.9, 'RejectChannels', 'no', ...
        'ChannelENOVA', 0.9, 'Parallel', 'no');
    for name = fieldnames(changes)'
        opts.(name{1}) = changes.(name{1});
    end
end
