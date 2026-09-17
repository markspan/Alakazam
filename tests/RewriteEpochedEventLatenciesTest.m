classdef RewriteEpochedEventLatenciesTest < matlab.unittest.TestCase
%REWRITEEPOCHEDEVENTLATENCIESTEST  Unit tests for
%   src/IO/rewriteEpochedEventLatencies.m.
%
%   THE BUG THIS PINS. DefineBins/cutEpochs leaves every event's own
%   .latency at its ORIGINAL continuous-recording sample number, but
%   EEGLAB expects an epoched dataset's event latencies on one
%   CONCATENATED timeline (epoch k's own samples occupying
%   [(k-1)*pnts, k*pnts)) -- left unrewritten, eeg_checkset sees a trial
%   anchor's latency as wildly out of bounds and PRUNES it outright.
%   Confirmed directly: exporting a real 2-bin, 40-trial DefineBins
%   dataset lost 12 of its 40 trial-anchor events this way. A first fix
%   attempt used a 0-based within-epoch sample offset and was ALSO wrong
%   in a way a shape-only test would have missed entirely: every trial's
%   own EEG.epoch(k).eventlatency came back -4 ms (at 250 Hz, exactly
%   -1 sample) instead of 0 after a REAL pop_saveset/eeg_checkset round
%   trip -- EEGLAB's own .event.latency convention is 1-based, not
%   0-based. theRewriteSurvivesARealEegCheckestRoundTrip below is the
%   test that would have caught it: it does not just check the computed
%   latency value in isolation, it runs the real eeg_checkset and
%   confirms nothing gets pruned and eventlatency comes back exactly 0.
%
%   Run with: runtests('tests/RewriteEpochedEventLatenciesTest.m').
%
%   See also REWRITEEPOCHEDEVENTLATENCIES, ONEXPORTSET, ENSUREEVENTEPOCHFIELD.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'IO'), fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end

        function ensureEeglab(testCase)
        %ENSUREEEGLAB  Skip (not fail) the round-trip test if EEGLAB is not
        %   on the path/initialised -- same pattern as FilterTest.m.
            testCase.assumeTrue(~isempty(which('eeglab')), ...
                'EEGLAB not found on the MATLAB path -- skipping the round-trip test.');
            if isempty(which('eeg_checkset'))
                eeglab('nogui');
            end
            testCase.assumeFalse(isempty(which('eeg_checkset')), ...
                'EEGLAB''s eeg_checkset is not available -- skipping the round-trip test.');
        end
    end

    methods (Test)
        function itIsANoOpOnContinuousData(testCase)
            EEG = struct('trials', 1, 'epoch', struct([]));
            result = rewriteEpochedEventLatencies(EEG);
            testCase.verifyEqual(result, EEG);
        end

        function anchorLatenciesAreRewrittenToTheConcatenatedTimeline(testCase)
        %ANCHORLATENCIESAREREWRITTENTOTHECONCATENATEDTIMELINE  Direct check
        %   of the formula itself: trial k's anchor latency must land at
        %   (k-1)*pnts + zeroSample (1-based), not the anchor's own stale,
        %   large original-continuous-recording sample number.
            pnts = 250; zeroSampleExpected = 51; % -200 ms at 250 Hz: sample 51 is t=0 (1-based)
            EEG = struct();
            EEG.trials = 3;
            EEG.pnts = pnts;
            EEG.times = ((-50 + (0:pnts - 1)) / 250) * 1000; % ms, matches cutEpochs' own formula
            EEG.event = struct('type', {'112', '112', '112'}, ...
                'latency', {9999, 20000, 31000}); % stale, large, original-recording values
            EEG.epoch = struct('event', {1, 2, 3});

            result = rewriteEpochedEventLatencies(EEG);

            for k = 1:3
                testCase.verifyEqual(result.event(k).latency, (k - 1) * pnts + zeroSampleExpected);
            end
        end

        function nonAnchorEventsAreLeftAlone(testCase)
            EEG = struct();
            EEG.trials = 2; EEG.pnts = 250;
            EEG.times = ((-50 + (0:249)) / 250) * 1000;
            EEG.event = struct('type', {'112', 'boundary', '112'}, 'latency', {9999, 15000, 20000});
            EEG.epoch = struct('event', {1, 3}); % event 2 (boundary) is not any trial's anchor

            result = rewriteEpochedEventLatencies(EEG);

            testCase.verifyEqual(result.event(2).latency, 15000, ...
                'a non-anchor event''s latency must not be touched.');
        end

        function theRewriteSurvivesARealEegCheckestRoundTrip(testCase)
        %THEREWRITESURVIVESAREALEEGCHECKESTROUNDTRIP  The test that would
        %   have caught the 1-based/0-based bug (see this class' own
        %   header comment): build a real DefineBins-epoched dataset, run
        %   the rewrite, then run the REAL eeg_checkset('eventconsistency')
        %   -- the same call onExportSet.m's own ensureEventEpochField
        %   makes -- and confirm no anchor event is pruned and every
        %   trial's own EEG.epoch(k).eventlatency comes back exactly 0.
            EEG = realEpochedFixture();
            nTrialsBefore = EEG.trials;

            EEG = rewriteEpochedEventLatencies(EEG);
            for k = 1:numel(EEG.epoch)
                ei = EEG.epoch(k).event;
                if ~isempty(ei); EEG.event(ei).epoch = k; end
            end
            EEG = eeg_checkset(EEG, 'eventconsistency');

            testCase.verifyEqual(numel(EEG.epoch), nTrialsBefore, ...
                'no trial anchor should have been pruned by eeg_checkset.');
            for k = 1:numel(EEG.epoch)
                testCase.verifyEqual(EEG.epoch(k).eventlatency, 0, sprintf( ...
                    'trial %d''s own anchor should be at exactly latency 0 within its epoch.', k));
            end
        end
    end
end

function EEG = realEpochedFixture()
%REALEPOCHEDFIXTURE  A real, EEGLAB-checkset-clean continuous recording
%   put through the real DefineBins.m -- 6 trials, one bin, non-
%   overlapping epoch windows (a real ERP paradigm's inter-trial interval
%   is longer than its own analysis epoch, not shorter).
    srate = 250;
    EEG = eeg_emptyset();
    EEG.data = randn(2, srate * 12);
    EEG.srate = srate; EEG.nbchan = 2;
    EEG.chanlocs = struct('labels', {'Fz', 'Cz'});
    EEG.times = (0:size(EEG.data, 2) - 1) / srate;
    lat = round((1:1.8:11) * srate); % 6 events, 1.8 s apart, well outside a 1 s epoch
    EEG.event = struct('type', repmat({'112'}, 1, numel(lat)), 'latency', num2cell(double(lat)));

    opts = struct('script', 'bin 1 "Related" : 112', ...
        'epoch', struct('lo', -200, 'hi', 800, 'unit', 'ms'));
    EEG = DefineBins(EEG, opts);
end
