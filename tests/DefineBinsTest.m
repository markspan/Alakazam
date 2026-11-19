classdef DefineBinsTest < matlab.unittest.TestCase
%DEFINEBINSTEST  Unit tests for
%   src/Transformations/DefineBins/DefineBins.m.
%
%   Uses "script mode" throughout -- DefineBins(EEG, struct('script', txt))
%   -- which parses TXT directly with no dialog, exactly the path the
%   function's own comment calls out as "for scripting and tests".
%
%   Latencies below are in SAMPLES (EEGLAB's own convention for
%   EEG.event(i).latency), at a fixed 250 Hz test sampling rate (4 ms per
%   sample), chosen so every relation-window boundary in these tests
%   lands well clear of an edge case rather than exactly on one.
%
%   THE EPOCH comes from an epoch statement in the script (epoch [-200,800]
%   ms) or from options.epoch, and the statement wins; tagsOnly ignores
%   both. Text before the first statement is refused rather than dropped,
%   which is how an epoch line used to be ignored without a word.
%
%   Run with: runtests('tests/DefineBinsTest.m').
%
%   See also MAKETESTEEG.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations', 'DefineBins')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'tests', 'fixtures')));
        end
    end

    methods (Test)
        function matchesASimpleAnchorCode(testCase)
        %MATCHESASIMPLEANCHORCODE  bin 1 "Targets" 112 matches only the
        %   events whose type is 112, tagging each with .bini, the one
        %   record of which events a bin holds.
            EEG = eegWithEvents({'112', '122', '112'}, [100, 200, 300]);
            opts = struct('script', 'bin 1 "Targets" 112');

            [result, ~] = DefineBins(EEG, opts);

            testCase.verifyEqual(DefineBinsTest.membersOf(result, 1), [1, 3]);
            testCase.verifyEqual(result.bindesc(1).n, 2);
            testCase.verifyEqual(result.event(1).bini, 1);
            testCase.verifyEqual(result.event(2).bini, []);
            testCase.verifyEqual(result.event(3).bini, 1);
        end

        function wildcardMatchesExactCharacterCount(testCase)
        %WILDCARDMATCHESEXACTCHARACTERCOUNT  "s??" matches exactly a
        %   3-character "s"-prefixed marker (? = exactly one character
        %   each), not a shorter or longer one.
            EEG = eegWithEvents({'s11', 's1', 'sxx1'}, [100, 200, 300]);
            opts = struct('script', 'bin 1 "S" "s??"');

            [result, ~] = DefineBins(EEG, opts);

            testCase.verifyEqual(DefineBinsTest.membersOf(result, 1), 1);
        end

        function nextWithinWindowRequiresAQualifyingNeighbourInRange(testCase)
        %NEXTWITHINWINDOWREQUIRESAQUALIFYINGNEIGHBOURINRANGE  112 and
        %   next(118) within (200,1200] ms only matches the 112 whose
        %   nearest following 118 falls inside that window; a 112 whose
        %   nearest 118 comes back sooner (40 ms) is dropped, and .rt
        %   records the matched delay in ms.
            EEG = eegWithEvents({'112', '118', '112', '118'}, [100, 175, 1000, 1010]);
            opts = struct('script', 'bin 1 "Related" 112 and next(118) within (200,1200] ms');

            [result, ~] = DefineBins(EEG, opts);

            testCase.verifyEqual(DefineBinsTest.membersOf(result, 1), 1);
            testCase.verifyEqual(DefineBinsTest.rtsOf(result, 1), 300, 'AbsTol', 1e-9); % (175-100)/250*1000 ms
        end

        function adjacentRequiresTheImmediatelyFollowingEvent(testCase)
        %ADJACENTREQUIRESTHEIMMEDIATELYFOLLOWINGEVENT  112 and
        %   adjacent(118) matches only when the VERY NEXT event (in
        %   latency order) is 118, not just any later one.
            EEG = eegWithEvents({'112', '118', '112', '122', '118'}, [100, 150, 300, 350, 400]);
            opts = struct('script', 'bin 1 "X" 112 and adjacent(118)');

            [result, ~] = DefineBins(EEG, opts);

            testCase.verifyEqual(DefineBinsTest.membersOf(result, 1), 1); % the first 112 only
        end

        function combinationBinRecordsItsRecipeNotItsOwnEvents(testCase)
        %COMBINATIONBINRECORDSITSRECIPENOTITSOWNEVENTS  bin 3 = bin 1 -
        %   bin 2 has no event predicate of its own: DefineBins records
        %   the (coeff, bin) recipe on .combo and tags no event with it
        %   (Average computes the actual difference later).
            EEG = eegWithEvents({'112', '122'}, [100, 200]);
            opts = struct('script', [ ...
                'bin 1 "A" 112' newline ...
                'bin 2 "B" 122' newline ...
                'bin 3 "A-B" = bin 1 - bin 2']);

            [result, ~] = DefineBins(EEG, opts);

            testCase.verifyEmpty(DefineBinsTest.membersOf(result, 3));
            testCase.verifyEqual(result.bindesc(3).n, 0);
            testCase.verifyEqual([result.bindesc(3).combo.bin], [1, 2]);
            testCase.verifyEqual([result.bindesc(3).combo.coeff], [1, -1]);
        end

        function malformedScriptThrowsAFriendlyError(testCase)
        %MALFORMEDSCRIPTTHROWSAFRIENDLYERROR  A script with an unclosed
        %   relation should be rejected with the app's own error
        %   identifier (wrapParseError repackages the internal
        %   ParseAtCol... identifier into this one), not propagate a raw
        %   internal error.
            EEG = eegWithEvents({'112'}, 100);
            opts = struct('script', 'bin 1 "X" next(118'); % missing closing ')'
            testCase.verifyError(@() DefineBins(EEG, opts), 'Alakazam:DefineBins');
        end

        % --- Broken-script coverage below: one test per distinct parse-error
        % class DefineBinsEngine's parser can raise (see its throwParseError
        % call sites), each checked for both the shared wrapped identifier
        % and a distinguishing phrase from its own specific message -- so a
        % script that trips the wrong failure path still fails the test,
        % rather than only checking "some parse error happened".

        function emptyScriptIsRejectedWithAHelpfulMessage(testCase)
        %EMPTYSCRIPTISREJECTEDWITHAHELPFULMESSAGE  A script with no bin
        %   statements at all (blank, or only comments) is rejected before
        %   ever reaching the evaluator.
            EEG = eegWithEvents({'112'}, 100);
            opts = struct('script', '% just a comment, no bins here');
            testCase.verifyError(@() DefineBins(EEG, opts), 'Alakazam:DefineBins');
            try
                DefineBins(EEG, opts);
            catch err
                testCase.verifySubstring(err.message, 'bin <number> "<label>"');
            end
        end

        function binWithNoExpressionIsRejected(testCase)
        %BINWITHNOEXPRESSIONISREJECTED  A bin with a label but nothing
        %   after it has no predicate to match events against.
            EEG = eegWithEvents({'112'}, 100);
            opts = struct('script', 'bin 1 "Targets"');
            try
                DefineBins(EEG, opts);
                testCase.verifyFail('Expected DefineBins to throw.');
            catch err
                testCase.verifyEqual(err.identifier, 'Alakazam:DefineBins');
                testCase.verifySubstring(err.message, 'nothing after it');
            end
        end

        function duplicateAliasNameIsRejected(testCase)
        %DUPLICATEALIASNAMEISREJECTED  Two 'let' statements defining the
        %   same alias name are rejected, not silently letting the second
        %   shadow the first.
            EEG = eegWithEvents({'112'}, 100);
            opts = struct('script', [ ...
                'let x = 112' newline ...
                'let x = 122' newline ...
                'bin 1 "A" x']);
            try
                DefineBins(EEG, opts);
                testCase.verifyFail('Expected DefineBins to throw.');
            catch err
                testCase.verifyEqual(err.identifier, 'Alakazam:DefineBins');
                testCase.verifySubstring(err.message, 'already defined earlier');
            end
        end

        function aBinNumberUsedTwiceIsRejected(testCase)
        %ABINNUMBERUSEDTWICEISREJECTED  Two bins with the same number cannot
        %   be told apart by the events they tag or by a combination bin that
        %   names them, so the second is refused rather than accepted as a
        %   silent copy. The case was found in a shipped bin script.
            EEG = eegWithEvents({'112', '122'}, [100, 200]);
            opts = struct('script', [ ...
                'bin 1 "A" 112' newline ...
                'bin 1 "B" 122']);
            try
                DefineBins(EEG, opts);
                testCase.verifyFail('Expected DefineBins to throw.');
            catch err
                testCase.verifyEqual(err.identifier, 'Alakazam:DefineBins');
                testCase.verifySubstring(err.message, 'Bin 1 is defined twice');
            end
        end

        function unknownAliasReferenceIsRejected(testCase)
        %UNKNOWNALIASREFERENCEISREJECTED  A bare word that is not a
        %   defined 'let' alias (and not a quoted marker) is rejected
        %   rather than silently matching nothing.
            EEG = eegWithEvents({'112'}, 100);
            opts = struct('script', 'bin 1 "A" foo');
            try
                DefineBins(EEG, opts);
                testCase.verifyFail('Expected DefineBins to throw.');
            catch err
                testCase.verifyEqual(err.identifier, 'Alakazam:DefineBins');
                testCase.verifySubstring(err.message, 'don''t know what ''foo'' means');
            end
        end

        function comboReferencingAMissingBinIsRejected(testCase)
        %COMBOREFERENCINGAMISSINGBINISREJECTED  A combination bin that
        %   names a bin number nobody defined is caught at parse time,
        %   not as an opaque failure later in Average.
            EEG = eegWithEvents({'112'}, 100);
            opts = struct('script', [ ...
                'bin 1 "A" 112' newline ...
                'bin 2 "B" = bin 1 - bin 99']);
            try
                DefineBins(EEG, opts);
                testCase.verifyFail('Expected DefineBins to throw.');
            catch err
                testCase.verifyEqual(err.identifier, 'Alakazam:DefineBins');
                testCase.verifySubstring(err.message, 'no bin 99');
            end
        end

        function circularComboReferenceIsRejected(testCase)
        %CIRCULARCOMBOREFERENCEISREJECTED  Two combination bins that
        %   reference each other can never be computed, and are rejected
        %   as a loop rather than recursing forever.
            EEG = eegWithEvents({'112'}, 100);
            opts = struct('script', [ ...
                'bin 1 "A" = bin 2' newline ...
                'bin 2 "B" = bin 1']);
            try
                DefineBins(EEG, opts);
                testCase.verifyFail('Expected DefineBins to throw.');
            catch err
                testCase.verifyEqual(err.identifier, 'Alakazam:DefineBins');
                testCase.verifySubstring(err.message, 'forms a loop');
            end
        end

        function emptyBraceListIsRejected(testCase)
        %EMPTYBRACELISTISREJECTED  {} has no codes inside it to match.
            EEG = eegWithEvents({'112'}, 100);
            opts = struct('script', 'bin 1 "A" {}');
            try
                DefineBins(EEG, opts);
                testCase.verifyFail('Expected DefineBins to throw.');
            catch err
                testCase.verifyEqual(err.identifier, 'Alakazam:DefineBins');
                testCase.verifySubstring(err.message, 'empty');
            end
        end

        function unclosedBraceListIsRejected(testCase)
        %UNCLOSEDBRACELISTISREJECTED  A '{' with no matching '}' is
        %   caught by the tokenizer rather than reading past the script.
            EEG = eegWithEvents({'112'}, 100);
            opts = struct('script', 'bin 1 "A" {112');
            try
                DefineBins(EEG, opts);
                testCase.verifyFail('Expected DefineBins to throw.');
            catch err
                testCase.verifyEqual(err.identifier, 'Alakazam:DefineBins');
                testCase.verifySubstring(err.message, 'never closes');
            end
        end

        function invertedWindowBoundsAreRejected(testCase)
        %INVERTEDWINDOWBOUNDSAREREJECTED  A window whose low bound is
        %   greater than its high bound can never match anything, and is
        %   rejected rather than silently matching nothing forever.
            EEG = eegWithEvents({'112', '118'}, [100, 200]);
            opts = struct('script', 'bin 1 "A" 112 and next(118) within (1200,200] ms');
            try
                DefineBins(EEG, opts);
                testCase.verifyFail('Expected DefineBins to throw.');
            catch err
                testCase.verifyEqual(err.identifier, 'Alakazam:DefineBins');
                testCase.verifySubstring(err.message, 'greater than');
            end
        end

        function anyWithoutAWithinWindowIsRejected(testCase)
        %ANYWITHOUTAWITHINWINDOWISREJECTED  Unlike next/prev/adjacent,
        %   any(code) has no natural neighbour to fall back on and always
        %   needs an explicit window.
            EEG = eegWithEvents({'112'}, 100);
            opts = struct('script', 'bin 1 "A" any(112)');
            try
                DefineBins(EEG, opts);
                testCase.verifyFail('Expected DefineBins to throw.');
            catch err
                testCase.verifyEqual(err.identifier, 'Alakazam:DefineBins');
                testCase.verifySubstring(err.message, 'always needs a ''within');
            end
        end

        function unrecognisedCharacterIsRejected(testCase)
        %UNRECOGNISEDCHARACTERISREJECTED  A character that is not part of
        %   any code, keyword or punctuation the language uses is caught
        %   by the tokenizer with a pointer to exactly where it is.
            EEG = eegWithEvents({'112'}, 100);
            opts = struct('script', 'bin 1 "A" 112 @');
            try
                DefineBins(EEG, opts);
                testCase.verifyFail('Expected DefineBins to throw.');
            catch err
                testCase.verifyEqual(err.identifier, 'Alakazam:DefineBins');
                testCase.verifySubstring(err.message, 'don''t know what to do with the character');
            end
        end

        function epochWindowSegmentsTheData(testCase)
        %EPOCHWINDOWSEGMENTSTHEDATA  Passing opts.epoch alongside
        %   opts.script cuts trials around every matched event and
        %   switches DataFormat to EPOCHED.
            EEG = eegWithEvents({'112', '122', '112'}, [100, 200, 300]);
            EEG.data = zeros(2, 500); % 2 channels, continuous, long enough for the window below
            EEG.pnts = 500;
            opts = struct('script', 'bin 1 "Targets" 112', ...
                'epoch', struct('lo', -40, 'hi', 40, 'unit', 'ms'));

            [result, ~] = DefineBins(EEG, opts);

            testCase.verifyEqual(result.DataFormat, 'EPOCHED');
            testCase.verifyEqual(result.trials, 2); % the two matched 112 events
            testCase.verifyEqual(size(result.data), [2, 20, 2]); % 80ms window @ 250Hz = 20 samples
        end

        function anEpochStatementSegmentsTheData(testCase)
        %ANEPOCHSTATEMENTSEGMENTSTHEDATA  The script's own epoch line cuts
        %   the trials, with nothing passed beside it.
            EEG = epochFixture();

            [result, opts] = DefineBins(EEG, struct('script', ...
                ['epoch [-40,40] ms' newline 'bin 1 "Targets" 112']));

            testCase.verifyEqual(result.DataFormat, 'EPOCHED');
            testCase.verifyEqual(size(result.data), [2, 20, 2]);
            testCase.verifyEqual(opts.epoch, struct('lo', -40, 'hi', 40, 'unit', 'ms'), ...
                'The epoch actually cut is what is stored, so a replay cuts the same.');
        end

        function theScriptsEpochWinsOverAPassedOne(testCase)
            EEG = epochFixture();

            [result, opts] = DefineBins(EEG, struct('script', ...
                ['bin 1 "Targets" 112' newline 'epoch [-40,40] ms'], ...
                'epoch', struct('lo', -100, 'hi', 100, 'unit', 'ms')));

            testCase.verifyEqual(size(result.data, 2), 20, ...
                'The epoch line, anywhere in the script, decides the window.');
            testCase.verifyEqual(opts.epoch.lo, -40);
        end

        function eachTrialRecordsTheSampleItStartsAt(testCase)
        %EACHTRIALRECORDSTHESAMPLEITSTARTSAT  The recording's samples hold
        %   their own numbers, so the first point of every trial must be the
        %   sample its epochStart names.
            EEG = epochFixture();
            EEG.data = repmat(1:500, 2, 1);

            result = DefineBins(EEG, struct('script', ...
                ['epoch [-40,40] ms' newline 'bin 1 "Targets" 112']));

            testCase.verifyEqual(result.etc.alz.epochStart, [90 290], ...
                'The events at 100 and 300, less 40 ms at 250 Hz.');
            testCase.verifyEqual(squeeze(result.data(1, 1, :))', result.etc.alz.epochStart);
        end

        function anEpochCanBeGivenInSamples(testCase)
            EEG = epochFixture();

            result = DefineBins(EEG, struct('script', ...
                ['epoch [-10,10] samples' newline 'bin 1 "Targets" 112']));

            testCase.verifyEqual(size(result.data, 2), 20);
        end

        function tagsOnlyIgnoresTheEpoch(testCase)
        %TAGSONLYIGNORESTHEEPOCH  Deconvolve needs the continuous recording
        %   with bin tags; an epoch line in its bins must not cut it.
            EEG = epochFixture();

            [result, opts] = DefineBins(EEG, struct('script', ...
                ['epoch [-40,40] ms' newline 'bin 1 "Targets" 112'], 'tagsOnly', true));

            testCase.verifyEqual(size(result.data), [2, 500]);
            testCase.verifyEmpty(opts.epoch);
        end

        function aSecondEpochIsRefused(testCase)
            testCase.verifyParseError( ...
                ['epoch [-40,40] ms' newline 'epoch [-100,100] ms' newline 'bin 1 "A" 112'], ...
                'sets the epoch twice');
        end

        function anEpochInEventsIsRefused(testCase)
            testCase.verifyParseError( ...
                ['epoch [-2,2] events' newline 'bin 1 "A" 112'], 'ms or samples');
        end

        function anEmptyEpochIsRefused(testCase)
            testCase.verifyParseError( ...
                ['epoch [100,100] ms' newline 'bin 1 "A" 112'], 'no data to cut');
        end

        function textAfterTheEpochWindowIsRefused(testCase)
            testCase.verifyParseError( ...
                ['epoch [-40,40] ms 112' newline 'bin 1 "A" 112'], 'nothing after it');
        end

        function textBeforeTheFirstStatementIsRefused(testCase)
        %TEXTBEFORETHEFIRSTSTATEMENTISREFUSED  It used to be dropped without
        %   a word, which is how the README's epoch lines did nothing.
            testCase.verifyParseError( ...
                ['window [-40,40] ms' newline 'bin 1 "A" 112'], 'don''t recognise this');
        end

        function commentsBeforeTheFirstStatementAreFine(testCase)
            EEG = eegWithEvents({'112'}, 100);

            [~, opts] = DefineBins(EEG, struct('script', ...
                ['% a comment first' newline 'bin 1 "A" 112']));

            testCase.verifyNumElements(opts.bins, 1);
        end

        function unmatchedEventsGetAnExplicitInvalidEpochNumber(testCase)
        %UNMATCHEDEVENTSGETANEXPLICITINVALIDEPOCHNUMBER  An event that
        %   matched no bin belongs to no trial, and cutEpochs must leave it
        %   with .epoch = 0 (an explicit, always-invalid sentinel), not
        %   MATLAB's default []. See cutEpochs.m's own comment: eeg_checkset
        %   silently drops an empty .epoch from its own concatenated
        %   [EEG.event.epoch] rather than treating it as present-but-invalid,
        %   so [] can survive its pruning undetected -- 0 cannot.
            EEG = eegWithEvents({'999', '112', '112'}, [20, 100, 300]);
            EEG.data = zeros(2, 500);
            opts = struct('script', 'bin 1 "Targets" 112', ...
                'epoch', struct('lo', -40, 'hi', 40, 'unit', 'ms'));

            [result, ~] = DefineBins(EEG, opts);

            testCase.verifyEqual(result.event(1).epoch, 0);
            testCase.verifyEqual(result.event(2).epoch, 1);
            testCase.verifyEqual(result.event(3).epoch, 2);
        end

        function anchorLatenciesAreOnTheConcatenatedTimelineImmediatelyAfterEpoching(testCase)
        %ANCHORLATENCIESAREONTHECONCATENATEDTIMELINEIMMEDIATELYAFTEREPOCHING
        %   cutEpochs must rewrite each anchor's .latency onto EEGLAB's
        %   per-epoch-concatenated numbering itself (see
        %   rewriteEpochedEventLatencies), not leave it on the stale
        %   original-continuous-recording sample number, so the dataset is
        %   already EEGLAB-consistent for every later pipeline step, not
        %   just at eventual .set export.
            EEG = eegWithEvents({'112', '112'}, [100, 300]);
            EEG.data = zeros(2, 500);
            opts = struct('script', 'bin 1 "Targets" 112', ...
                'epoch', struct('lo', -40, 'hi', 40, 'unit', 'ms'));

            [result, ~] = DefineBins(EEG, opts);

            zeroSample = find(abs(result.times) < 1e-9, 1);
            testCase.verifyEqual(result.event(1).latency, zeroSample);
            testCase.verifyEqual(result.event(2).latency, result.pnts + zeroSample);
        end

        function anUnmatchedEventWithAnInBoundsLatencySurvivesARealEegCheckestRoundTrip(testCase)
        %ANUNMATCHEDEVENTWITHANINBOUNDSLATENCYSURVIVESAREALEEGCHECKESTROUNDTRIP
        %   THE BUG THIS PINS. eeg_checkset('eventconsistency')'s own early
        %   "invalid epoch" pruning computes allepochs = [EEG.event.epoch];
        %   an event left with MATLAB's default [] for .epoch is silently
        %   DROPPED from that concatenation rather than counted as invalid,
        %   so it is never flagged there. Whether such an event then gets
        %   pruned anyway depends purely on luck: eeg_checkset separately
        %   prunes events whose stale, still-continuous-recording .latency
        %   exceeds EEG.pnts*EEG.trials. A short test fixture's non-anchor
        %   event latency easily exceeds that small bound by accident; a
        %   real, long recording's does not always. When it survives both,
        %   it reaches eeg_checkset's later "build epoch structure" step
        %   with a .epoch that no longer matches every other field's
        %   length, which throws inside eeg_point2lat -- surfaced only as
        %   EEGLAB's own blocking "minor problem encountered when
        %   generating the EEG epoch structure" dialog. Reported directly:
        %   this froze Apply Template on the RIFT template. This fixture's
        %   own non-anchor latency (20) is deliberately kept well inside
        %   EEG.pnts*EEG.trials (40) so it cannot be pruned by luck, and
        %   only cutEpochs' own explicit .epoch = 0 sentinel (see
        %   unmatchedEventsGetAnExplicitInvalidEpochNumber above) can catch
        %   it -- without that fix, this test reproduces the exact reported
        %   dialog as a thrown MATLAB error instead.
            testCase.assumeTrue(~isempty(which('eeglab')), ...
                'EEGLAB not found on the MATLAB path -- skipping the round-trip test.');
            if isempty(which('eeg_checkset'))
                eeglab('nogui');
            end
            testCase.assumeFalse(isempty(which('eeg_checkset')), ...
                'EEGLAB''s eeg_checkset is not available -- skipping the round-trip test.');

            EEG = inBoundsUnmatchedFixture();
            opts = struct('script', 'bin 1 "Targets" 112', ...
                'epoch', struct('lo', -40, 'hi', 40, 'unit', 'ms'));
            [result, ~] = DefineBins(EEG, opts);

            result = eeg_checkset(result, 'eventconsistency');

            testCase.verifyEqual(numel(result.epoch), 2, ...
                'no trial anchor should have been pruned.');
            testCase.verifyEqual(numel(result.event), 2, ...
                'the unmatched event should have been pruned.');
            testCase.verifyTrue(all(strcmp({result.event.type}, '112')));
            for k = 1:numel(result.epoch)
                testCase.verifyEqual(result.epoch(k).eventlatency, 0, sprintf( ...
                    'trial %d''s own anchor should be at exactly latency 0 within its epoch.', k));
            end
        end

        % ---- reaction time ------------------------------------------------
        function reactionTimeIsIndependentOfTermOrder(testCase)
        %REACTIONTIMEISINDEPENDENTOFTERMORDER  The regression this pins.
        %   evalRel captures whatever latency it matched, in either
        %   direction, and 'and' takes the first non-NaN capture left to
        %   right. So a bin written with its preceding-context relation
        %   first recorded the CUE delay, negative, as the reaction time,
        %   while the identical bin with the relations the other way round
        %   recorded the response. The rt depended on typing order.
            EEG = testCase.cueStimulusResponse();

            forward = testCase.rtOf(EEG, 'bin 1 "x" 112 and next(118)');
            cueFirst = testCase.rtOf(EEG, 'bin 1 "x" 112 and prev(50) and next(118)');
            cueLast  = testCase.rtOf(EEG, 'bin 1 "x" 112 and next(118) and prev(50)');

            testCase.verifyEqual(forward, 700, 'AbsTol', 1e-9);
            testCase.verifyEqual(cueFirst, forward, ...
                'A preceding relation is stealing the reaction time again.');
            testCase.verifyEqual(cueLast, forward);
        end

        function aBackwardOnlyMatchHasNoReactionTime(testCase)
        %ABACKWARDONLYMATCHHASNOREACTIONTIME  A reaction time is the delay
        %   to a LATER event; a bin whose only relation looks backwards has
        %   none, and NaN says so rather than a negative number pretending.
            EEG = testCase.cueStimulusResponse();

            testCase.verifyTrue(isnan(testCase.rtOf(EEG, 'bin 1 "x" 112 and prev(50)')));
        end

        function timelockCanStillLockBackwards(testCase)
        %TIMELOCKCANSTILLLOCKBACKWARDS  The other half of the fix. evalRel's
        %   capture had to keep working in both directions, because
        %   'timelock' legitimately centres the epoch on a preceding event.
        %   Only the rt derived from it is restricted to forward matches.
            EEG = testCase.cueStimulusResponse();
            spec = DefineBinsEngine.parseSpec('bin 1 "x" 112 and prev(50) timelock prev(50)');

            [~, ~, centerLat] = DefineBinsEngine.evaluateBins(EEG, spec.bins);

            testCase.verifyTrue(any(centerLat == 1), ...
                'timelock no longer reaches the preceding cue at latency 1.');
        end

        % ---- numeric code ranges -------------------------------------------
        function aNumericRangeExpandsToItsCodes(testCase)
        %ANUMERICRANGEEXPANDSTOITSCODES  ERPLAB's BINLISTER has code ranges
        %   and they are genuinely useful for a block of stimulus codes.
            spec = DefineBinsEngine.parseSpec('bin 1 "x" 21-24');

            testCase.verifyEqual(cellstr(spec.bins(1).expr.codes), {'21', '22', '23', '24'});
        end

        function rangesWorkInsideSetsAndPipes(testCase)
            inSet = DefineBinsEngine.parseSpec('bin 1 "x" {21-23 40}');
            inPipe = DefineBinsEngine.parseSpec('bin 1 "x" 21-22|40');

            testCase.verifyEqual(cellstr(inSet.bins(1).expr.codes), {'21', '22', '23', '40'});
            testCase.verifyEqual(cellstr(inPipe.bins(1).expr.codes), {'21', '22', '40'});
        end

        function spacingAroundTheDashDoesNotMatter(testCase)
        %SPACINGAROUNDTHEDASHDOESNOTMATTER  The lexer reads a leading '-' as
        %   the start of a negative number, so the same range arrives as two
        %   different token shapes depending on the spaces: "21-30" and
        %   "21 -30" become num(21) num(-30), while "21 - 30" and "21- 30"
        %   become num(21) punc('-') num(30). Event codes are never negative,
        %   so neither shape can mean anything else and all four spellings
        %   are the one range.
            for script = {'bin 1 "x" {21-30}', 'bin 1 "x" {21 -30}', ...
                    'bin 1 "x" {21 - 30}', 'bin 1 "x" {21- 30}'}
                spec = DefineBinsEngine.parseSpec(script{1});
                testCase.verifyNumElements(spec.bins(1).expr.codes, 10, ...
                    sprintf('%s should be the range 21 to 30.', script{1}));
            end
        end

        function aNegativeCodeIsRefused(testCase)
        %ANEGATIVECODEISREFUSED  Event codes are never negative. That is what
        %   makes the range spellings above unambiguous, so it is worth
        %   stating as a rule rather than leaving implicit.
            testCase.verifyError(@() DefineBinsEngine.parseSpec('bin 1 "x" -30'), ...
                'Alakazam:DefineBins');
        end

        function cancellingTheDialogIsNotAnError(testCase)
        %CANCELLINGTHEDIALOGISNOTANERROR  Every transformation says "the
        %   user changed their mind" by returning an empty EEG, which
        %   Alakazam.onTransformation reads as cancelled: nothing persisted,
        %   nothing shown. DefineBins threw instead, so backing out of the
        %   dialog raised an error that then had to be dismissed -- a second
        %   click to undo a decision already made.
        %
        %   Checked at the source, because the cancel path is interactive and
        %   MATLAB's -batch refuses blocking dialogs. Weaker than driving it,
        %   but it does catch the throw coming back.
            root = fileparts(fileparts(mfilename('fullpath')));
            src = fileread(fullfile(root, 'src', 'Transformations', ...
                'DefineBins', 'DefineBins.m'));

            start = strfind(src, 'result = DefineBinsDialog(');
            testCase.assertNotEmpty(start, 'The interactive branch has moved.');
            branch = src(start(1):min(start(1) + 800, numel(src)));

            testCase.verifySubstring(branch, 'EEG = [];');
            testCase.verifySubstring(branch, 'options = [];');
            testCase.verifyEmpty(strfind(branch, 'throw(MException'), ...
                'Cancelling DefineBins raises an error again.'); %#ok<STREMP>
        end

        % ---- the s-prefix rule ---------------------------------------------
        function anSPrefixIsDroppedSoCodesAreNumeric(testCase)
        %ANSPREFIXISDROPPEDSOCODESARENUMERIC  BrainVision writes stimulus
        %   markers as "S 12"/"S201", so a recording's codes arrive as text
        %   even though they are numbers with a prefix. Dropping it makes
        %   them numeric again: writable unquoted, comparable numerically,
        %   and coverable by a range.
            EEG = testCase.brainVisionMarkers();

            testCase.verifyEqual(testCase.matchesFor(EEG, 'bin 1 "x" 25'), ...
                {'S 25', '25'});
            testCase.verifyEqual(testCase.matchesFor(EEG, 'bin 1 "x" "S25"'), ...
                {'S 25', '25'});
        end

        function aRangeSpansPrefixedCodes(testCase)
        %ARANGESPANSPREFIXEDCODES  The point of the rule: once the prefix is
        %   gone the codes are numeric, so a range covers them.
            EEG = testCase.brainVisionMarkers();

            testCase.verifyEqual(testCase.matchesFor(EEG, 'bin 1 "x" 21-30'), ...
                {'S21', 'S 25', 'S30', '25'});
        end

        function onlySIsDropped(testCase)
        %ONLYSISDROPPED  Response markers keep their prefix. R codes
        %   routinely reuse the same numbers as S codes, so stripping both
        %   would merge a stimulus with the response to it.
            EEG = testCase.brainVisionMarkers();

            testCase.verifyEqual(testCase.matchesFor(EEG, 'bin 1 "x" "R21"'), {'R21'});
            testCase.verifyFalse(any(strcmp(testCase.matchesFor(EEG, 'bin 1 "x" 21'), 'R21')), ...
                'The numeric code 21 must not match the response marker R21.');
        end

        function theSuffixMustBeEntirelyNumeric(testCase)
        %THESUFFIXMUSTBEENTIRELYNUMERIC  "S1a" is a text marker that happens
        %   to start with an s, not a prefixed number, and must survive.
            EEG = eegWithEvents({'S1a', 'S1'}, [100, 200]);

            testCase.verifyEqual(testCase.matchesFor(EEG, 'bin 1 "x" "S1a"'), {'S1a'});
            testCase.verifyEqual(testCase.matchesFor(EEG, 'bin 1 "x" 1'), {'S1'});
        end

        function wildcardsLoseThePrefixToo(testCase)
        %WILDCARDSLOSETHEPREFIXTOO  A pattern like "s??" has to be stripped
        %   as well, or it would keep an 's' the events no longer have and
        %   match nothing -- which is exactly what would break the "s??"
        %   example in the language reference.
            EEG = eegWithEvents({'s11', 's22', 'S30', 'other'}, [100, 200, 300, 400]);

            testCase.verifyEqual(testCase.matchesFor(EEG, 'bin 1 "x" "s??"'), ...
                {'s11', 's22', 'S30'});
        end

        function aDescendingRangeIsRefused(testCase)
        %ADESCENDINGRANGEISREFUSED  "30-21" covers nothing. It used to be
        %   read as two codes, which is no longer possible now that a
        %   negative code is itself an error.
            testCase.verifyError(@() DefineBinsEngine.parseSpec('bin 1 "x" {30-21}'), ...
                'Alakazam:DefineBins');
        end

        function anAbsurdRangeIsRefused(testCase)
        %ANABSURDRANGEISREFUSED  A mistyped range would otherwise build a
        %   hundred thousand code literals and look like a hang.
            testCase.verifyError(@() DefineBinsEngine.parseSpec('bin 1 "x" 1-100000'), ...
                'Alakazam:DefineBins');
        end

        function rangesMatchTheEventsTheyCover(testCase)
        %RANGESMATCHTHEEVENTSTHEYCOVER  Parsing to the right codes is not the
        %   same as matching the right events.
            EEG = eegWithEvents({'21', '25', '31'}, [100, 200, 300]);
            spec = DefineBinsEngine.parseSpec('bin 1 "x" 21-25');

            [~, bindesc] = DefineBinsEngine.evaluateBins(EEG, spec.bins);

            testCase.verifyEqual(bindesc(1).n, 2, ...
                'The range should match the 21 and the 25, but not the 31.');
        end
        % ---- reaction-time windows relative to the mean -----------------
        function aWindowInMillisecondsFiltersOnReactionTime(testCase)
        %AWINDOWINMILLISECONDSFILTERSONREACTIONTIME  The fixed window the
        %   relative one extends: only the RTs inside it are kept, and a
        %   bin without a relative bound records no trimming.
            EEG = stimulusResponse([300 500 700 900]);

            [result, ~] = DefineBins(EEG, struct('script', ...
                'bin 1 "x" 112 and next(118) rt within (400,800] ms'));

            testCase.verifyEqual(DefineBinsTest.rtsOf(result, 1), [500 700], 'AbsTol', 1e-9);
            testCase.verifyEmpty(result.bindesc(1).rtTrim);
        end

        function meanPlusSdDropsTheSlowOutlier(testCase)
        %MEANPLUSSDDROPSTHESLOWOUTLIER  The rule the feature exists for:
        %   mean + 2.5 sd of the bin's own reaction times, with the sample
        %   standard deviation, computed once over every matched trial.
            rts = [400 400 400 400 400 400 400 400 400 2000];
            EEG = stimulusResponse(rts);

            [result, ~] = DefineBins(EEG, struct('script', ...
                'bin 1 "x" 112 and next(118) rt within (0, mean + 2.5 sd] ms'));

            trim = result.bindesc(1).rtTrim;
            testCase.verifyEqual(result.bindesc(1).n, 9);
            testCase.verifyEqual(trim.mean, mean(rts), 'AbsTol', 1e-9);
            testCase.verifyEqual(trim.sd, std(rts), 'AbsTol', 1e-9);
            testCase.verifyEqual(trim.hi, mean(rts) + 2.5 * std(rts), 'AbsTol', 1e-9);
            testCase.verifyEqual(trim.lo, 0);
            testCase.verifyEqual(trim.nRt, 10);
            testCase.verifyEqual(trim.removed, 1);
            testCase.verifyEmpty(trim.note);
        end

        function bothBoundsMayBeRelative(testCase)
        %BOTHBOUNDSMAYBERELATIVE  [mean - k sd, mean + k sd] trims both
        %   tails, and 'mean -2 sd' (read by the tokenizer as a negative
        %   number) means the same as 'mean - 2 sd'.
            rts = [100 500 500 500 500 500 500 500 500 900];
            EEG = stimulusResponse(rts);
            spaced = 'bin 1 "x" 112 and next(118) rt within [mean - 2 sd, mean + 2 sd] ms';
            joined = 'bin 1 "x" 112 and next(118) rt within [mean -2 sd, mean+2sd] ms';

            [a, ~] = DefineBins(EEG, struct('script', spaced));
            [b, ~] = DefineBins(EEG, struct('script', joined));

            m = mean(rts); s = std(rts);
            testCase.verifyEqual(DefineBinsTest.rtsOf(a, 1), rts(rts >= m - 2*s & rts <= m + 2*s), 'AbsTol', 1e-9);
            testCase.verifyEqual(a.bindesc(1).n, 8, ...
                'Both the 100 ms and the 900 ms trial lie beyond two SDs of these RTs.');
            testCase.verifyEqual(DefineBinsTest.rtsOf(b, 1), DefineBinsTest.rtsOf(a, 1));
        end

        function aBareMeanIsABound(testCase)
        %ABAREMEANISABOUND  'mean' on its own is mean + 0 sd: the trials at
        %   or below the mean, here.
            EEG = stimulusResponse([300 400 500 600]);

            [result, ~] = DefineBins(EEG, struct('script', ...
                'bin 1 "x" 112 and next(118) rt within (0, mean] ms'));

            testCase.verifyEqual(DefineBinsTest.rtsOf(result, 1), [300 400], 'AbsTol', 1e-9);
        end

        function theCutoffIsComputedPerRecording(testCase)
        %THECUTOFFISCOMPUTEDPERRECORDING  Why it belongs in the language:
        %   a compiled plan replayed on another recording trims that
        %   recording at its own mean and sd, not at the first one's.
            fast = stimulusResponse([300 300 300 300 300 300 300 300 300 1200]);
            slow = stimulusResponse([900 900 900 900 900 900 900 900 900 3000]);
            script = 'bin 1 "x" 112 and next(118) rt within (0, mean + 2.5 sd] ms';

            [first, options] = DefineBins(fast, struct('script', script));
            [replayed, ~] = DefineBins(slow, options);

            testCase.verifyEqual(first.bindesc(1).n, 9);
            testCase.verifyEqual(replayed.bindesc(1).n, 9, ...
                'The slow recording''s 900 ms trials must survive its own cutoff.');
            testCase.verifyGreaterThan(replayed.bindesc(1).rtTrim.hi, ...
                first.bindesc(1).rtTrim.hi);
        end

        function aSingleReactionTimeKeepsNothingAndSaysWhy(testCase)
        %ASINGLEREACTIONTIMEKEEPSNOTHINGANDSAYSWHY  One RT has no standard
        %   deviation. Keeping the trial would skip the rule without a
        %   word, so the bin is empty and the note says why.
            EEG = stimulusResponse(500);

            [result, ~] = DefineBins(EEG, struct('script', ...
                'bin 1 "x" 112 and next(118) rt within (0, mean + 2.5 sd] ms'));

            testCase.verifyEqual(result.bindesc(1).n, 0);
            testCase.verifySubstring(result.bindesc(1).rtTrim.note, 'standard deviation');
        end

        function aPlanWithoutRelativeFieldsStillReplays(testCase)
        %APLANWITHOUTRELATIVEFIELDSSTILLREPLAYS  A plan compiled before
        %   relative bounds existed has no loSd/hiSd, and one that went
        %   through jsonencode/jsondecode has [] where NaN was. Both are a
        %   plain window.
            EEG = stimulusResponse([300 500 700]);
            spec = DefineBinsEngine.parseSpec( ...
                'bin 1 "x" 112 and next(118) rt within (400,800] ms');
            old = spec.bins;
            old(1).rtWindow = rmfield(old(1).rtWindow, {'loSd', 'hiSd'});
            decoded = spec.bins;
            decoded(1).rtWindow.loSd = [];
            decoded(1).rtWindow.hiSd = [];

            fromOld = DefineBinsTest.tagged(EEG, old);
            fromDecoded = DefineBinsTest.tagged(EEG, decoded);

            testCase.verifyEqual(DefineBinsTest.rtsOf(fromOld, 1), [500 700], 'AbsTol', 1e-9);
            testCase.verifyEqual(DefineBinsTest.rtsOf(fromDecoded, 1), [500 700], 'AbsTol', 1e-9);
        end

        function meanAndSdAreStillFreeAsAliasNames(testCase)
        %MEANANDSDARESTILLFREEASALIASNAMES  The words mean something only
        %   inside a reaction-time window, so a script that already named
        %   an alias mean keeps working.
            EEG = eegWithEvents({'112', '122'}, [100, 200]);

            [result, ~] = DefineBins(EEG, struct('script', ...
                ['let mean = 112' newline 'bin 1 "x" mean']));

            testCase.verifyEqual(DefineBinsTest.membersOf(result, 1), 1);
        end

        function relativeBoundSpellingErrorsAreExplained(testCase)
        %RELATIVEBOUNDSPELLINGERRORSAREEXPLAINED  The likely slips each
        %   get a message that names the fix.
            base = 'bin 1 "x" 112 and next(118) rt within ';
            testCase.verifyParseError([base '(0, 2.5 sd] ms'], 'needs the word mean');
            testCase.verifyParseError([base '(0, mean + 2.5] ms'], 'needs the word sd');
            testCase.verifyParseError([base '(0, mean 2 sd] ms'], 'expected + or -');
            testCase.verifyParseError([base '(0, average] ms'], 'mean, median or a percentile');
            testCase.verifyParseError([base '[mean + 1 sd, mean - 1 sd] ms'], 'other way round');
            testCase.verifyParseError([base '(800, 400] ms'], 'greater than');
            testCase.verifyParseError([base '(0, mean + 2 sd] samples'], 'milliseconds');
        end

        % ---- selecting events by their own fields --------------------------
        function aFieldTestSelectsBeatsByInterval(testCase)
        %AFIELDTESTSELECTSBEATSBYINTERVAL  The case it exists for: the
        %   Heartbeats plugin gives every beat its interbeat interval, and
        %   a bin keeps the beats whose interval lies in the window.
            EEG = heartbeats([700 900 1100 1300]);

            matched = testCase.eventsFor(EEG, ...
                'bin 1 "x" "heartbeat" and field ibi within (800,1200]');

            testCase.verifyEqual(matched, [2 3]);
        end

        function aFieldTestJoinsWithoutAnd(testCase)
        %AFIELDTESTJOINSWITHOUTAND  Like any other term, it is and-ed with
        %   its neighbour without the keyword, and it can stand in a let.
            EEG = heartbeats([700 900 1100 1300]);

            implied = testCase.eventsFor(EEG, ...
                'bin 1 "x" "heartbeat" field ibi within [1000,2000]');
            named = testCase.eventsFor(EEG, ...
                ['let slow = field ibi within [1000,2000]' newline ...
                 'bin 1 "x" "heartbeat" and slow']);

            testCase.verifyEqual(implied, [3 4]);
            testCase.verifyEqual(named, implied);
        end

        function aMissingValueIsInNoWindow(testCase)
        %AMISSINGVALUEISINNOWINDOW  The last beat before a cut has a NaN
        %   interval: in no window, so out of every interval-based bin and
        %   in the same bin written under 'not'.
            EEG = heartbeats([900 NaN 900]);

            inside = testCase.eventsFor(EEG, ...
                'bin 1 "x" "heartbeat" and field ibi within [0,5000]');
            outside = testCase.eventsFor(EEG, ...
                'bin 1 "x" "heartbeat" and not field ibi within [0,5000]');

            testCase.verifyEqual(inside, [1 3]);
            testCase.verifyEqual(outside, 2);
        end

        function anAliasCalledFieldKeepsItsMeaning(testCase)
        %ANALIASCALLEDFIELDKEEPSITSMEANING  'field' is a plain word, so a
        %   script that named an alias field before still works.
            EEG = eegWithEvents({'112', '122'}, [100, 200]);

            [result, ~] = DefineBins(EEG, struct('script', ...
                ['let field = 112' newline 'bin 1 "x" field']));

            testCase.verifyEqual(DefineBinsTest.membersOf(result, 1), 1);
        end

        function aFieldNoEventHasIsRefusedWithTheFieldsThatExist(testCase)
        %AFIELDNOEVENTHASISREFUSEDWITHTHEFIELDSTHATEXIST  A slip of the
        %   name, or Heartbeats not run, would otherwise give an empty bin
        %   without a word.
            EEG = heartbeats([900 900]);
            try
                DefineBins(EEG, struct('script', 'bin 1 "x" field IBI within (0,2000]'));
                testCase.verifyFail('Expected DefineBins to refuse an unknown field.');
            catch err
                testCase.verifyEqual(err.identifier, 'Alakazam:DefineBins');
                testCase.verifySubstring(err.message, 'did you mean field ibi');
            end
        end

        function fieldTestSpellingErrorsAreExplained(testCase)
        %FIELDTESTSPELLINGERRORSAREEXPLAINED  The likely slips each get a
        %   message that names the fix.
            base = 'bin 1 "x" "heartbeat" and ';
            testCase.verifyParseError([base 'field ibi within (800,1200] ms'], 'takes no unit');
            testCase.verifyParseError([base 'field ibi (800,1200]'], 'needs a window');
            testCase.verifyParseError([base 'field within (800,1200]'], 'name of an event field');
            testCase.verifyParseError([base 'field ibi within (1200,800]'], 'greater than');
        end

        % ---- value tests: statistics, ranks and logarithms ----------------
        function aMedianSplitPartitionsTheTrials(testCase)
        %AMEDIANSPLITPARTITIONSTHETRIALS  (0, median] and (median, inf) part
        %   the trials into halves, each bin taking the median of the same
        %   trials, and rank(rt) within [0, 50] and (50, 100] part them the
        %   same way. What the window came to is recorded per bin.
            rts = [312 452 520 380 700 292 640 412];
            EEG = stimulusResponse(rts);
            script = strjoin({ ...
                'bin 1 "fast" 112 and next(118) rt within (0, median] ms', ...
                'bin 2 "slow" 112 and next(118) rt within (median, inf) ms', ...
                'bin 3 "fast by rank" 112 and next(118) rank(rt) within [0, 50]', ...
                'bin 4 "slow by rank" 112 and next(118) rank(rt) within (50, 100]'}, newline);

            [result, ~] = DefineBins(EEG, struct('script', script));

            d = result.bindesc;
            m = median(rts);
            testCase.verifyEqual(sort(DefineBinsTest.rtsOf(result, 1)), sort(rts(rts <= m)), 'AbsTol', 1e-9);
            testCase.verifyEqual(sort(DefineBinsTest.rtsOf(result, 2)), sort(rts(rts > m)), 'AbsTol', 1e-9);
            testCase.verifyEqual(DefineBinsTest.membersOf(result, 3), DefineBinsTest.membersOf(result, 1));
            testCase.verifyEqual(DefineBinsTest.membersOf(result, 4), DefineBinsTest.membersOf(result, 2));
            record = d(1).filters;
            testCase.verifyEqual(record.text, 'rt within (0, median] ms');
            testCase.verifyEqual(record.median, m, 'AbsTol', 1e-9);
            testCase.verifyEqual([record.lo record.hi], [0 m], 'AbsTol', 1e-9);
            testCase.verifyEqual([record.n record.removed], [8 4]);
            testCase.verifyEmpty(record.note);
            testCase.verifyEqual(d(2).filters.hi, Inf);
            testCase.verifyEmpty(d(1).rtTrim, 'A median is not a mean: no rtTrim.');
        end

        function ranksArePercentilesAndTiesShareOne(testCase)
        %RANKSAREPERCENTILESANDTIESSHAREONE  rank is 100 (r - 0.5) / n, tied
        %   values sharing the mean of their ranks: 600, 700, 700, 800 rank
        %   12.5, 50, 50 and 87.5.
            EEG = heartbeats([600 700 700 800]);

            lowest = testCase.eventsFor(EEG, ...
                'bin 1 "x" "heartbeat" and rank(field ibi) within [0, 25]');
            tied = testCase.eventsFor(EEG, ...
                'bin 1 "x" "heartbeat" and rank(field ibi) within [50, 50]');
            highest = testCase.eventsFor(EEG, ...
                'bin 1 "x" "heartbeat" and rank(field ibi) within (87, 88)');

            testCase.verifyEqual(lowest, 1);
            testCase.verifyEqual(tied, [2 3]);
            testCase.verifyEqual(highest, 4);
        end

        function aLogarithmIsTestedOnItsOwnStatistics(testCase)
        %ALOGARITHMISTESTEDONITSOWNSTATISTICS  log(rt) within mean +- 1 sd
        %   takes the mean and sd of the logarithms; a log of a field with
        %   number bounds is a term like any other, and a value of 0 or
        %   less has no logarithm, so it lies in no window.
            rts = [296 352 400 452 500 600 800 1200];
            EEG = stimulusResponse(rts);
            [result, ~] = DefineBins(EEG, struct('script', ...
                'bin 1 "x" 112 and next(118) log(rt) within [mean - 1 sd, mean + 1 sd]'));
            L = log(rts);
            kept = rts(L >= mean(L) - std(L) & L <= mean(L) + std(L));
            testCase.verifyEqual(sort(DefineBinsTest.rtsOf(result, 1)), sort(kept), 'AbsTol', 1e-9);
            testCase.verifyEqual(result.bindesc(1).filters.mean, mean(L), 'AbsTol', 1e-12);

            beats = heartbeats([600 700 900 1200 0]);
            testCase.verifyEqual(testCase.eventsFor(beats, ...
                'bin 1 "x" "heartbeat" and log(field ibi) within (6.5, 7]'), [2 3]);
            testCase.verifyEqual(testCase.eventsFor(beats, ...
                'bin 1 "x" "heartbeat" and not log(field ibi) within (-inf, inf)'), 5, ...
                'An interval of 0 has no logarithm: in no window, so under not.');
        end

        function tukeysFencesUsePercentilesAsPrctileDoes(testCase)
        %TUKEYSFENCESUSEPERCENTILESASPRCTILEDOES  [p25 - 1.5 iqr, p75 + 1.5
        %   iqr] with the percentiles defined as prctile defines them: for
        %   these nine, p25 = 404 + 0.75 * 4 = 407 and p75 = 424 + 0.25 * 4
        %   = 425, so the fences are 380 and 452 and the 2000 ms trial goes.
            rts = [400 404 408 412 416 420 424 428 2000];
            EEG = stimulusResponse(rts);

            [result, ~] = DefineBins(EEG, struct('script', ...
                'bin 1 "x" 112 and next(118) rt within [p25 - 1.5 iqr, p75 + 1.5 iqr] ms'));

            record = result.bindesc(1).filters;
            testCase.verifyEqual(record.iqr, 18, 'AbsTol', 1e-9);
            testCase.verifyEqual([record.lo record.hi], [380 452], 'AbsTol', 1e-9);
            testCase.verifyEqual(result.bindesc(1).n, 8);
            if exist('prctile', 'file') == 2
                testCase.verifyEqual([407 425], prctile(rts, [25 75]), 'AbsTol', 1e-9, ...
                    'The hand-worked percentiles are prctile''s.');
            end
        end

        function aMadIsScaledToTheStandardDeviation(testCase)
        %AMADISSCALEDTOTHESTANDARDDEVIATION  mad is 1.4826 times the median
        %   absolute deviation (Leys et al., 2013): 8 here, so median + 3 mad
        %   is 412 + 35.6 and the 2000 ms trial goes.
            rts = [400 404 408 412 416 420 2000];
            EEG = stimulusResponse(rts);

            [result, ~] = DefineBins(EEG, struct('script', ...
                'bin 1 "x" 112 and next(118) rt within [median - 3 mad, median + 3 mad] ms'));

            record = result.bindesc(1).filters;
            testCase.verifyEqual(record.mad, 1.4826 * 8, 'AbsTol', 1e-9);
            testCase.verifyEqual(record.hi, 412 + 3 * 1.4826 * 8, 'AbsTol', 1e-9);
            testCase.verifyEqual(result.bindesc(1).n, 6);
        end

        function aFieldMayBeSplitAtItsMedian(testCase)
        %AFIELDMAYBESPLITATITSMEDIAN  The longer half of the intervals.
            EEG = heartbeats([600 700 800 900 1000]);
            testCase.verifyEqual(testCase.eventsFor(EEG, ...
                'bin 1 "x" "heartbeat" and field ibi within (median, inf)'), [4 5]);
        end

        function theStatisticsAreThoseOfTheRestOfTheBin(testCase)
        %THESTATISTICSARETHOSEOFTHERESTOFTHEBIN  A term (hr below 100) limits
        %   the trials a rank is taken among: the first beat is not one of
        %   them, so the lower half of the other five keeps three. And two
        %   tests about the trials each take the same trials, not what the
        %   other left: (0, median] keeps the four fastest, rank > 25 the six
        %   slowest, together the two in between.
            EEG = heartbeats([600 700 800 900 1000 1100]);
            [EEG.event.hr] = deal(120, 90, 90, 90, 90, 90);
            testCase.verifyEqual(testCase.eventsFor(EEG, ['bin 1 "x" "heartbeat" and ' ...
                'field hr within [0, 100] and rank(field ibi) within [0, 50]']), [2 3 4]);

            rts = [300 340 380 420 460 500 540 580];
            trials = stimulusResponse(rts);
            [result, ~] = DefineBins(trials, struct('script', ['bin 1 "x" 112 and next(118) ' ...
                'rt within (0, median] ms and rank(rt) within (25, 100]']));
            testCase.verifyEqual(sort(DefineBinsTest.rtsOf(result, 1)), [380 420], 'AbsTol', 1e-9);
        end

        function aTestAboutTheTrialsMayStandInALet(testCase)
        %ATESTABOUTTHETRIALSMAYSTANDINALET  An alias holding one is the same
        %   as writing it out; and an alias called rank or log keeps its
        %   meaning, as one called field does.
            EEG = stimulusResponse([300 400 500 600]);
            inline = testCase.eventsFor(EEG, ...
                'bin 1 "x" 112 and next(118) rank(rt) within [0, 50]');
            aliased = testCase.eventsFor(EEG, ['let fast = rank(rt) within [0, 50]' newline ...
                'bin 1 "x" 112 and next(118) fast']);
            testCase.verifyEqual(aliased, inline);
            testCase.verifyNumElements(inline, 2);

            named = testCase.matchesFor(EEG, ['let rank = 118' newline 'bin 1 "x" rank']);
            testCase.verifyEqual(unique(named), {'118'});
        end

        function aValuePlanReplaysAndOldPlansStillRun(testCase)
        %AVALUEPLANREPLAYSANDOLDPLANSSTILLRUN  A plan with tests about the
        %   trials, replayed from its stored options as a workspace replays
        %   a node, takes the same trials, and on another recording resolves
        %   its windows from that recording's trials; a plan compiled before
        %   there were any (no filters field) runs as it did.
            rts = [312 452 520 380 700 292 640 412];
            EEG = stimulusResponse(rts);
            script = strjoin({ ...
                'bin 1 "a" 112 and next(118) rt within (median, inf) ms', ...
                'bin 2 "b" 112 and next(118) rank(rt) within [0, 50] and log(rt) within [mean - 2 sd, mean + 2 sd]', ...
                'bin 3 "c" 112 and next(118) rt within (0, mean + 2.5 sd] ms'}, newline);
            [first, options] = DefineBins(EEG, struct('script', script));

            [again, ~] = DefineBins(EEG, options);
            testCase.verifyEqual(DefineBinsTest.allMembers(again), DefineBinsTest.allMembers(first));
            slower = stimulusResponse(rts + 400);
            [other, ~] = DefineBins(slower, options);
            testCase.verifyEqual(other.bindesc(1).filters.median, median(rts) + 400, 'AbsTol', 1e-9);
            testCase.verifyEqual(other.bindesc(1).n, 4);

            spec = DefineBinsEngine.parseSpec('bin 1 "x" 112 and next(118) rt within (400,800] ms');
            testCase.verifyEmpty(spec.bins(1).filters, 'A plain window stays in rtWindow.');
            old = DefineBinsTest.tagged(EEG, rmfield(spec.bins, 'filters'));
            testCase.verifyEqual(sort(DefineBinsTest.rtsOf(old, 1)), sort(rts(rts > 400 & rts <= 800)), 'AbsTol', 1e-9);
        end

        function aBoundThatCannotBeComputedKeepsNothingAndSaysWhy(testCase)
        %ABOUNDTHATCANNOTBECOMPUTEDKEEPSNOTHINGANDSAYSWHY  One value has no
        %   standard deviation: no trial, and a note.
            EEG = heartbeats(800);
            [result, ~] = DefineBins(EEG, struct('script', ...
                'bin 1 "x" "heartbeat" and field ibi within (0, median + 2 sd]'));
            testCase.verifyEqual(result.bindesc(1).n, 0);
            testCase.verifySubstring(result.bindesc(1).filters.note, 'standard deviation');
        end

        function valueTestSlipsAreExplained(testCase)
        %VALUETESTSLIPSAREEXPLAINED  A test about the trials under or or not,
        %   a unit on a rank or a logarithm, nested transforms, and windows
        %   no trial could fall in, each get a message that names the fix.
            base = 'bin 1 "x" 112 and ';
            testCase.verifyParseError([base '(next(118) or rank(rt) within [0, 50])'], ...
                'joined to the rest with and');
            testCase.verifyParseError([base 'next(118) and not rank(rt) within [0, 50]'], ...
                'rank(rt) within (50, 100]');
            testCase.verifyParseError([base 'not field ibi within (median, inf)'], 'not inside');
            testCase.verifyParseError([base 'next(118) rank(rt) within [0, 50] ms'], 'takes no unit');
            testCase.verifyParseError([base 'next(118) log(log(rt)) within (0, 7]'], ...
                'not another log or rank');
            testCase.verifyParseError([base 'next(118) rank(118) within [0, 50]'], ...
                'take rt or field');
            testCase.verifyParseError([base 'next(118) rt within (inf, 500] ms'], 'inf down');
            testCase.verifyParseError([base 'next(118) rt within [median + 1 iqr, median - 1 iqr] ms'], ...
                'other way round');
            testCase.verifyParseError([base 'next(118) rt within (0, p101] ms'], ...
                'mean, median or a percentile');
            testCase.verifyParseError([base 'next(118) rt within (0, median + 2] ms'], ...
                'needs the word sd, iqr or mad');
        end
    end

    methods (Access = private)
        function verifyParseError(testCase, script, fragment)
        %VERIFYPARSEERROR  SCRIPT is refused with a message containing
        %   FRAGMENT.
            EEG = eegWithEvents({'112'}, 100);
            try
                DefineBins(EEG, struct('script', script));
                testCase.verifyFail('Expected DefineBins to refuse the script.');
            catch err
                testCase.verifyEqual(err.identifier, 'Alakazam:DefineBins');
                testCase.verifySubstring(err.message, fragment);
            end
        end

        function EEG = cueStimulusResponse(~)
        %CUESTIMULUSRESPONSE  Cue at -500 ms, stimulus at 0, response at
        %   +700 ms. 250 Hz, so one sample is 4 ms.
            EEG = eegWithEvents({'50', '112', '118'}, [1, 126, 301]);
        end

        function EEG = brainVisionMarkers(~)
        %BRAINVISIONMARKERS  The shapes a BrainVision recording actually
        %   produces, plus one bare numeric code, so the prefix rule is
        %   exercised against both.
            EEG = eegWithEvents({'S21', 'S 25', 'S30', 'R21', 'S99', '25'}, ...
                100:100:600);
        end

        function matched = matchesFor(~, EEG, script)
        %MATCHESFOR  The event types one bin matched, in recording order.
            spec = DefineBinsEngine.parseSpec(script);
            matched = {EEG.event(DefineBinsTest.membersOf(DefineBinsTest.tagged(EEG, spec.bins), 1)).type};
        end

        function events = eventsFor(~, EEG, script)
        %EVENTSFOR  The event indices bin 1 of SCRIPT matched.
            spec = DefineBinsEngine.parseSpec(script);
            events = DefineBinsTest.membersOf(DefineBinsTest.tagged(EEG, spec.bins), 1);
        end

        function rt = rtOf(~, EEG, script)
            spec = DefineBinsEngine.parseSpec(script);
            rt = DefineBinsTest.rtsOf(DefineBinsTest.tagged(EEG, spec.bins), 1);
            if isempty(rt); rt = NaN; end
            rt = rt(1);
        end
    end

    methods (Static)
        % Which events (trials) a bin matched, and their reaction times, are
        % on the events and trials (.bini, .binrt); these read them as the
        % app does, through TransTools.BinMembership.
        function members = membersOf(EEG, b)
            members = TransTools.BinMembership.of(EEG, b);
        end

        function rts = rtsOf(EEG, b)
            [~, rts] = TransTools.BinMembership.of(EEG, b);
        end

        function all = allMembers(EEG)
            all = arrayfun(@(b) {TransTools.BinMembership.of(EEG, b)}, 1:numel(EEG.bindesc));
        end

        function EEG = tagged(EEG, bins)
        %TAGGED  EEG with its events tagged by BINS (evaluateBins) and the
        %   bins' descriptions beside them, as DefineBins leaves it.
            [EEG, bindesc] = DefineBinsEngine.evaluateBins(EEG, bins);
            EEG.bindesc = bindesc;
        end
    end
