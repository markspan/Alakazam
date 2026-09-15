classdef DeriveBinsFromEpochsTest < matlab.unittest.TestCase
%DERIVEBINSFROMEPOCHSTEST  Unit tests for src/Support/deriveBinsFromEpochs.m.
%
%   THE FIXTURE'S SHAPE IS NOT ARBITRARY. Confirmed directly against a real
%   RIFT recording (Data/RIFT/ThriftyRIFT_1_preproc.set, an epoched .set
%   from an EEGLAB pipeline outside Alakazam -- not tracked in git, gitignored
%   under Data/, so this file cannot depend on it): pop_epoch stores
%   .eventtype/.eventlatency as a CELL row once an epoch's wide window
%   catches more than one event, but keeps .event itself a PLAIN NUMERIC
%   ROW regardless -- an inconsistency between pop_epoch's own fields that
%   is easy to miss without checking real data (a first version of this
%   function did, and every multi-event trial silently landed unbinned
%   until the mismatch was caught against the real file). Trial 1's fixture
%   below reproduces exactly that shape.
%
%   Run with: runtests('tests/DeriveBinsFromEpochsTest.m').
%
%   See also DERIVEBINSFROMEPOCHS, LOADSETFILE, DEFINEBINS.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Support')));
        end
    end

    methods (Test)
        function anchorsAreGroupedByTypeIntoBins(testCase)
            EEG = popEpochFixture();
            EEG = deriveBinsFromEpochs(EEG);

            testCase.assertTrue(isfield(EEG, 'bindesc'));
            testCase.assertEqual(numel(EEG.bindesc), 2);
            labels = string({EEG.bindesc.label});
            testCase.verifyEqual(sort(labels), ["A", "B"]);

            binA = EEG.bindesc(labels == "A");
            binB = EEG.bindesc(labels == "B");
            testCase.verifyEqual(binA.n, 2);
            testCase.verifyEqual(sort(binA.trials), [1, 2]);
            testCase.verifyEqual(binB.n, 1);
            testCase.verifyEqual(binB.trials, 3);
        end

        function theMultiEventEpochsNumericEventFieldIsHandled(testCase)
        %THEMULTIEVENTEPOCHSNUMERICEVENTFIELDISHANDLED  Trial 1's own
        %   .event is the plain numeric row [1 2], not a cell -- this is
        %   the exact shape that broke the first version of the function
        %   (see this class' own header comment). Its anchor (latency 0)
        %   is event 1, type "A".
            EEG = popEpochFixture();
            EEG = deriveBinsFromEpochs(EEG);
            testCase.verifyEqual(EEG.epoch(1).event, 1);
            testCase.verifyEqual(EEG.epoch(1).eventtype, 'A');
            testCase.verifyEqual(EEG.epoch(1).eventlatency, 0);
            testCase.verifyEqual(EEG.epoch(1).bini, 1); % bin A
        end

        function aTrialWithNoZeroLatencyEventIsKeptUnbinnedNotDropped(testCase)
        %ATRIALWITHNOZEROLATENCYEVENTISKEPTUNBINNEDNOTDROPPED  Trial 4 has
        %   no event at latency 0 (a malformed/off-centre epoch). It must
        %   still exist afterwards -- data is not silently discarded --
        %   just with no bin, the same way DefineBins leaves an event that
        %   matched no bin's predicate.
            EEG = popEpochFixture();
            EEG = deriveBinsFromEpochs(EEG);
            testCase.verifyEqual(numel(EEG.epoch), 4, 'trial 4 must not be dropped');
            testCase.verifyEmpty(EEG.epoch(4).bini);
            totalBinned = sum([EEG.bindesc.n]);
            testCase.verifyEqual(totalBinned, 3, 'only the 3 trials with a real anchor should be binned');
        end

        function everyEpochGetsAlakazamsLeanFourFieldShape(testCase)
        %EVERYEPOCHGETSALAKAZAMSLEANFOURFIELDSHAPE  EEG.epoch is REPLACED
        %   with DefineBins/cutEpochs' own convention (event/eventtype/
        %   eventlatency/bini only), not pop_epoch's richer per-epoch
        %   fields left in place alongside a new .bini.
            EEG = popEpochFixture();
            EEG.epoch(1).eventduration = {0, 0}; % a pop_epoch field this function does not use
            EEG = deriveBinsFromEpochs(EEG);
            testCase.verifyEqual(sort(fieldnames(EEG.epoch)), sort({'event'; 'eventtype'; 'eventlatency'; 'bini'}));
        end

        function itIsANoOpWhenBindescAlreadyExists(testCase)
        %ITISANOOPWHENBINDESCALREADYEXISTS  Re-deriving over an existing
        %   result (an Alakazam-produced epoched set, or one already
        %   adapted once) would discard any editing done since.
            EEG = popEpochFixture();
            EEG.bindesc = struct('index', 1, 'label', 'Kept', 'script', '', ...
                'plan', [], 'combo', [], 'events', 1, 'rt', NaN, 'n', 1, 'trials', 1);
            result = deriveBinsFromEpochs(EEG);
            testCase.verifyEqual(result.bindesc.label, 'Kept');
        end

        function itIsANoOpForSingleTrialData(testCase)
        %ITISANOOPFORSINGLETRIALDATA  Nothing meaningful to group with
        %   only one trial (averaged/single-trial data).
            EEG = popEpochFixture();
            EEG.trials = 1;
            EEG.epoch = EEG.epoch(1);
            result = deriveBinsFromEpochs(EEG);
            testCase.verifyFalse(isfield(result, 'bindesc'));
        end

        function itIsANoOpWithoutPerEpochEventMetadata(testCase)
        %ITISANOOPWITHOUTPEREPOCHEVENTMETADATA  A dataset with no
        %   .epoch(k).eventlatency/.event at all (e.g. one that reached
        %   loadSETFile some other way) has nothing to derive from.
            EEG = popEpochFixture();
            EEG.epoch = rmfield(EEG.epoch, {'eventlatency', 'event'});
            result = deriveBinsFromEpochs(EEG);
            testCase.verifyFalse(isfield(result, 'bindesc'));
        end
    end
end

function EEG = popEpochFixture()
%POPEPOCHFIXTURE  4 trials, pop_epoch-shaped .epoch metadata (see this
%   class' own header comment for why trial 1's shape matters):
%     trial 1: multi-event, .event a plain numeric row [1 2], anchor "A" (event 1)
%     trial 2: single-event (bare scalar fields), anchor "A" (event 3)
%     trial 3: single-event, anchor "B" (event 4)
%     trial 4: multi-event, no event at latency 0 -- no anchor
    EEG = struct();
    EEG.trials = 4;
    EEG.data = zeros(2, 10, 4);
    EEG.event = struct('type', {'A', 'X', 'A', 'B', 'Y', 'Z'}, ...
        'latency', {1, 10, 3, 4, 50, 60});

    EEG.epoch(1).event        = [1 2];
    EEG.epoch(1).eventtype    = {'A', 'X'};
    EEG.epoch(1).eventlatency = {0, 50};

    EEG.epoch(2).event        = 3;
    EEG.epoch(2).eventtype    = 'A';
    EEG.epoch(2).eventlatency = 0;

    EEG.epoch(3).event        = 4;
    EEG.epoch(3).eventtype    = 'B';
    EEG.epoch(3).eventlatency = 0;

    EEG.epoch(4).event        = [5 6];
    EEG.epoch(4).eventtype    = {'Y', 'Z'};
    EEG.epoch(4).eventlatency = {-10, 20};
end
