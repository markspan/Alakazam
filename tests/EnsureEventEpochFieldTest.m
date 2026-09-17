classdef EnsureEventEpochFieldTest < matlab.unittest.TestCase
%ENSUREEVENTEPOCHFIELDTEST  Unit tests for src/IO/ensureEventEpochField.m.
%
%   Run with: runtests('tests/EnsureEventEpochFieldTest.m').
%
%   See also ENSUREEVENTEPOCHFIELD, ONEXPORTSET, REWRITEEPOCHEDEVENTLATENCIES.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'IO'), fullfile(root, 'src', 'Transformations')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end

        function ensureEeglab(testCase)
            testCase.assumeTrue(~isempty(which('eeglab')), ...
                'EEGLAB not found on the MATLAB path -- skipping EnsureEventEpochFieldTest.');
            if isempty(which('eeg_checkset'))
                eeglab('nogui');
            end
            testCase.assumeFalse(isempty(which('eeg_checkset')), ...
                'EEGLAB''s eeg_checkset is not available -- skipping EnsureEventEpochFieldTest.');
        end
    end

    methods (Test)
        function itIsANoOpOnContinuousData(testCase)
            EEG = struct('trials', 1, 'epoch', struct([]));
            result = ensureEventEpochField(EEG);
            testCase.verifyEqual(result, EEG);
        end

        function anchorEventsGetTheirOwnEpochNumberAndSurviveEventconsistency(testCase)
        %ANCHOREVENTSGETTHEIROWNEPOCHNUMBERANDSURVIVEEVENTCONSISTENCY  Every
        %   trial's own anchor must end up with EEG.event(ei).epoch == that
        %   trial's number, and must still be present afterwards -- proven
        %   with a real eeg_checkset call (which requires exactly this
        %   field to accept epoched data, and which is what would prune a
        %   wrongly-tagged anchor away).
            EEG = fixture();
            EEG = rewriteEpochedEventLatencies(EEG); % anchors need EEGLAB-correct latencies first (see that function's own test)
            result = ensureEventEpochField(EEG);

            testCase.verifyEqual(numel(result.epoch), numel(EEG.epoch), ...
                'no trial anchor should have been pruned.');
            for k = 1:numel(result.epoch)
                ei = result.epoch(k).event;
                testCase.verifyEqual(result.event(ei).epoch, k);
            end
        end

        function anEventMatchingNoBinIsPrunedByEventconsistency(testCase)
        %ANEVENTMATCHINGNOBINISPRUNEDBYEVENTCONSISTENCY  An event that
        %   matched no bin's predicate belongs to no trial in Alakazam's
        %   own one-anchor-per-trial model, never gets a valid .epoch, and
        %   is pruned by eeg_checkset's own 'eventconsistency' cleanup --
        %   the documented, intended behaviour (see this function's own
        %   header comment), not a bug.
            EEG = fixture();
            nEventsBefore = numel(EEG.event);
            EEG = rewriteEpochedEventLatencies(EEG);
            result = ensureEventEpochField(EEG);

            testCase.verifyLessThan(numel(result.event), nEventsBefore, ...
                'the unmatched event should have been pruned.');
            testCase.verifyTrue(all(strcmp({result.event.type}, '112')), ...
                'only the two bin-matched anchor events ("112") should remain.');
        end
    end
end

function EEG = fixture()
%FIXTURE  A real, EEGLAB-checkset-clean 2-trial epoched dataset (via the
%   real DefineBins.m): 2 events code "112" (both matched, one bin each
%   becomes a trial anchor) plus 1 event code "999" that matches no bin,
%   so it belongs to no trial -- the exact "non-anchor, gets pruned" case.
    srate = 250;
    EEG = eeg_emptyset();
    EEG.data = randn(2, srate * 8);
    EEG.srate = srate; EEG.nbchan = 2;
    EEG.chanlocs = struct('labels', {'Fz', 'Cz'});
    EEG.times = (0:size(EEG.data, 2) - 1) / srate;
    EEG.event = struct('type', {'112', '999', '112'}, ...
        'latency', {double(1 * srate), double(3 * srate), double(6 * srate)});

    opts = struct('script', 'bin 1 "Related" : 112', ...
        'epoch', struct('lo', -200, 'hi', 800, 'unit', 'ms'));
    EEG = DefineBins(EEG, opts);
end