end

function EEG = eegWithEvents(types, latencies)
%EEGWITHEVENTS  A minimal EEG struct with just .event/.srate -- everything
%   DefineBins needs before an .epoch statement asks it to also cut trial
%   data (see the epochWindowSegmentsTheData test, which adds .data itself).
    EEG = struct();
    EEG.srate = 250;
    EEG.event = struct('type', types, 'latency', num2cell(latencies));
end

function EEG = stimulusResponse(rts)
%STIMULUSRESPONSE  One 112 per reaction time in RTS (ms), each followed by
%   a 118 that much later. At 250 Hz a sample is 4 ms, so every RT here is
%   a whole number of samples; stimuli are 4 s apart, clear of any RT used.
    n = numel(rts);
    stimuli = 100 + (0:n - 1) * 1000;
    responses = stimuli + rts / 4;
    types = repmat({'112', '118'}, 1, n);
    latencies = reshape([stimuli; responses], 1, []);
    EEG = eegWithEvents(types, latencies);
end

function EEG = heartbeats(ibis)
%HEARTBEATS  One "heartbeat" event per interval in IBIS (ms), carrying it
%   as its ibi field, as the Heartbeats plugin writes them. NaN stands for
%   the last beat before a cut, whose interval the plugin leaves NaN.
    n = numel(ibis);
    EEG = eegWithEvents(repmat({'heartbeat'}, 1, n), 100 + (0:n - 1) * 250);
    for i = 1:n
        EEG.event(i).ibi = ibis(i);
    end
