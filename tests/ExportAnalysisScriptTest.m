classdef ExportAnalysisScriptTest < matlab.unittest.TestCase
%EXPORTANALYSISSCRIPTTEST  Unit tests for src/IO/matlabLiteral.m and
%   src/IO/exportAnalysisScript.m.
%
%   The literal writer is the part that has to be exactly right: a stored
%   option written back imprecisely produces a script that runs, looks
%   plausible, and analyses something subtly different. Every value type is
%   therefore checked by ROUND TRIP -- eval(matlabLiteral(x)) must isequaln
%   x -- rather than by asserting the text, which would only pin the
%   formatting.
%
%   The generator itself is checked for the properties that make the output
%   usable: it is valid MATLAB, every variable is assigned before it is
%   read, and forks in the tree start from the right dataset.
%
%   Run with: runtests('tests/ExportAnalysisScriptTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'IO')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Support')));
        end
    end

    methods (Test)
        % ---- matlabLiteral round trips ---------------------------------
        function scalarsRoundTrip(testCase)
            testCase.verifyRoundTrip(42);
            testCase.verifyRoundTrip(-3);
            testCase.verifyRoundTrip(0.1);
            testCase.verifyRoundTrip(pi);
            testCase.verifyRoundTrip(1e-12);
            testCase.verifyRoundTrip(NaN);
            testCase.verifyRoundTrip(Inf);
            testCase.verifyRoundTrip(-Inf);
        end

        function ordinaryDecimalsPrintAsThemselves(testCase)
        %ORDINARYDECIMALSPRINTASTHEMSELVES  0.4 and 0.40000000000000002 are
        %   the same double, so printing the long form is not more faithful,
        %   only less readable, and it reads as a rounding error in a file
        %   whose purpose is being read. Reported from a real export of
        %   AutoGEDAI's own LowCut.
            testCase.verifyEqual(matlabLiteral(0.4), '0.4');
            testCase.verifyEqual(matlabLiteral(0.9), '0.9');
            testCase.verifyEqual(matlabLiteral(0.1), '0.1');
            testCase.verifyEqual(matlabLiteral(-0.05), '-0.05');
            testCase.verifyEqual(matlabLiteral(1.5), '1.5');
            testCase.verifyEqual(matlabLiteral(pi), '3.141592653589793');
        end

        function aShortenedNumberStillReadsBackExactly(testCase)
        %ASHORTENEDNUMBERSTILLREADSBACKEXACTLY  Shortening is only safe
        %   because every candidate is checked to round-trip bit for bit.
            values = [0.4, 0.9, 0.1, pi, 1/3, 0.30000000000000004, ...
                1e-12, 6.022e23, -2.5e-8, realmin, realmax];
            for v = values
                restored = eval(matlabLiteral(v)); %#ok<EVLDOT>
                testCase.verifyEqual(restored, v, 'AbsTol', 0, ...
                    sprintf('%.17g did not round-trip.', v));
            end
        end

        function nonIntegerValuesKeepFullPrecision(testCase)
        %NONINTEGERVALUESKEEPFULLPRECISION  A filter cutoff or threshold
        %   rounded on the way out would make the script analyse something
        %   marginally different from the run it claims to reproduce.
            value = 0.30000000000000004;
            restored = eval(matlabLiteral(value)); %#ok<EVLDOT>
            testCase.verifyEqual(restored, value, 'AbsTol', 0);
        end

        function textRoundTrips(testCase)
            testCase.verifyRoundTrip('Absolute threshold');
            testCase.verifyRoundTrip('');
            testCase.verifyRoundTrip('it''s quoted');
            testCase.verifyRoundTrip("a string");
            testCase.verifyRoundTrip("with ""quotes""");
        end

        function logicalsAndVectorsRoundTrip(testCase)
            testCase.verifyRoundTrip(true);
            testCase.verifyRoundTrip(false);
            testCase.verifyRoundTrip([true false true]);
            testCase.verifyRoundTrip([1 2 3]);
            testCase.verifyRoundTrip([1 2; 3 4]);
            testCase.verifyRoundTrip([]);
            testCase.verifyRoundTrip(int32(7));
        end

        function cellsRoundTrip(testCase)
            testCase.verifyRoundTrip({});
            testCase.verifyRoundTrip({'Absolute threshold'});
            testCase.verifyRoundTrip({'a', 'b', 'c'});
            testCase.verifyRoundTrip({1, 'two', [3 4]});
        end

        function structsRoundTrip(testCase)
            testCase.verifyRoundTrip(struct());
            testCase.verifyRoundTrip(struct('Minimum', -100, 'Maximum', 100));
            testCase.verifyRoundTrip(struct('a', struct('b', struct('c', 1))));
        end

        function aCellValuedFieldSurvivesAsACell(testCase)
        %ACELLVALUEDFIELDSURVIVESASACELL  The classic struct() trap: a bare
        %   cell argument builds a struct ARRAY, one element per cell, so
        %   struct('Method', {'a','b'}) is 1x2 rather than one struct whose
        %   Method is a cell. ArtefactDetect's own Method is exactly this
        %   shape, so getting it wrong would silently change which detectors
        %   a generated script ran.
            value = struct('Method', {{'Absolute threshold', 'Step function'}}, ...
                'Minimum', -100);
            restored = testCase.verifyRoundTrip(value);
            testCase.verifySize(restored, [1 1]);
            testCase.verifyClass(restored.Method, 'cell');
            testCase.verifyEqual(numel(restored.Method), 2);
        end

        function anEmptyCellFieldSurvives(testCase)
        %ANEMPTYCELLFIELDSURVIVES  The shape that turned out to mean "no
        %   detectors ticked" (see ArtefactDetect): it must not come back
        %   as a missing field or a 0x0 struct array.
            value = struct('Method', {{}}, 'Minimum', -100);
            restored = testCase.verifyRoundTrip(value);
            testCase.verifyClass(restored.Method, 'cell');
            testCase.verifyEmpty(restored.Method);
        end

        function structArraysRoundTrip(testCase)
            value = struct('label', {'Rare', 'Frequent'}, 'index', {1, 2});
            restored = testCase.verifyRoundTrip(value);
            testCase.verifySize(restored, [1 2]);
        end

        function aRealisticOptionsStructRoundTrips(testCase)
        %AREALISTICOPTIONSSTRUCTROUNDTRIPS  Shaped like a Measure window,
        %   the most involved options struct the app stores.
            value = struct('windows', {{struct('label', 'N400', 'start', 300, ...
                'stop', 500, 'measure', 'Mean Amplitude', 'polarity', 'Negative', ...
                'width', [], 'localPoints', 0, 'fraction', [], 'areaMode', 'signed', ...
                'baseline', [], 'refChannel', '', 'channels', '')}}, ...
                'derivations', 'let LRP = C3 - C4');
            testCase.verifyRoundTrip(value);
        end

        function multiLineTextRoundTrips(testCase)
        %MULTILINETEXTROUNDTRIPS  A MATLAB single-quoted string cannot span
        %   lines, so multi-line text written as a plain literal is a syntax
        %   error. DefineBins stores its entire bin script as one multi-line
        %   char, which is precisely what a generated script must carry, and
        %   a real exported chain is where this was found: the unit fixtures
        %   here were all single-line and missed it.
            testCase.verifyRoundTrip(sprintf('line one\nline two\nline three'));
            testCase.verifyRoundTrip(sprintf('with\ttabs\tin it'));
            testCase.verifyRoundTrip(sprintf('trailing newline\n'));
        end

        function aBinScriptRoundTripsExactly(testCase)
        %ABINSCRIPTROUNDTRIPSEXACTLY  Shaped like the real thing: comment
        %   lines starting with %, a quoted wildcard, and brackets. The
        %   percent signs are the trap, since the escaped form goes through
        %   sprintf, which would otherwise read them as conversions and
        %   silently drop them.
            script = sprintf(['let rare = {11,22,33,44,55}\n' ...
                'let frequent = "??" not rare\n' ...
                '%%\n' ...
                '%% 100%% of trials, a \\ backslash, and an ''apostrophe''\n' ...
                'bin 1 "Rare" rare and next(201) within [200,1000] ms\n']);

            restored = testCase.verifyRoundTrip(script);

            testCase.verifyEqual(restored, script);
            testCase.verifySubstring(restored, '100% of trials');
            testCase.verifySubstring(restored, '\ backslash');
        end

        function aLongCellKeepsItsShapeNotItsRows(testCase)
        %ALONGCELLKEEPSITSSHAPENOTITSROWS  Long values are emitted across
        %   several lines, and inside {} or [] a bare newline is a ROW
        %   separator: without a continuation the value evaluates cleanly
        %   but comes back Nx1 instead of 1xN. Found by the realistic
        %   Measure struct below, which failed outright inside struct(...)
        %   where the same omission is a syntax error rather than a silent
        %   reshape.
            value = arrayfun(@(k) sprintf('a channel label number %d', k), ...
                1:12, 'UniformOutput', false);
            restored = testCase.verifyRoundTrip(value);
            testCase.verifySize(restored, [1 12]);
        end

        function aLongNumericVectorKeepsItsShape(testCase)
            value = (1:40) + 0.5;
            restored = testCase.verifyRoundTrip(value);
            testCase.verifySize(restored, [1 40]);
        end

        function aLongStructArrayKeepsItsShape(testCase)
            value = struct('label', arrayfun(@(k) sprintf('bin %d', k), 1:8, ...
                'UniformOutput', false), 'index', num2cell(1:8));
            restored = testCase.verifyRoundTrip(value);
            testCase.verifySize(restored, [1 8]);
        end

        function anUnsupportedClassIsRefusedRatherThanMangled(testCase)
            testCase.verifyError(@() matlabLiteral(containers.Map()), ...
                'Alakazam:matlabLiteral');
        end

        % ---- the generated script --------------------------------------
        function refusesAnEmptyWorkspace(testCase)
            testCase.verifyError(@() exportAnalysisScript( ...
                struct('name', {}, 'rawFile', {}, 'loader', {}, 'steps', {}), []), ...
                'Alakazam:exportAnalysisScript');
        end

        function theOutputIsAScriptNotAFunction(testCase)
        %THEOUTPUTISASCRIPTNOTAFUNCTION  A script leaves its variables in
        %   the workspace, so an average or a measurement can be inspected
        %   after the run and any section can be re-run on its own.
            code = exportAnalysisScript(testCase.twoSubjects(), testCase.oneGrandAverage(), struct());
            lines = strsplit(code, newline);

            firstCode = lines(~cellfun(@(l) isempty(strtrim(l)) || startsWith(strtrim(l), '%'), lines));
            testCase.verifyFalse(startsWith(strtrim(firstCode{1}), 'function'), ...
                'The file must not open with a function declaration.');
            testCase.verifyFalse(startsWith(code, 'function'));

            % Body code sits at column 0, as a script's own code does.
            testCase.verifySubstring(code, sprintf('\nscriptDir = fileparts'));
            testCase.verifySubstring(code, sprintf('\nfor r = 1:numel(recordings)'));
        end

        function localFunctionsComeAfterAllExecutableCode(testCase)
        %LOCALFUNCTIONSCOMEAFTERALLEXECUTABLECODE  MATLAB allows local
        %   functions in a script only at the very end, so anything emitted
        %   after them would not run.
            code = exportAnalysisScript(testCase.twoSubjects(), testCase.oneGrandAverage(), struct());
            lines = strsplit(code, newline);

            isFunction = cellfun(@(l) startsWith(strtrim(l), 'function '), lines);
            firstFunction = find(isFunction, 1);
            testCase.assertNotEmpty(firstFunction, 'Expected the emitted helpers.');

            after = lines(firstFunction:end);
            stray = after(cellfun(@(l) ~isempty(regexp(l, '^\S', 'once')) ...
                && ~startsWith(strtrim(l), '%') && ~startsWith(strtrim(l), 'function ') ...
                && ~strcmp(strtrim(l), 'end'), after));
            testCase.verifyEmpty(stray, 'No executable code may follow the local functions.');
        end

        function theGeneratedScriptIsValidMatlab(testCase)
        %THEGENERATEDSCRIPTISVALIDMATLAB  Parsed for real, not eyeballed:
        %   a script that does not compile is the one failure mode that
        %   makes the whole feature worthless.
            code = exportAnalysisScript(testCase.twoSubjects(), testCase.oneGrandAverage(), ...
                struct('rawDirectory', 'C:\raw', 'outputDirectory', 'C:\out'));

            file = testCase.writeScript(code);
            errors = testCase.parseErrors(file);
            testCase.verifyEmpty(errors, sprintf('Generated script does not parse:\n%s', errors));
        end

        function everyVariableIsAssignedBeforeItIsUsed(testCase)
        %EVERYVARIABLEISASSIGNEDBEFOREITISUSED  A fork in the tree reads its
        %   parent's variable, so an ordering mistake would produce a script
        %   that parses but fails at run time on an undefined name.
            subjects = testCase.forkedSubject();
            code = exportAnalysisScript(subjects, [], struct());

            % Comment lines are excluded: the Setup section documents the
            % raw readers with example calls, and matching those would
            % report rawDir as an unassigned variable.
            body = strjoin(testCase.executableLines(code), newline);

            % A name counts as available if it is assigned, is a for-loop
            % variable, or is a parameter of one of the emitted helper
            % functions. Assignment alone is not enough: EEG arrives via
            % "EEG = loaded.EEG" and filesFor's own allFiles is a parameter,
            % and an earlier version of this check reported both as bugs.
            % (?:^|;) so a second statement on the same line counts too:
            % the load is written as "loaded = load(...); EEG = loaded.EEG;",
            % and a line-anchored pattern sees only the first assignment.
            assigned = regexp(body, '(?:^|;)\s*(\w+)\s*=(?!=)', 'tokens', 'lineanchors');
            loopVars = regexp(body, 'for\s+(\w+)\s*=', 'tokens');
            params   = regexp(body, '^function[^(]*\(([^)]*)\)', 'tokens', 'lineanchors');
            used     = regexp(body, '= \w+\((\w+),', 'tokens', 'lineanchors');

            available = [cellfun(@(c) c{1}, assigned, 'UniformOutput', false), ...
                         cellfun(@(c) c{1}, loopVars, 'UniformOutput', false)];
            for p = 1:numel(params)
                pieces = strtrim(strsplit(params{p}{1}, ','));
                available = [available, pieces(~cellfun(@isempty, pieces))]; %#ok<AGROW>
            end
            used = cellfun(@(c) c{1}, used, 'UniformOutput', false);
            assigned = available;

            testCase.verifyNotEmpty(used, 'Expected the fork to read a parent variable.');
            for i = 1:numel(used)
                testCase.verifyTrue(any(strcmp(assigned, used{i})), ...
                    sprintf('"%s" is used but never assigned.', used{i}));
            end
        end

        function aForkStartsFromItsOwnParent(testCase)
        %AFORKSTARTSFROMITSOWNPARENT  Two steps hanging off the same node
        %   must both take that node as input, not chain off each other.
            code = exportAnalysisScript(testCase.forkedSubject(), [], struct());

            testCase.verifySubstring(code, '= Average(v_Baseline,');
            testCase.verifySubstring(code, '= Measure(v_Baseline,');
        end

        function repeatedTransformsGetDistinctVariables(testCase)
            steps = struct( ...
                'transformId', {'Filter', 'Filter'}, ...
                'params', {struct('Low', 0.1), struct('High', 30)}, ...
                'parent', {-1, 1});
            subjects = struct('name', 'sub01', 'rawFile', 'sub01.set', ...
                'loader', 'set', 'steps', steps);

            code = exportAnalysisScript(subjects, [], struct());

            testCase.verifySubstring(code, 'v_Filter =');
            testCase.verifySubstring(code, 'v_Filter_2 =');
            testCase.verifySubstring(code, 'v_Filter_2 = Filter(v_Filter,');
        end

        function everyRecordingIsReadFromTheCache(testCase)
        %EVERYRECORDINGISREADFROMTHECACHE  The cache holds each recording as
        %   it stood just after import: smaller and faster than re-reading
        %   the original, needing no format reader, and always present for
        %   anything the workspace has processed.
            for loader = {'set', 'bva', 'mat', 'erp'}
                subjects = struct('name', 'sub', 'rawFile', ['sub.' loader{1}], ...
                    'cacheFile', 'sub.mat', 'loader', loader{1}, 'steps', testCase.oneStep());
                code = exportAnalysisScript(subjects, [], struct());
                testCase.verifySubstring(code, 'load(fullfile(cacheDir, ''sub.mat''), ''EEG'')');
                % Comment lines are excluded deliberately: the Setup section
                % documents the raw readers on purpose, as the way to
                % repoint the script away from the cache. What must not
                % appear is an executable call to one.
                testCase.verifyEmpty(testCase.executableLinesMatching(code, 'pop_load'), ...
                    'No executable line should call a raw-format reader.');
            end
        end

        function theRawReadersAreDocumentedForRepointing(testCase)
        %THERAWREADERSAREDOCUMENTEDFORREPOINTING  Reading from the cache is
        %   the fast path, but a script may have to run where the cache is
        %   not available, so the alternative stays written down.
            code = exportAnalysisScript(testCase.twoSubjects(), [], struct());

            testCase.verifySubstring(code, 'pop_loadset');
            testCase.verifySubstring(code, 'pop_loadbv');
            testCase.verifySubstring(code, 'erpsetToAveraged');
        end

        function mixedFormatsStillGroupIntoOneLoop(testCase)
        %MIXEDFORMATSSTILLGROUPINTOONELOOP  The reader no longer matters,
        %   since every recording is read the same way, so a workspace
        %   mixing .set and BrainVision recordings groups on the thing that
        %   actually has to agree: the processing.
            subjects = testCase.twoSubjects();
            subjects(2).loader = 'bva';
            subjects(2).rawFile = 'sub02.vhdr';

            code = exportAnalysisScript(subjects, [], struct());

            testCase.verifySubstring(code, '%% 2 recordings, processed identically');
        end

        function theOptionsStructReachesTheScriptIntact(testCase)
        %THEOPTIONSSTRUCTREACHESTHESCRIPTINTACT  End to end: the params a
        %   step recorded must be recoverable from the emitted line.
            params = struct('Method', {{'Step function'}}, 'Threshold', 75.5);
            subjects = struct('name', 'sub01', 'rawFile', 'sub01.set', 'loader', 'set', ...
                'steps', struct('transformId', 'ArtefactDetect', 'params', params, 'parent', -1));

            code = exportAnalysisScript(subjects, [], struct());

            % The step passes a hoisted variable, so the value to check is
            % that variable's own definition in the Options section.
            testCase.verifySubstring(code, 'ArtefactDetect(EEG, opt_ArtefactDetect)');
            literal = regexp(code, 'opt_ArtefactDetect = (.*?);\n', 'tokens', 'once');
            testCase.assertNotEmpty(literal, 'Could not find the hoisted options definition.');
            restored = eval(literal{1}); %#ok<EVLDOT>
            testCase.verifyEqual(restored, params);
        end

        % ---- looping over identically processed recordings --------------
        function identicalPipelinesBecomeOneLoop(testCase)
        %IDENTICALPIPELINESBECOMEONELOOP  The "Apply to All" case, which is
        %   how a study is normally processed: one loop, not N copies.
            code = exportAnalysisScript(testCase.twoSubjects(), [], struct());

            testCase.verifySubstring(code, '%% 2 recordings, processed identically');
            testCase.verifySubstring(code, 'for r = 1:numel(recordings)');
            testCase.verifySubstring(code, '''sub01.mat'', ''sub02.mat''');
            testCase.verifySubstring(code, 'averages(end + 1) = struct(''name'', thisName');
            testCase.verifyEqual(numel(strfind(code, '= Average(')), 1, ...
                'The shared Average step should be written once, not per subject.');
        end

        function aDifferingSubjectKeepsItsOwnBlock(testCase)
        %ADIFFERINGSUBJECTKEEPSITSOWNBLOCK  A subject whose options differ
        %   must not be folded into the others' loop, which would silently
        %   analyse it with someone else's settings.
            subjects = testCase.twoSubjects();
            subjects(3) = subjects(1);
            subjects(3).name = 'sub03';
            subjects(3).rawFile = 'sub03.set';
            subjects(3).steps(1).params.Start = -250;   % a different baseline

            code = exportAnalysisScript(subjects, [], struct());

            testCase.verifySubstring(code, '%% 2 recordings, processed identically');
            testCase.verifySubstring(code, '%% sub03');
            testCase.verifySubstring(code, '-250');
        end

        function nanOptionsDoNotSplitAnOtherwiseIdenticalGroup(testCase)
        %NANOPTIONSDONOTSPLITANOTHERWISEIDENTICALGROUP  NaN ~= NaN under
        %   isequal, so an unset width or fraction (which several Measure
        %   windows carry) would split a group that is in fact identical.
            subjects = testCase.twoSubjects();
            for s = 1:2
                subjects(s).steps(1).params.width = NaN;
            end

            code = exportAnalysisScript(subjects, [], struct());

            testCase.verifySubstring(code, 'processed identically');
        end

        function aLoopedScriptStillParses(testCase)
            code = exportAnalysisScript(testCase.twoSubjects(), testCase.oneGrandAverage(), struct());
            testCase.verifyEmpty(testCase.parseErrors(testCase.writeScript(code)));
        end

        function aLoopedForkStartsFromItsOwnParent(testCase)
        %ALOOPEDFORKSTARTSFROMITSOWNPARENT  Variable wiring has to survive
        %   the move inside the loop body, where the per-subject prefix is
        %   gone.
            subjects = testCase.forkedSubject();
            subjects(2) = subjects(1);
            subjects(2).name = 'sub02';
            subjects(2).rawFile = 'sub02.set';

            code = exportAnalysisScript(subjects, [], struct());

            testCase.verifySubstring(code, 'for r = 1:numel(recordings)');
            testCase.verifySubstring(code, '= Average(v_Baseline,');
            testCase.verifySubstring(code, '= Measure(v_Baseline,');
            testCase.verifyEmpty(testCase.parseErrors(testCase.writeScript(code)));
        end

        function oneSubjectNeedsNoLoop(testCase)
            code = exportAnalysisScript(testCase.subjectWithBinScript('bin 1 "A" 11'), [], struct());

            testCase.verifyEmpty(strfind(code, 'for r = 1:numel(recordings)')); %#ok<STRIFCND>
            testCase.verifySubstring(code, '%% sub01');
        end

        % ---- hoisted options, error handling, sections ------------------
        function optionsAreHoistedAndSharedByValue(testCase)
        %OPTIONSAREHOISTEDANDSHAREDBYVALUE  The reason to hoist at all: a
        %   threshold is changed in one place. Two steps using the same
        %   value share one variable; the same transformation used twice
        %   with DIFFERENT values gets two.
            steps = struct( ...
                'transformId', {'Filter', 'Filter', 'Baseline'}, ...
                'params', {struct('Low', 0.1), struct('Low', 0.1), struct('Start', -100)}, ...
                'parent', {-1, 1, 2});
            subjects = struct('name', 'sub01', 'rawFile', 'sub01.set', ...
                'loader', 'set', 'steps', steps);

            code = exportAnalysisScript(subjects, [], struct());

            testCase.verifySubstring(code, '%% Options');
            testCase.verifyEqual(numel(strfind(code, 'opt_Filter =')), 1, ...
                'One shared value should be defined once.');
            testCase.verifyEmpty(strfind(code, 'opt_Filter_2')); %#ok<STRIFCND>
            testCase.verifySubstring(code, 'opt_Baseline =');
        end

        function aVariantIsNamedAfterTheRecordingThatUsesIt(testCase)
        %AVARIANTISNAMEDAFTERTHERECORDINGTHATUSESIT  opt_X_2 says nothing
        %   about why it exists; the recording treated differently is the
        %   useful label, and is what the reader is looking for.
            subjects = testCase.twoSubjects();
            subjects(3) = subjects(1);
            subjects(3).name = 'sub03';
            subjects(3).rawFile = 'sub03.set';
            subjects(3).cacheFile = 'sub03.mat';
            subjects(3).steps(1).params.Start = -250;

            code = exportAnalysisScript(subjects, [], struct());

            testCase.verifySubstring(code, 'opt_Baseline_sub03 =');
            testCase.verifySubstring(code, 'Baseline(EEG, opt_Baseline_sub03)');
            testCase.verifyEmpty(strfind(code, 'opt_Baseline_2')); %#ok<STRIFCND>
        end

        function theMajorityVariantKeepsThePlainName(testCase)
        %THEMAJORITYVARIANTKEEPSTHEPLAINNAME  The common settings are the
        %   norm the others depart from, so they stay unqualified.
            subjects = testCase.twoSubjects();
            subjects(3) = subjects(1);
            subjects(3).name = 'sub03';
            subjects(3).cacheFile = 'sub03.mat';
            subjects(3).steps(1).params.Start = -250;

            code = exportAnalysisScript(subjects, [], struct());

            % The point here is the NAME: the common settings stay
            % unqualified. The value may be emitted either inline or in
            % the annotated multi-line form depending on whether this
            % transformation's defaults are readable, so the assertion
            % deliberately does not pin the layout.
            testCase.verifySubstring(code, 'opt_Baseline = struct(');
            testCase.verifyEmpty(strfind(code, 'opt_Baseline_sub01')); %#ok<STRIFCND>
        end

        function namesFallBackToNumbersWhenTheyCannotDistinguish(testCase)
        %NAMESFALLBACKTONUMBERSWHENTHEYCANNOTDISTINGUISH  One recording
        %   filtering twice with different settings has the same name
        %   against both variants, so naming them after it would label two
        %   different things identically.
            steps = struct( ...
                'transformId', {'Filter', 'Filter'}, ...
                'params', {struct('Low', 0.1), struct('High', 30)}, ...
                'parent', {-1, 1});
            subjects = struct('name', 'sub01', 'rawFile', 'sub01.set', ...
                'cacheFile', 'sub01.mat', 'loader', 'set', 'steps', steps);

            code = exportAnalysisScript(subjects, [], struct());

            testCase.verifySubstring(code, 'opt_Filter =');
            testCase.verifySubstring(code, 'opt_Filter_2 =');
            testCase.verifyEmpty(strfind(code, 'opt_Filter_sub01')); %#ok<STRIFCND>
        end

        function everyBlockUsesTheSameVariableNames(testCase)
        %EVERYBLOCKUSESTHESAMEVARIABLENAMES  Blocks run one after another in
        %   a single function, each simply reassigning, so a per-recording
        %   prefix would imply the names mattered across blocks and would
        %   make the same pipeline read differently depending on whether its
        %   recording happened to be grouped.
            subjects = testCase.twoSubjects();
            subjects(3) = subjects(1);
            subjects(3).name = 'sub03';
            subjects(3).cacheFile = 'sub03.mat';
            subjects(3).steps(1).params.Start = -250;

            code = exportAnalysisScript(subjects, [], struct());

            testCase.verifyEqual(numel(strfind(code, 'v_Baseline =')), 2, ...
                'Both the loop and the standalone block should assign v_Baseline.');
            testCase.verifyEmpty(strfind(code, 'sub03_Baseline')); %#ok<STRIFCND>
        end

        function aRecordingNameStartingWithADigitStillMakesValidNames(testCase)
        %ARECORDINGNAMESTARTINGWITHADIGITSTILLMAKESVALIDNAMES  Real
        %   recordings here are called things like 11_P3_corrected, and
        %   11_P3_corrected_Baseline is not a legal identifier.
            subjects = testCase.twoSubjects();
            subjects(3) = subjects(1);
            subjects(3).name = '11_P3_corrected';
            subjects(3).cacheFile = '11_P3_corrected.mat';
            subjects(3).steps(1).params.Start = -250;

            code = exportAnalysisScript(subjects, [], struct());

            testCase.verifyEmpty(testCase.parseErrors(testCase.writeScript(code)));
            testCase.verifySubstring(code, 'opt_Baseline_11_P3_corrected');
        end

        function competingOptionsSayWhichRecordingsUseThem(testCase)
        %COMPETINGOPTIONSSAYWHICHRECORDINGSUSETHEM  opt_X and opt_X_2 do not
        %   themselves say who ran which, and working it out means reading
        %   the whole pipeline. That difference is usually the most
        %   interesting thing in the script, so it is named.
            subjects = testCase.twoSubjects();
            subjects(3) = subjects(1);
            subjects(3).name = 'sub03';
            subjects(3).rawFile = 'sub03.set';
            subjects(3).cacheFile = 'sub03.mat';
            subjects(3).steps(1).params.Start = -250;

            code = exportAnalysisScript(subjects, [], struct());

            testCase.verifySubstring(code, '% used by: sub01, sub02');
            testCase.verifySubstring(code, '% used by: sub03');
        end

        function aSingleVariantIsNotAnnotated(testCase)
        %ASINGLEVARIANTISNOTANNOTATED  With nothing to distinguish it from,
        %   listing every recording against the one option set is noise.
            code = exportAnalysisScript(testCase.twoSubjects(), [], struct());

            testCase.verifyEmpty(strfind(code, '% used by:')); %#ok<STRIFCND>
        end

        function aLongUserListIsAbbreviated(testCase)
            subjects = testCase.twoSubjects();
            for k = 3:10
                subjects(k) = subjects(1);
                subjects(k).name = sprintf('sub%02d', k);
                subjects(k).cacheFile = sprintf('sub%02d.mat', k);
            end
            subjects(10).steps(1).params.Start = -250;   % forces a second variant

            code = exportAnalysisScript(subjects, [], struct());

            testCase.verifySubstring(code, 'and 6 others');
        end

        function theLoadLineSitsInsideItsTryBlock(testCase)
        %THELOADLINESITSINSIDEITSTRYBLOCK  It used to be emitted with its
        %   own four spaces regardless of the block it landed in, so it hung
        %   out of the try it belongs to. Valid MATLAB, but visibly wrong in
        %   a file whose whole purpose is being read.
            code = exportAnalysisScript(testCase.twoSubjects(), [], struct());

            testCase.verifySubstring(code, ...
                sprintf('    try\n        loaded = load(fullfile(cacheDir'));
        end

        function theRecordingsListShowsHowToRunOverTheWholeCache(testCase)
        %THERECORDINGSLISTSHOWSHOWTORUNOVERTHEWHOLECACHE  The explicit list
        %   is the record of what was run; re-running over a whole folder,
        %   usually to take in recordings added since, is the obvious next
        %   thing to want and is written down rather than left to be worked
        %   out.
            code = exportAnalysisScript(testCase.twoSubjects(), [], struct());

            testCase.verifySubstring(code, 'dir(fullfile(cacheDir, ''*.mat''))');
            testCase.verifySubstring(code, 'recordings = {found.name};');
            % Commented, not live: the list above is what reproduces the
            % analysis, and silently widening it would not.
            testCase.verifyEmpty(testCase.executableLinesMatching(code, 'found.name'), ...
                'The dir alternative must be a comment, not executable.');
        end

        % ---- defaults are marked, never omitted -------------------------
        function transformDefaultsReadsTheDeclaredOnes(testCase)
        %TRANSFORMDEFAULTSREADSTHEDECLAREDONES  ArtefactDetect declares its
        %   defaults through TransTools.FieldOr; Baseline through the
        %   stored-struct fallback.
            ad = transformDefaults('ArtefactDetect');
            testCase.verifyEqual(ad.Minimum, -100);
            testCase.verifyEqual(ad.Maximum, 100);
            testCase.verifyEqual(ad.Scope, 'Whole epoch');

            bl = transformDefaults('Baseline');
            testCase.verifyEqual(bl.Start, -100);
            testCase.verifyEqual(bl.Stop, 0);
        end

        function transformDefaultsIsEmptyWhenNoneAreDeclared(testCase)
        %TRANSFORMDEFAULTSISEMPTYWHENNONEAREDECLARED  A normal answer, not a
        %   failure: several transformations have no simple literal
        %   defaults, and those fields go un-annotated.
            testCase.verifyEmpty(fieldnames(transformDefaults('NoSuchTransform')));
        end

        function transformDefaultsRefusesToEvaluateNonLiterals(testCase)
        %TRANSFORMDEFAULTSREFUSESTOEVALUATENONLITERALS  Reading a source
        %   file must not run any of it, so only plainly literal shapes are
        %   accepted. Resample's own default is a function call
        %   (defaultRate(input.srate)) and must be skipped.
            rs = transformDefaults('Resample');
            testCase.verifyFalse(isfield(rs, 'NewRate'));
        end

        function defaultedFieldsAreMarkedNotRemoved(testCase)
            steps = struct('transformId', 'Baseline', ...
                'params', struct('Start', -100, 'Stop', -10), 'parent', -1);
            subjects = struct('name', 'sub01', 'rawFile', 'sub01.set', ...
                'cacheFile', 'sub01.mat', 'loader', 'set', 'steps', steps);

            code = exportAnalysisScript(subjects, [], struct());

            testCase.verifySubstring(code, '''Start'', -100, ...   % default');
            testCase.verifySubstring(code, '''Stop'', -10 ...');
            testCase.verifyEmpty(strfind(code, '''Stop'', -10 ...   % default')); %#ok<STRIFCND>
        end

        function anAnnotatedOptionStructStillEvaluatesToTheSameValue(testCase)
        %ANANNOTATEDOPTIONSTRUCTSTILLEVALUATESTOTHESAMEVALUE  The whole
        %   claim of annotating rather than omitting: the value is
        %   unchanged. Text after "..." is ignored by MATLAB, so the
        %   comments cannot alter what the struct evaluates to.
            params = struct('Method', {{'Absolute threshold'}}, ...
                'Minimum', -100, 'Maximum', 100, 'Threshold', 55);
            steps = struct('transformId', 'ArtefactDetect', 'params', params, 'parent', -1);
            subjects = struct('name', 'sub01', 'rawFile', 'sub01.set', ...
                'cacheFile', 'sub01.mat', 'loader', 'set', 'steps', steps);

            code = exportAnalysisScript(subjects, [], struct());

            testCase.verifySubstring(code, '% default');
            % \n\s*\); rather than a fixed indent: this asserts the VALUE
            % survives annotation, not how it happens to be laid out.
            literal = regexp(code, 'opt_ArtefactDetect = (struct\(.*?\n\s*\));', ...
                'tokens', 'once');
            testCase.assertNotEmpty(literal, 'Could not find the annotated struct.');
            restored = eval(literal{1}); %#ok<EVLDOT>
            testCase.verifyEqual(restored, params);
            testCase.verifyEmpty(testCase.parseErrors(testCase.writeScript(code)));
        end

        function nothingIsAnnotatedWhenNoDefaultsAreKnown(testCase)
            code = exportAnalysisScript(testCase.twoSubjects(), [], struct());
            % twoSubjects uses Baseline with Start -100 (a default) and
            % Stop 0 (also a default), so this checks the opposite case via
            % a transformation with none declared.
            steps = struct('transformId', 'ReRef', ...
                'params', struct('mode', 'Average'), 'parent', -1);
            subjects = struct('name', 'sub01', 'rawFile', 'sub01.set', ...
                'cacheFile', 'sub01.mat', 'loader', 'set', 'steps', steps);

            plain = exportAnalysisScript(subjects, [], struct());

            testCase.verifySubstring(plain, 'opt_ReRef = struct(''mode'', ''Average'');');
            testCase.verifyEmpty(strfind(plain, '% default')); %#ok<STRIFCND>
            testCase.verifyNotEmpty(code);
        end

        function measureResultsAreCollectedNotDiscarded(testCase)
        %MEASURERESULTSARECOLLECTEDNOTDISCARDED  Measure's whole output is
        %   the numbers it puts on the dataset, so a loop that computes them
        %   and lets the next recording overwrite the variable has done the
        %   work and thrown the result away.
            subjects = testCase.twoSubjects();
            for s = 1:2
                subjects(s).steps(3) = struct('transformId', 'Measure', ...
                    'params', struct('windows', {{}}), 'parent', 2);
            end

            code = exportAnalysisScript(subjects, [], struct());

            testCase.verifySubstring(code, 'measures = struct(''name'', {}, ''EEG'', {});');
            testCase.verifySubstring(code, 'measures(end + 1) = struct(''name'', thisName');
            testCase.verifySubstring(code, 'Measured %d recording(s)');
        end

        function anUnusedCollectorIsNotDeclared(testCase)
        %ANUNUSEDCOLLECTORISNOTDECLARED  An always-empty "measures" would
        %   leave the reader wondering what was supposed to fill it.
            code = exportAnalysisScript(testCase.twoSubjects(), [], struct());

            testCase.verifySubstring(code, 'averages = struct(');
            testCase.verifyEmpty(strfind(code, 'measures = struct(')); %#ok<STRIFCND>
        end

        function emptyOptionsAreNotHoisted(testCase)
        %EMPTYOPTIONSARENOTHOISTED  struct() is not worth a name; hoisting
        %   it would add a line that says nothing.
            code = exportAnalysisScript(testCase.twoSubjects(), [], struct());

            testCase.verifySubstring(code, 'Average(v_Baseline, struct())');
            testCase.verifyEmpty(strfind(code, 'opt_Average')); %#ok<STRIFCND>
        end

        function eachRecordingRunsIndependently(testCase)
        %EACHRECORDINGRUNSINDEPENDENTLY  A batch that dies on subject 3 of
        %   40 and discards the other 37 is not a batch.
            code = exportAnalysisScript(testCase.twoSubjects(), [], struct());

            testCase.verifySubstring(code, 'try');
            testCase.verifySubstring(code, 'catch err');
            testCase.verifySubstring(code, 'failures(end + 1)');
            testCase.verifySubstring(code, 'recording(s) failed');
        end

        function requiredTransformationsAreCheckedUpFront(testCase)
            code = exportAnalysisScript(testCase.twoSubjects(), [], struct());

            testCase.verifySubstring(code, 'requireFunctions({''Baseline'', ''Average''})');
            testCase.verifySubstring(code, 'function requireFunctions(names)');
        end

        function theScriptIsSplitIntoEditorSections(testCase)
            code = exportAnalysisScript(testCase.twoSubjects(), testCase.oneGrandAverage(), struct());

            for section = {'%% Setup', '%% Options', '%% Grand averages', '%% Summary'}
                testCase.verifySubstring(code, section{1});
            end
        end

        function namesAreDerivedFromFileNamesWhenTheyMatch(testCase)
        %NAMESAREDERIVEDFROMFILENAMESWHENTHEYMATCH  A display name is almost
        %   always the file stem, so carrying a parallel list of them is
        %   noise that can also fall out of step with the file list.
            code = exportAnalysisScript(testCase.twoSubjects(), [], struct());

            testCase.verifySubstring(code, '[~, thisName] = fileparts(recordings{r})');
            testCase.verifyEmpty(strfind(code, 'names      =')); %#ok<STRIFCND>
        end

        function aNameThatDiffersFromItsFileIsKept(testCase)
            subjects = testCase.twoSubjects();
            subjects(1).name = 'Participant one';
            subjects(2).name = 'Participant two';

            code = exportAnalysisScript(subjects, [], struct());

            testCase.verifySubstring(code, 'names      =');
            testCase.verifySubstring(code, 'Participant one');
            testCase.verifySubstring(code, 'thisName = names{r};');
        end

        function theCallersOwnStructShapesAreAccepted(testCase)
        %THECALLERSOWNSTRUCTSHAPESAREACCEPTED  Builds the subject and grand
        %   average structs the way Alakazam.onExportAnalysisScript does,
        %   field for field, and appends to them the way it does. A field
        %   present on one side only fails here rather than at the moment a
        %   user clicks Export.
            subjects = struct('name', {}, 'rawFile', {}, 'cacheFile', {}, ...
                'loader', {}, 'steps', {});
            subjects(end + 1) = struct('name', 'sub01', 'rawFile', 'sub01.set', ...
                'cacheFile', 'sub01.mat', 'loader', 'set', 'steps', testCase.oneStep());

            gas = testCase.grandAverageStructShape();
            gas(end + 1) = struct('name', 'GA', 'weighted', false, ...
                'sources', {{'a.mat'}}, 'subjects', {{'sub01'}}, 'cell', '');

            code = exportAnalysisScript(subjects, gas, struct( ...
                'rawDirectory', 'C:\raw', 'cacheDirectory', 'C:\cache', ...
                'outputDirectory', 'C:\out'));

            testCase.verifySubstring(code, 'cacheDir = ''C:\cache''');
            testCase.verifyEmpty(testCase.parseErrors(testCase.writeScript(code)));
        end

        function aDesignCellIsNamedInTheScript(testCase)
        %ADESIGNCELLISNAMEDINTHESCRIPT  A grand average built per design
        %   cell knows what it represents; the script should say so, or the
        %   reader is left with a list of files and a guess.
            gas = struct('name', 'control, Day 1', 'weighted', false, ...
                'sources', {{}}, 'subjects', {{'sub01', 'sub02'}}, 'cell', 'control, Day 1');

            code = exportAnalysisScript(testCase.twoSubjects(), gas, struct());

            testCase.verifySubstring(code, '% Design cell: control, Day 1');
            % Still selected by name: the script records what was run.
            testCase.verifySubstring(code, 'filesFor(averageFiles');
        end

        function aHandBuiltGrandAverageHasNoCellLine(testCase)
            code = exportAnalysisScript(testCase.twoSubjects(), testCase.oneGrandAverage(), struct());

            testCase.verifyEmpty(strfind(code, '% Design cell:')); %#ok<STRIFCND>
        end

        % ---- grand averages built from a subset -------------------------
        function aGrandAverageSelectsOnlyItsOwnRecordings(testCase)
        %AGRANDAVERAGESELECTSONLYITSOWNRECORDINGS  A grand average built
        %   from a subset (a patient group, a pilot exclusion) must not be
        %   rebuilt over every recording the script produced.
            gas = struct('name', 'Patients', 'weighted', false, ...
                'sources', {{}}, 'subjects', {{'sub02'}}, 'cell', '');

            code = exportAnalysisScript(testCase.twoSubjects(), gas, struct());

            testCase.verifySubstring(code, 'ga1Files = filesFor(averageFiles, {averages.name}, {''sub02''})');
            testCase.verifySubstring(code, 'function files = filesFor(');
            testCase.verifyEmpty(strfind(code, 'ga1Files = averageFiles;')); %#ok<STRIFCND>
        end

        function anUnresolvedGrandAverageStillFallsBackToAll(testCase)
        %ANUNRESOLVEDGRANDAVERAGESTILLFALLSBACKTOALL  When the recordings
        %   behind it could not be recovered, using all of them is the only
        %   available answer, and the script says so rather than implying it
        %   was a deliberate choice.
            code = exportAnalysisScript(testCase.twoSubjects(), testCase.oneGrandAverage(), struct());

            testCase.verifySubstring(code, 'ga1Files = averageFiles;');
            testCase.verifySubstring(code, 'could not be');
        end

        % ---- bin scripts as their own files -----------------------------
        function aBinScriptGoesToItsOwnFileNotIntoTheCode(testCase)
        %ABINSCRIPTGOESTOITSOWNFILENOTINTOTHECODE  A bin script is source
        %   text the analyst wrote, with its own syntax and comments.
        %   Inlining a kilobyte of it as an escaped sprintf string makes
        %   both the script and the .m unreadable.
            script = sprintf('let rare = {11,22}\nbin 1 "Rare" rare\n');
            subjects = testCase.subjectWithBinScript(script);

            [code, sidecars] = exportAnalysisScript(subjects, [], struct());

            testCase.verifyNumElements(sidecars, 1);
            testCase.verifyEqual(sidecars(1).content, script);
            testCase.verifyEqual(sidecars(1).name, 'bins1.binscript');
            testCase.verifySubstring(code, 'binScript1 = fileread(fullfile(scriptDir, ''bins1.binscript''))');
            testCase.verifySubstring(code, '''script'', binScript1');
            testCase.verifyEmpty(strfind(code, 'let rare'), ...
                'The bin script text must not be inlined into the code.'); %#ok<STRIFCND>
        end

        function identicalBinScriptsShareOneFile(testCase)
        %IDENTICALBINSCRIPTSSHAREONEFILE  Every subject in a study normally
        %   runs the same bins; one file per subject would be N identical
        %   copies and N chances to drift apart.
            script = sprintf('bin 1 "A" 11\n');
            subjects = testCase.subjectWithBinScript(script);
            subjects(2) = testCase.subjectWithBinScript(script);
            subjects(2).name = 'sub02';

            [~, sidecars] = exportAnalysisScript(subjects, [], struct());

            testCase.verifyNumElements(sidecars, 1);
        end

        function differentBinScriptsGetSeparateFiles(testCase)
            subjects = testCase.subjectWithBinScript(sprintf('bin 1 "A" 11\n'));
            subjects(2) = testCase.subjectWithBinScript(sprintf('bin 1 "B" 22\n'));
            subjects(2).name = 'sub02';

            [code, sidecars] = exportAnalysisScript(subjects, [], struct());

            testCase.verifyNumElements(sidecars, 2);
            testCase.verifySubstring(code, 'bins2.binscript');
        end

        function theCompiledBinsCacheIsDropped(testCase)
        %THECOMPILEDBINSCACHEISDROPPED  .bins is derived wholly from
        %   .script and DefineBins re-parses it when absent, so carrying the
        %   compiled form only risks the type-shape mismatches re-parsing
        %   avoids (see Alakazam.templateParams, which drops it for the same
        %   reason). It is also most of the bulk of the emitted params.
            script = sprintf('bin 1 "A" 11\n');
            subjects = testCase.subjectWithBinScript(script);
            subjects(1).steps(1).params.bins = struct('label', 'A', ...
                'codes', {{'11'}}, 'compiled', true);

            code = exportAnalysisScript(subjects, [], struct());

            testCase.verifyEmpty(strfind(code, 'compiled'), ...
                'The compiled bins cache should not be emitted.'); %#ok<STRIFCND>
            testCase.verifySubstring(code, '''script'', binScript1');
        end

        function aScriptWithBinScriptsStillParses(testCase)
            subjects = testCase.subjectWithBinScript(sprintf('let a = {1}\nbin 1 "A" a\n'));
            code = exportAnalysisScript(subjects, [], struct());

            testCase.verifyEmpty(testCase.parseErrors(testCase.writeScript(code)));
        end

        function anEmptyBinScriptIsLeftAlone(testCase)
        %ANEMPTYBINSCRIPTISLEFTALONE  Nothing to write out, and no variable
        %   to point at; the params must stay usable rather than referring
        %   to a file that was never created.
            subjects = testCase.subjectWithBinScript('');

            [code, sidecars] = exportAnalysisScript(subjects, [], struct());

            testCase.verifyEmpty(sidecars);
            testCase.verifyEmpty(strfind(code, 'fileread(fullfile(scriptDir')); %#ok<STRIFCND>
        end

        function grandAverageStepsAreEmitted(testCase)
            code = exportAnalysisScript(testCase.twoSubjects(), testCase.oneGrandAverage(), struct());

            testCase.verifySubstring(code, 'GrandAverage(ga1Files, false)');
            testCase.verifySubstring(code, 'averages(end + 1)');
        end

        function noGrandAveragesStillProducesAUsableScript(testCase)
            code = exportAnalysisScript(testCase.twoSubjects(), [], struct());

            testCase.verifySubstring(code, 'no grand averages defined');
            file = testCase.writeScript(code);
            testCase.verifyEmpty(testCase.parseErrors(file));
        end
    end

    % ==================================================================== %
    methods
        function restored = verifyRoundTrip(testCase, value)
            literal = matlabLiteral(value);
            try
                restored = eval(literal); %#ok<EVLDOT>
            catch err
                testCase.verifyFail(sprintf('Literal did not evaluate: %s\n  %s', ...
                    err.message, literal));
                restored = [];
                return;
            end
            testCase.verifyTrue(isequaln(restored, value), ...
                sprintf('Round trip changed the value. Literal was:\n  %s', literal));
        end

        function steps = oneStep(~)
            steps = struct('transformId', 'Average', 'params', struct(), 'parent', -1);
        end

        function subjects = twoSubjects(~)
            steps = struct( ...
                'transformId', {'Baseline', 'Average'}, ...
                'params', {struct('Start', -100, 'Stop', 0), struct()}, ...
                'parent', {-1, 1});
            subjects = struct( ...
                'name',      {'sub01', 'sub02'}, ...
                'rawFile',   {'sub01.set', 'sub02.set'}, ...
                'cacheFile', {'sub01.mat', 'sub02.mat'}, ...
                'loader',    {'set', 'set'}, ...
                'steps',     {steps, steps});
        end

        function subjects = forkedSubject(~)
        %FORKEDSUBJECT  Baseline, then TWO children hanging off it.
            steps = struct( ...
                'transformId', {'Baseline', 'Average', 'Measure'}, ...
                'params', {struct('Start', -100), struct(), struct('windows', {{}})}, ...
                'parent', {-1, 1, 1});
            subjects = struct('name', 'sub01', 'rawFile', 'sub01.set', ...
                'loader', 'set', 'steps', steps);
        end

        function subjects = subjectWithBinScript(~, script)
            steps = struct( ...
                'transformId', {'DefineBins', 'Average'}, ...
                'params', {struct('script', script, 'epoch', struct('lo', -200, 'hi', 600)), ...
                           struct()}, ...
                'parent', {-1, 1});
            subjects = struct('name', 'sub01', 'rawFile', 'sub01.set', ...
                'loader', 'set', 'steps', steps);
        end

        function lines = executableLines(~, code)
        %EXECUTABLELINES  The code, without its comment lines.
            all = strsplit(code, newline);
            lines = all(~cellfun(@(l) startsWith(strtrim(l), '%'), all));
        end

        function hits = executableLinesMatching(~, code, needle)
        %EXECUTABLELINESMATCHING  Lines containing NEEDLE that are not
        %   comments. Section headers (%%) and explanatory comments legitimately
        %   mention things the code itself must not do, so a plain strfind
        %   over the whole text cannot tell the two apart.
            lines = strsplit(code, newline);
            isComment = cellfun(@(l) startsWith(strtrim(l), '%'), lines);
            hits = lines(~isComment & contains(lines, needle));
        end

        function gas = grandAverageStructShape(~)
        %GRANDAVERAGESTRUCTSHAPE  Exactly the fields
        %   Alakazam.onExportAnalysisScript builds, in the order it builds
        %   them. A field added on one side and not the other is a runtime
        %   error ("subscripted assignment between dissimilar structures")
        %   that no amount of reading the generator would catch, and that is
        %   how the subjects field was first missed.
            gas = struct('name', {}, 'weighted', {}, 'sources', {}, 'subjects', {}, 'cell', {});
        end

        function gas = oneGrandAverage(~)
            gas = struct('name', 'GA all', 'weighted', false, ...
                'sources', {{'a.mat', 'b.mat'}}, 'subjects', {{}}, 'cell', '');
        end

        function file = writeScript(testCase, code)
            folder = tempname();
            mkdir(folder);
            testCase.addTeardown(@() rmdir(folder, 's'));
            file = fullfile(folder, 'alakazam_analysis.m');
            fid = fopen(file, 'w');
            fwrite(fid, code, 'char');
            fclose(fid);
        end

        function report = parseErrors(~, file)
        %PARSEERRORS  MATLAB's own parser on the generated file, so "is it
        %   valid MATLAB" is answered by MATLAB rather than by inspection.
            issues = checkcode(file, '-id', '-struct');
            report = '';
            for i = 1:numel(issues)
                % Syntax errors only. checkcode also reports style advice
                % (an unused variable, a preallocation hint), which says
                % nothing about whether the script runs.
                if startsWith(issues(i).id, 'MDOTM') || contains(lower(issues(i).message), 'parse error')
                    report = [report sprintf('line %d: %s\n', issues(i).line, issues(i).message)]; %#ok<AGROW>
                end
            end
        end
    end
end
