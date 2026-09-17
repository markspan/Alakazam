classdef AlakazamBinsToEventListTest < matlab.unittest.TestCase
%ALAKAZAMBINSTOEVENTLISTTEST  Unit tests for src/IO/alakazamBinsToEventList.m.
%
%   THE SHAPE PINNED HERE IS FROM RUNNING REAL ERPLAB, NOT GUESSED -- see
%   the function's own header comment: a synthetic recording was put
%   through ERPLAB 13.10's own pop_creabasiceventlist + pop_binlister +
%   pop_epochbin, and the field names/values/sentinels checked below
%   (bini=-1 and binlabel='""' for an unbinned event, "B<n>(<code>)" for a
%   binned one, EEG.event(i).type getting REPLACED by that bin label) are
%   copied from its actual output.
%
%   Run with: runtests('tests/AlakazamBinsToEventListTest.m').
%
%   See also ALAKAZAMBINSTOEVENTLIST, ONEXPORTSET, DEFINEBINS.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'IO'), fullfile(root, 'src', 'Transformations')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function itIsANoOpWithoutBindesc(testCase)
            EEG = struct('event', struct('type', {'112'}, 'latency', {1}));
            result = alakazamBinsToEventList(EEG);
            testCase.verifyFalse(isfield(result, 'EVENTLIST'));
        end

        function aBinnedEventGetsErplabsOwnFieldsAndSentinelFormat(testCase)
        %ABINNEDEVENTGETSERPLABSOWNFIELDSANDSENTINELFORMAT  A single event
        %   in bin 1 must end up with EEG.event(1).bini == 1, .binlabel ==
        %   "B1(112)" (confirmed directly against real ERPLAB output), and
        %   .type REPLACED by that same label -- ERPLAB's own pop_binlister
        %   does exactly this and prints a warning saying so.
            EEG = fixtureContinuous();
            EEG = alakazamBinsToEventList(EEG);

            testCase.verifyEqual(EEG.event(1).bini, 1);
            testCase.verifyEqual(EEG.event(1).binlabel, 'B1(112)');
            testCase.verifyEqual(EEG.event(1).type, 'B1(112)');
            testCase.verifyEqual(EEG.event(1).item, 1);
            testCase.verifyEqual(EEG.EVENTLIST.eventinfo(1).bini, 1);
            testCase.verifyEqual(EEG.EVENTLIST.eventinfo(1).code, '112');
        end

        function anUnbinnedEventGetsErplabsOwnSentinels(testCase)
        %ANUNBINNEDEVENTGETSERPLABSOWNSENTINELS  An event matching no bin's
        %   predicate (EEG.event(i).bini == []) must read bini == -1 and
        %   binlabel == '""' -- ERPLAB's own "not in any bin" convention,
        %   confirmed directly (a fresh pop_creabasiceventlist marks every
        %   event this way before pop_binlister runs).
            EEG = fixtureContinuous();
            EEG.event(2).bini = []; % event 2 (code 118) matches no bin
            EEG = alakazamBinsToEventList(EEG);

            testCase.verifyEqual(EEG.event(2).bini, -1);
            testCase.verifyEqual(EEG.event(2).binlabel, '""');
            testCase.verifyEqual(EEG.event(2).type, '""');
        end

        function eventlistTopLevelFieldsMatchTheBindesc(testCase)
            EEG = fixtureContinuous();
            EEG = alakazamBinsToEventList(EEG);

            testCase.verifyEqual(EEG.EVENTLIST.nbin, 2);
            testCase.verifyEqual(EEG.EVENTLIST.trialsperbin, [1, 0], ...
                'bin 2 ("Unrelated") matches no event in this fixture (see fixtureContinuous).');
            testCase.verifyEqual(EEG.EVENTLIST.bdf(1).description, 'Related');
            testCase.verifyEqual(EEG.EVENTLIST.bdf(2).description, 'Unrelated');
            testCase.verifyEqual(EEG.EVENTLIST.bdf(1).namebin, 'BIN 1');
        end

        function aCombinationBinIsExcludedFromBdf(testCase)
        %ACOMBINATIONBININEXCLUDEDFROMBDF  A DefineBins difference bin (bin
        %   N = bin A - bin B) has no matched events of its own and no
        %   ERPLAB equivalent -- must not appear in EVENTLIST.bdf, and
        %   EVENTLIST.nbin must count only the real (plain) bins.
            EEG = fixtureContinuous();
            EEG.bindesc(3) = struct('index', 3, 'label', 'Effect', 'script', '', ...
                'plan', [], 'combo', struct('bin', [1 2], 'coeff', [1 -1]), ...
                'events', [], 'rt', [], 'n', 0);
            EEG = alakazamBinsToEventList(EEG);

            testCase.verifyEqual(EEG.EVENTLIST.nbin, 2, 'the combo bin must not be counted');
            testCase.verifyEqual(numel(EEG.EVENTLIST.bdf), 2);
            testCase.verifyTrue(all(~strcmpi({EEG.EVENTLIST.bdf.description}, 'Effect')));
        end

        function epochedDataMirrorsTheAnchorsFieldsWithErplabsEventPrefix(testCase)
        %EPOCHEDDATAMIRRORSTHEANCHORSFIELDSWITHERPLABSEVENTPREFIX  Confirmed
        %   directly against real ERPLAB's pop_epochbin output: each trial's
        %   .epoch(k) gets its own anchor event's bin fields mirrored with
        %   an "event" prefix (eventbini, eventbinlabel, ...), the same
        %   shape pop_epochbin produces.
            EEG = fixtureEpoched();
            EEG = alakazamBinsToEventList(EEG);

            testCase.verifyEqual(EEG.epoch(1).eventbini, EEG.event(1).bini);
            testCase.verifyEqual(EEG.epoch(1).eventbinlabel, EEG.event(1).binlabel);
            testCase.verifyEqual(EEG.epoch(1).eventtype, EEG.event(1).type);
            testCase.verifyEqual(EEG.epoch(1).eventbepoch, 1);
        end
    end
end

function EEG = fixtureContinuous()
%FIXTURECONTINUOUS  2 events (codes 112/118), bin 1 matches event 1 only.
    EEG = struct();
    EEG.event = struct('type', {'112', '118'}, 'latency', {100, 200}, 'bini', {1, []});
    EEG.srate = 250;
    EEG.bindesc = struct( ...
        'index', {1, 2}, 'label', {'Related', 'Unrelated'}, 'script', {'bin 1 "Related" : 112', 'bin 2 "Unrelated" : 122'}, ...
        'plan', {[], []}, 'combo', {[], []}, 'events', {1, []}, 'rt', {NaN, []}, 'n', {1, 0});
end

function EEG = fixtureEpoched()
%FIXTUREEPOCHED  One trial, its own anchor at EEG.event(1), matching
%   Alakazam's own cutEpochs shape (event/eventtype/eventlatency/bini).
    EEG = fixtureContinuous();
    EEG.trials = 1;
    EEG.epoch = struct('event', 1, 'eventtype', '112', 'eventlatency', 0, 'bini', 1);
end
