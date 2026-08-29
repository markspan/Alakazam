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
%   NOTE: while writing this, DefineBins.m's own header comment (about a
%   single "epoch [...] ms" statement inside the script) turned out to be
%   stale -- the epoch window is actually a separate options.epoch struct
%   (populated from the dialog's own start/stop fields, or passed directly
%   in "script mode"), not parsed from the script text at all; the
%   tokenizer's own keyword list has no "epoch" entry. This file tests the
%   actual current behaviour; the stale doc comment is a separate,
%   unrelated cleanup.
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
        %   events whose type is 112, tagging each with .bini and
        %   recording their (original) indices on bindesc.
            EEG = eegWithEvents({'112', '122', '112'}, [100, 200, 300]);
            opts = struct('script', 'bin 1 "Targets" 112');

            [result, ~] = DefineBins(EEG, opts);

            testCase.verifyEqual(result.bindesc(1).events, [1, 3]);
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

            testCase.verifyEqual(result.bindesc(1).events, 1);
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

            testCase.verifyEqual(result.bindesc(1).events, 1);
            testCase.verifyEqual(result.bindesc(1).rt, 300, 'AbsTol', 1e-9); % (175-100)/250*1000 ms
        end

        function adjacentRequiresTheImmediatelyFollowingEvent(testCase)
        %ADJACENTREQUIRESTHEIMMEDIATELYFOLLOWINGEVENT  112 and
        %   adjacent(118) matches only when the VERY NEXT event (in
        %   latency order) is 118, not just any later one.
            EEG = eegWithEvents({'112', '118', '112', '122', '118'}, [100, 150, 300, 350, 400]);
            opts = struct('script', 'bin 1 "X" 112 and adjacent(118)');

            [result, ~] = DefineBins(EEG, opts);

            testCase.verifyEqual(result.bindesc(1).events, 1); % the first 112 only
        end

        function combinationBinRecordsItsRecipeNotItsOwnEvents(testCase)
        %COMBINATIONBINRECORDSITSRECIPENOTITSOWNEVENTS  bin 3 = bin 1 -
        %   bin 2 has no event predicate of its own: DefineBins records
        %   the (coeff, bin) recipe on .combo and leaves .events empty
        %   (Average computes the actual difference later).
            EEG = eegWithEvents({'112', '122'}, [100, 200]);
            opts = struct('script', [ ...
                'bin 1 "A" 112' newline ...
                'bin 2 "B" 122' newline ...
                'bin 3 "A-B" = bin 1 - bin 2']);

            [result, ~] = DefineBins(EEG, opts);

            testCase.verifyEmpty(result.bindesc(3).events);
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
    end

    methods (Access = private)
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
            [~, bindesc] = DefineBinsEngine.evaluateBins(EEG, spec.bins);
            matched = {EEG.event(bindesc(1).events).type};
        end

        function rt = rtOf(~, EEG, script)
            spec = DefineBinsEngine.parseSpec(script);
            [~, bindesc] = DefineBinsEngine.evaluateBins(EEG, spec.bins);
            rt = bindesc(1).rt;
            if isempty(rt); rt = NaN; end
            rt = rt(1);
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