end

function EEG = epochFixture()
%EPOCHFIXTURE  Two 112 events and a 122 on 500 samples of 2-channel data,
%   long enough for an 80 ms window at 250 Hz around each.
    EEG = eegWithEvents({'112', '122', '112'}, [100, 200, 300]);
    EEG.data = zeros(2, 500);
    EEG.pnts = 500;
end

function EEG = inBoundsUnmatchedFixture()
%INBOUNDSUNMATCHEDFIXTURE  A real, EEGLAB-checkset-clean dataset (built on
%   eeg_emptyset, not the bare eegWithEvents struct -- eeg_checkset's own
%   pop_editeventvals resort step needs a properly-shaped EEG, not just the
%   handful of fields DefineBins itself reads) for
%   anUnmatchedEventWithAnInBoundsLatencySurvivesARealEegCheckestRoundTrip.
%   1 event (code "999") matches no bin and is deliberately given a small
%   latency (20 samples) that stays well inside this fixture's own
%   EEG.pnts*EEG.trials (20*2 = 40), so it cannot be pruned by
%   eeg_checkset's separate "latency out of bounds" check -- only cutEpochs'
%   own explicit .epoch = 0 sentinel can catch it.
    srate = 250;
    EEG = eeg_emptyset();
    EEG.data = zeros(2, 500);
    EEG.srate = srate; EEG.nbchan = 2;
    EEG.chanlocs = struct('labels', {'Fz', 'Cz'});
    EEG.times = (0:size(EEG.data, 2) - 1) / srate;
    EEG.event = struct('type', {'999', '112', '112'}, ...
        'latency', {20, 100, 300});
end
