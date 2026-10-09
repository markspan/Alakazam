classdef ErplabBdfImportTest < matlab.unittest.TestCase
%ERPLABBDFIMPORTTEST  The ERPLAB BDF importer, against the grammar ERPLAB
%   itself implements.
%
%   The constructs exercised here are taken from ERPLAB's own
%   bdf2struct.m -- its expp{} table enumerates all 23 recognised
%   combinations of time condition, flag test and flag write -- and from
%   neobinlister2.m, which is where the matching SEMANTICS live. Guessing at
%   the syntax instead produced a test suite that agreed with a translation
%   nobody had checked against the source.
%
%   Two properties matter more than any individual mapping.
%
%   NOTHING TRANSLATES SILENTLY WRONG. Before this file existed, "~201"
%   became the quoted marker "~201", and the code range "21-30" became the
%   marker "21-30". Both parse, both are accepted by DefineBins, and both
%   match no event that has ever existed -- so the bin came out empty and
%   nothing said why. A construct must either translate correctly or warn.
%
%   EVERY TRANSLATION PARSES. The importer writes DefineBins source, so the
%   real check is handing its output to the DefineBins parser rather than
%   comparing strings.
%
%   Run with: runtests('tests/ErplabBdfImportTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'IO')));
            % The parent of @DefineBinsEngine, not the class folder itself:
            % MATLAB resolves a class folder from the directory above it.
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations', 'DefineBins')));
        end
    end

    methods (Test)
        % ---- positional semantics ---------------------------------------
        function bracketsBecomeOrdinalOffsets(testCase)
        %BRACKETSBECOMEORDINALOFFSETS  A BINLISTER sequencer is positional:
        %   each bracket is the ADJACENT event in the chain. DefineBins'
        %   next()/prev() scan until they find a match, so a bare next(201)
        %   is looser than the BDF asked for. The ordinal window restores it.
            script = ErplabBdfImportTest.translate('.{111}{201}{301}');

            testCase.verifySubstring(script, 'next(201) within [1,1] events');
            testCase.verifySubstring(script, 'next(301) within [2,2] events');
        end

        function precedingBracketsCountBackwards(testCase)
            script = ErplabBdfImportTest.translate('{5}.{111}');

            testCase.verifySubstring(script, 'prev(5) within [-1,-1] events');
        end

        function anExplicitTimeWindowReplacesTheOrdinalOne(testCase)
        %ANEXPLICITTIMEWINDOWREPLACESTHEORDINALONE  The millisecond range is
        %   what the BDF author actually constrained, and DefineBins allows
        %   one window per relation.
            script = ErplabBdfImportTest.translate('.{111}{t<200-800>201}');

            testCase.verifySubstring(script, 'next(201) within [200,800] ms');
            testCase.verifyEmpty(strfind(script, 'events')); %#ok<STREMP>
        end

        % ---- negation ----------------------------------------------------
        function negatedCodesBecomeNot(testCase)
        %NEGATEDCODESBECOMENOT  The regression this file was written for.
        %   "~201" used to become the quoted marker "~201", which matches
        %   nothing, with no warning.
            script = ErplabBdfImportTest.translate('.{111}{~201}');

            testCase.verifySubstring(script, 'not next(201)');
            testCase.verifyEmpty(strfind(script, '"~201"'), ...
                'The negation is being emitted as a literal marker again.'); %#ok<STREMP>
        end

        function negationIsAllOrNothingPerBracket(testCase)
        %NEGATIONISALLORNOTHINGPERBRACKET  neobinlister2 counts the
        %   non-negated ("desired") codes and only mismatches when there are
        %   none. A bracket mixing the two is therefore a positive test over
        %   all of them, which is surprising enough to warn about.
            [script, warnings] = ErplabBdfImportTest.translate('.{111}{201;~202}');

            testCase.verifySubstring(script, 'next({201 202})');
            testCase.verifyEmpty(strfind(script, 'not next'), ...
                'A mixed bracket must not be treated as negated.'); %#ok<STREMP>
            testCase.verifyTrue(any(contains(warnings, 'mixes negated and plain')));
        end

        function negationWithATimeWindowWarnsAboutTheDifference(testCase)
        %NEGATIONWITHATIMEWINDOWWARNSABOUTTHEDIFFERENCE  The one case where
        %   the two languages genuinely disagree: BINLISTER asks whether the
        %   event at this position is not the code; DefineBins asks whether
        %   the code occurs anywhere in the window.
            [~, warnings] = ErplabBdfImportTest.translate('.{111}{t<200-800>~201}');

            testCase.verifyTrue(any(contains(warnings, 'anywhere in the window')));
        end

        % ---- code sets ---------------------------------------------------
        function rangesCarryOverAsRanges(testCase)
        %RANGESCARRYOVERASRANGES  DefineBins has range syntax of its own and
        %   it means the same thing, so an imported script reads like the
        %   descriptor it came from rather than listing ten codes where the
        %   BDF wrote two. (It was enumerated until the language gained
        %   ranges; before that it became the literal marker "21-30", which
        %   matched nothing at all.)
            script = ErplabBdfImportTest.translate('.{111}{21-30}');

            testCase.verifySubstring(script, 'next(21-30)');
            testCase.verifyEmpty(strfind(script, '"21-30"')); %#ok<STREMP>
        end

        function negatedRangesAreBoth(testCase)
            script = ErplabBdfImportTest.translate('.{111}{~21-30}');

            testCase.verifySubstring(script, 'not next(21-30)');
        end

        function aRangeMixesWithPlainCodesInOneSet(testCase)
            script = ErplabBdfImportTest.translate('.{111}{21-23;40}');

            testCase.verifySubstring(script, 'next({21-23 40})');
        end

        function aBackwardsRangeIsCarriedOverAndFlagged(testCase)
        %ABACKWARDSRANGEISCARRIEDOVERANDFLAGGED  Guessing at the intent of a
        %   malformed descriptor is worse than saying so. It is emitted as
        %   written, warned about here, and refused by the DefineBins parser
        %   as well, so the script cannot be run until it is corrected.
            [script, warnings] = ErplabBdfImportTest.translate('.{111}{30-21}');

            testCase.verifySubstring(script, 'next(30-21)');
            testCase.verifyTrue(any(contains(warnings, 'runs backwards')));
            testCase.verifyError(@() DefineBinsEngine.parseSpec(script), ...
                'Alakazam:DefineBins');
        end

        function bothSeparatorsWork(testCase)
        %BOTHSEPARATORSWORK  ERPLAB accepts ';' and ',' between alternatives.
            semi = ErplabBdfImportTest.translate('.{111;112}{201}');
            comma = ErplabBdfImportTest.translate('.{111,112}{201}');

            testCase.verifySubstring(semi, '{111 112}');
            testCase.verifySubstring(comma, '{111 112}');
        end

        % ---- constructs with no equivalent -------------------------------
        function everyFlagConstructWarns(testCase)
        %EVERYFLAGCONSTRUCTWARNS  Flag tests (f/fa/fb) and flag writes
        %   (w/wa/wb) have no DefineBins equivalent: it matches on event type
        %   and timing, has no access to event flags, and has no mutable
        %   event state for a write to live in. Each must say so.
            for descriptor = {'.{111}{201:f<12>}', '.{111}{201:fa<3>}', ...
                    '.{111}{201:fb<9>}', '.{111}{201:w<5>}', ...
                    '.{111}{201:wa<2>}', '.{111}{201:wb<7>}'}
                [~, warnings] = ErplabBdfImportTest.translate(descriptor{1});
                testCase.verifyTrue(any(contains(warnings, 'no DefineBins equivalent')), ...
                    sprintf('%s translated without a warning.', descriptor{1}));
            end
        end

        function namedReactionTimeWarnsAndDoesNotCorruptTiming(testCase)
        %NAMEDREACTIONTIMEWARNSANDDOESNOTCORRUPTTIMING  ':rt<"name">'
        %   contains a literal 't<', so it used to be captured by the
        %   time-flag regex and reported as an unparseable time condition.
        %   It is stripped first now.
            [script, warnings] = ErplabBdfImportTest.translate('.{111}{201:rt<"targetRT">}');

            testCase.verifyTrue(any(contains(warnings, 'named reaction time')));
            testCase.verifyFalse(any(contains(warnings, 'could not parse the time condition')), ...
                'The rt<> label is being mistaken for a time condition again.');
            testCase.verifySubstring(script, 'next(201)');
        end

        function theWildcardSurvives(testCase)
        %THEWILDCARDSURVIVES  ERPLAB's '*' means any code; DefineBins' '*'
        %   inside quotes means any run of characters, which matches every
        %   canonicalised event type. The two coincide.
            script = ErplabBdfImportTest.translate('.{111}{*}');

            testCase.verifySubstring(script, 'next("*")');
        end

        % ---- the property that covers the rest ----------------------------
        function everyTranslationParses(testCase)
        %EVERYTRANSLATIONPARSES  The importer emits DefineBins source, so
        %   the real check is the DefineBins parser, not a string compare.
            descriptors = { ...
                '.{111}{201}', '{5}.{111}', '.{111}{201}{301}', ...
                '.{111;112}{201}', '.{111,112}{201}', '.{111}{~201}', ...
                '.{111}{t<200-800>~201}', '.{111}{21-30}', '.{111}{~21-30}', ...
                '.{111}{*}', '.{111}{t<200-800>201}', '.{111}{201:f<12>}', ...
                '.{111}{201:fa<3>}', '.{111}{201:w<5>}', ...
                '.{111}{201:rt<"targetRT">}', '.{111}{t<200-800>201:f<1>:w<2>}', ...
                '.{111}{201;~202}'};

            for d = descriptors
                script = ErplabBdfImportTest.translate(d{1});
                testCase.verifyWarningFree(@() DefineBinsEngine.parseSpec(script), ...
                    sprintf('Translation of "%s" does not parse: %s', d{1}, script));
            end
        end

        function nothingIsDroppedWithoutSaying(testCase)
        %NOTHINGISDROPPEDWITHOUTSAYING  Every warning also appears in the
        %   script as a "% WARNING:" comment, so a user who never looks
        %   at the return value still sees it.
            [script, warnings] = ErplabBdfImportTest.translate('.{111}{201:f<12>}');

            testCase.assertNotEmpty(warnings);
            testCase.verifySubstring(script, '% WARNING:');
        end
    end

    methods (Test, TestTags = {'External'})
        function itBinsAsErplabsOwnBinlisterDoes(testCase)
        %ITBINSASERPLABSOWNBINLISTERDOES  The import, run through DefineBins,
        %   puts the same events in the same bins as ERPLAB's pop_binlister
        %   on the same event list. Four trials, chosen where the two readings
        %   of a bracket part: a response with another event between it and
        %   the target (a timed bracket takes it, as BINLISTER does), and a
        %   preceding code that is not the adjacent event (an untimed bracket
        %   is the adjacent event only). On Luck's five bin files the bins
        %   were identical too (2026-10-09).
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Transformations')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}, 'IncludeSubfolders', true));
            end
            try
                EEGLabEnvironment.ensure();
            catch
            end
            if isempty(which('pop_binlister')) && ~isempty(which('eeglab'))
                erplab = dir(fullfile(fileparts(which('eeglab')), 'plugins', 'erplab*'));
                if ~isempty(erplab)
                    testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                        fullfile(erplab(end).folder, erplab(end).name), 'IncludeSubfolders', true));
                end
            end
            testCase.assumeFalse(isempty(which('pop_binlister')), 'ERPLAB is not installed.');

            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            bdf = fullfile(folder, 'gap.txt');
            fid = fopen(bdf, 'w');
            fprintf(fid, 'bin 1\nTarget answered\n.{211}{t<200-1500>201}\n\nbin 2\nTarget after a 99\n{99}.{211}\n');
            fclose(fid);
            codes = {211 201  211 99 201  99 211 201  99 5 211};
            ms    = [0   400  3000 3100 3400  6000 6050 6450  9000 9020 9050];
            EEG = ErplabBdfImportTest.eventsOnly(codes, ms, 250); %#ok<NASGU> read in evalc

            [~, E] = evalc(['pop_creabasiceventlist(EEG, ''AlphanumericCleaning'', ''on'', ' ...
                '''BoundaryNumeric'', {-99}, ''BoundaryString'', {''boundary''}, ''Warning'', ''off'')']); %#ok<ASGLU> read in evalc
            [~, E] = evalc(['pop_binlister(E, ''BDF'', bdf, ''IndexEL'', 1, ''SendEL2'', ''EEG'', ' ...
                '''Voutput'', ''EEG'', ''Warning'', ''off'', ''UpdateEEG'', ''on'')']);
            script = erplabBdfToBinScript(fileread(bdf)); %#ok<NASGU> read in evalc
            [~, A] = evalc('DefineBins(EEG, struct(''script'', script, ''tagsOnly'', true))');

            targets = find(cellfun(@(c) isequal(c, 211), codes));
            for b = 1:2
                erplab = arrayfun(@(k) any(E.EVENTLIST.eventinfo(k).bini == b), targets);
                alakazam = arrayfun(@(k) any(A.event(k).bini == b), targets);
                testCase.verifyEqual(alakazam, erplab, sprintf('Bin %d, trials 1 to 4.', b));
            end
            testCase.verifyEqual(double(arrayfun(@(k) any(A.event(k).bini == 1), targets)), [1 1 1 0], ...
                'The trials the case was built to tell apart.');
        end
    end

    methods (Static)
        function EEG = eventsOnly(codes, ms, srate)
        %EVENTSONLY  A flat continuous recording carrying CODES at MS.
            EEG = eeg_emptyset();
            EEG.srate = srate;
            EEG.pnts = round((max(ms) / 1000 + 2) * srate);
            EEG.nbchan = 1;
            EEG.trials = 1;
            EEG.data = zeros(1, EEG.pnts);
            EEG.xmin = 0;
            EEG.xmax = (EEG.pnts - 1) / srate;
            EEG.chanlocs = struct('labels', 'Cz');
            EEG.event = struct('type', codes, 'latency', num2cell(round(ms / 1000 * srate) + 1));
            evalc('EEG = eeg_checkset(EEG);');
            EEG.DataFormat = 'CONTINUOUS';
            EEG.DataType = 'TIMEDOMAIN';
        end

        function [script, warnings] = translate(descriptor)
        %TRANSLATE  One descriptor as a complete one-bin BDF.
            bdf = sprintf('bin 1\nLabel\n%s', descriptor);
            [script, warnings] = erplabBdfToBinScript(bdf);
        end
    end
end
