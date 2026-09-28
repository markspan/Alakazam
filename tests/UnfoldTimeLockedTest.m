classdef UnfoldTimeLockedTest < matlab.unittest.TestCase
%UNFOLDTIMELOCKEDTEST  Events in no bin that keep a near-constant lag to
%   another modelled event type: Unfold.timeLockedEvents (manual issue M10).
%
%   Deconvolution tells two responses apart by seeing them at different
%   offsets from one another, so a code that almost always comes the same
%   distance from a bin (a fixation 12 ms after its saccade) makes the design
%   nearly collinear: the solver may not converge, and the two are not told
%   apart. The Deconvolve dialog warns about such a pair, and the fit notes
%   it. These cases pin what counts as one: a lock that holds for most events
%   of BOTH types, with a lag short enough for the responses to overlap and a
%   jitter well under the response's own time scale.
%
%   UnfoldBinsTest's recording is the fixture, and it happens to hold such a
%   pair already: its 'response' events come exactly 600 ms after every
%   Frequent one. Needs no toolbox.
%
%   Run with: runtests('tests/UnfoldTimeLockedTest.m').
%
%   See also UNFOLD.TIMELOCKEDEVENTS, UNFOLD.BINMODEL, UNFOLDBINSTEST.

    properties (Constant)
        WindowMs = [-200 800]
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Support'), fullfile(root, 'tests')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function aCodeAtAFixedLagToABinIsNamed(testCase)
            EEG = UnfoldBinsTest.recording();

            pairs = lockedIn(EEG, 'all', testCase.WindowMs);

            testCase.assertNumElements(pairs, 1);
            testCase.verifyEqual(pairs.code, 'response');
            testCase.verifyEqual(pairs.other, 'Frequent');
            testCase.verifyEqual(pairs.lagMs, 600, 'AbsTol', 1e-9);
            testCase.verifyEqual(pairs.sdMs, 0, 'AbsTol', 1e-9);
            testCase.verifySubstring(pairs.note, 'follows "Frequent" by 600 ms');
            testCase.verifySubstring(pairs.note, 'Consider not modelling "response"');
        end

        function aCodeThatPrecedesABinIsSaidToPrecedeIt(testCase)
        %ACODETHATPRECEDESABINISSAIDTOPRECEDEIT  A trial marker 100 ms before
        %   every Frequent stimulus: the lag is negative, and says so.
            EEG = withCode(UnfoldBinsTest.recording(), 'marker', frequentLatencies() - 10);

            pairs = lockedIn(EEG, {'marker'}, testCase.WindowMs);

            testCase.assertNumElements(pairs, 1);
            testCase.verifyEqual(pairs.lagMs, -100, 'AbsTol', 1e-9);
            testCase.verifySubstring(pairs.note, 'precedes "Frequent" by 100 ms');
        end

        function aJitteredLagIsNotALock(testCase)
        %AJITTEREDLAGISNOTALOCK  Responses 400 to 800 ms after each stimulus,
        %   as reaction times vary: exactly what lets the fit separate them.
            EEG = UnfoldBinsTest.recording();
            rng(2);
            responses = frequentLatencies() + 40 + randi(40, 1, 90);
            EEG = withCode(withoutCode(EEG, 'response'), 'response', responses);

            testCase.verifyEmpty(lockedIn(EEG, 'all', testCase.WindowMs));
        end

        function aLagOfAFewSamplesStillIsALock(testCase)
        %ALAGOFAFEWSAMPLESSTILLISALOCK  The reported case: a fixation 10 to
        %   20 ms after its saccade, the lag varying by a sample.
            EEG = UnfoldBinsTest.recording();
            rng(3);
            fixations = frequentLatencies() + 1 + randi([0 1], 1, 90);
            EEG = withCode(withoutCode(EEG, 'response'), 'fixation', fixations);

            pairs = lockedIn(EEG, 'all', testCase.WindowMs);

            testCase.assertNumElements(pairs, 1);
            testCase.verifyEqual(pairs.code, 'fixation');
            testCase.verifyLessThan(pairs.sdMs, 10);
        end

        function responsesThatNeverOverlapAreNotALock(testCase)
        %RESPONSESTHATNEVEROVERLAPARENOTALOCK  With a 600 ms window, the
        %   window of a 'response' 600 ms later begins where Frequent's ends,
        %   so the two responses never share the data and cannot be confused.
            EEG = UnfoldBinsTest.recording();

            testCase.verifyEmpty(lockedIn(EEG, 'all', [-200 400]));
        end

        function aCodeAfterOnlySomeOfABinsEventsIsNotALock(testCase)
        %ACODEAFTERONLYSOMEOFABINSEVENTSISNOTALOCK  A code after every third
        %   Frequent stimulus only: the other two thirds are the leverage the
        %   fit needs, so the pair is fine.
            EEG = UnfoldBinsTest.recording();
            frequent = frequentLatencies();
            EEG = withCode(EEG, 'button', frequent(1:3:end) + 5);

            testCase.verifyEmpty(lockedIn(EEG, {'button'}, testCase.WindowMs));
        end

        function aCodeNotModelledIsNotChecked(testCase)
            EEG = UnfoldBinsTest.recording();

            testCase.verifyEmpty(lockedIn(EEG, {}, testCase.WindowMs), ...
                'A code left out of the model cannot make it collinear.');
        end

        function twoLockedCodesAreNamedOnce(testCase)
        %TWOLOCKEDCODESARENAMEDONCE  A marker 100 ms before every Frequent
        %   stimulus is locked to the response 700 ms later too; that pair of
        %   codes is one warning, not one for each of them.
            EEG = withCode(UnfoldBinsTest.recording(), 'marker', frequentLatencies() - 10);

            pairs = lockedIn(EEG, 'all', testCase.WindowMs);

            betweenCodes = arrayfun(@(p) all(ismember({p.code, p.other}, {'marker', 'response'})), pairs);
            testCase.verifyEqual(nnz(betweenCodes), 1);
            testCase.verifySubstring(pairs(find(betweenCodes, 1)).note, ...
                'Consider modelling only one of the two.');
            testCase.verifyNumElements(pairs, 3, ...
                'Each code with Frequent, and the two codes with each other.');
        end
    end
end

% ======================================================================= %
function pairs = lockedIn(EEG, otherEvents, windowMs)
%LOCKEDIN  The time-locked pairs of EEG's model with OTHEREVENTS modelled.
    plan = Unfold.binModel(EEG, 'OtherEvents', otherEvents);
    pairs = Unfold.timeLockedEvents(plan, EEG.srate, windowMs);
end

function latencies = frequentLatencies()
    latencies = UnfoldBinsTest.frequentLatencies();
end

function EEG = withCode(EEG, code, latencies)
%WITHCODE  EEG with an event CODE, in no bin, at every one of LATENCIES.
    for latency = latencies
        EEG.event(end + 1) = struct('type', code, 'latency', latency, 'bini', []);
    end
    [~, order] = sort([EEG.event.latency]);
    EEG.event = EEG.event(order);
end

function EEG = withoutCode(EEG, code)
%WITHOUTCODE  EEG with every event of CODE removed.
    EEG.event = EEG.event(~strcmp({EEG.event.type}, code));
end
