classdef NativeExportEquivalenceTest < matlab.unittest.TestCase
%NATIVEEXPORTEQUIVALENCETEST  A native call emitted by the analysis-script
%   export must produce exactly what the transformation it replaces does.
%
%   WHY THIS FILE IS THE POINT OF THE FEATURE. Emitting library calls into
%   an exported script is attractive precisely because the script can then
%   be run without Alakazam, which is also what makes it dangerous: a
%   reviewer runs it, gets numbers that differ, and has been handed a
%   document that looks authoritative. "It produced a script" is no
%   evidence at all that the script reproduces the analysis.
%
%   COMPARE EVERY FIELD, NOT THE DATA. An earlier version of this file
%   compared .data, .srate and the size, and passed while the Resample
%   emission was wrong: Resample.m does not stop at pop_resample, it also
%   rewrites EEG.times into Alakazam's seconds convention, so the emitted
%   line left a time axis a factor of 1000 out. Nothing in a data
%   comparison could see that. verifyEquivalent below walks every shared
%   field, which is the only comparison that would have caught it.
%
%   AND EVAL THE EMITTER'S OWN LINES. Each case asks nativeTransformCall
%   for the lines the exporter would write and executes those, rather than
%   re-typing the call the test author believes it emits. A test that
%   types its own version of the call proves only that the author can write
%   pop_reref twice.
%
%   Run with: runtests('tests/NativeExportEquivalenceTest.m').
%
%   See also NATIVETRANSFORMCALL, EXPORTANALYSISSCRIPT.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Transformations', 'Resample'), ...
                     fullfile(root, 'src', 'Transformations', 'ReRef'), ...
                     fullfile(root, 'src', 'Transformations', 'Interpolate'), ...
                     fullfile(root, 'src', 'Transformations', 'SelectData'), ...
                     fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'IO'), ...
                     fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end

        function requireEeglab(testCase)
            testCase.assumeTrue(exist('pop_resample', 'file') == 2 && ...
                exist('eeg_emptyset', 'file') == 2, ...
                'EEGLAB is not on the path, so the native calls cannot be run.');
        end
    end

    methods (Test)
        function resampleMatchesPopResample(testCase)
        %RESAMPLEMATCHESPOPRESAMPLE  Including the seconds time axis. The
        %   fixture runs at 250 Hz, so 125 is a real resampling.
            EEG = testCase.continuousFixture();
            testCase.verifyEquivalent(EEG, 'Resample', struct('NewRate', 125));
        end

        function resampleToTheRateAlreadyInForceMatchesTheTransformation(testCase)
        %RESAMPLETOTHERATEALREADYINFORCEMATCHESTHETRANSFORMATION  The
        %   degenerate case, which is where the first version of this
        %   feature diverged. Resample returns the dataset untouched;
        %   pop_resample leaves the samples alone but renames the set,
        %   adjusts xmax and rewrites times, so the emitted lines have to
        %   carry the guard.
            EEG = testCase.continuousFixture();
            testCase.verifyEquivalent(EEG, 'Resample', struct('NewRate', EEG.srate));
        end

        function rerefToAChannelMatchesPopReref(testCase)
            EEG = testCase.continuousFixture();
            testCase.verifyEquivalent(EEG, 'ReRef', ...
                struct('mode', 'Channels', 'refChannels', {{'Oz'}}, 'keepref', false));
        end

        function rerefToAverageMatchesPopReref(testCase)
            EEG = testCase.continuousFixture();
            testCase.verifyEquivalent(EEG, 'ReRef', ...
                struct('mode', 'Average', 'keepref', false));
        end

        function rerefKeepingTheReferenceMatchesPopReref(testCase)
        %REREFKEEPINGTHEREFERENCEMATCHESPOPREREF  keepref changes the channel
        %   count, so it is worth its own case rather than a flag flip.
            EEG = testCase.continuousFixture();
            testCase.verifyEquivalent(EEG, 'ReRef', ...
                struct('mode', 'Channels', 'refChannels', {{'Oz'}}, 'keepref', true));
        end

        function interpolateMatchesPopInterp(testCase)
            EEG = testCase.positionedFixture();
            testCase.verifyEquivalent(EEG, 'Interpolate', ...
                struct('channels', {{'Oz'}}, 'method', 'spherical'));
        end

        function selectKeepingChannelsMatchesPopSelect(testCase)
        %SELECTKEEPINGCHANNELSMATCHESPOPSELECT  On continuous data, where the
        %   emitted time-axis block has to fire.
            EEG = testCase.continuousFixture();
            testCase.verifyEquivalent(EEG, 'SelectData', ...
                struct('channels', struct('mode', 'Keep', 'labels', {{'Fz', 'Cz'}})));
        end

        function selectRemovingChannelsOnEpochedDataMatchesPopSelect(testCase)
        %SELECTREMOVINGCHANNELSONEPOCHEDDATAMATCHESPOPSELECT  And here it must
        %   NOT fire: epoched data keeps milliseconds.
            EEG = testCase.epochedFixture();
            testCase.verifyEquivalent(EEG, 'SelectData', ...
                struct('channels', struct('mode', 'Remove', 'labels', {{'Oz'}})));
        end

        function interpolatingAnAbsentChannelMatchesTheTransformation(testCase)
        %INTERPOLATINGANABSENTCHANNELMATCHESTHETRANSFORMATION  The same
        %   degenerate path for pop_interp: a stored label the dataset does
        %   not have makes Interpolate a no-op, and the emitted guard has to
        %   agree rather than handing pop_interp an empty list.
            EEG = testCase.positionedFixture();
            testCase.verifyEquivalent(EEG, 'Interpolate', ...
                struct('channels', {{'T7'}}, 'method', 'spherical'));
        end

        function removingAnAbsentChannelMatchesTheTransformation(testCase)
        %REMOVINGANABSENTCHANNELMATCHESTHETRANSFORMATION  And for pop_select.
            EEG = testCase.continuousFixture();
            testCase.verifyEquivalent(EEG, 'SelectData', ...
                struct('channels', struct('mode', 'Remove', 'labels', {{'T7'}})));
        end

        % ---- where BOTH routes must refuse ------------------------------
        function anAbsentReferenceIsRefusedByBothRoutes(testCase)
        %ANABSENTREFERENCEISREFUSEDBYBOTHROUTES  The one divergence that
        %   would be silent AND wrong. pop_reref reads an empty reference
        %   as "average reference" and applies one; ReRef raises instead.
        %   Without the emitted assert, a script re-run on a montage
        %   lacking the mastoids would quietly average-reference and report
        %   nothing, so this case is the assert's whole justification.
            EEG = testCase.continuousFixture();
            params = struct('mode', 'Channels', 'refChannels', {{'M1'}}, 'keepref', false);

            testCase.verifyError(@() ReRef(EEG, params), 'Alakazam:ReRef', ...
                'ReRef itself should refuse a reference the dataset does not have.');

            % Caught by hand rather than through verifyError: the emitted
            % line is a plain assert and throws without an identifier, and
            % what matters is only that the script stops, with a message
            % that says why, rather than average-referencing in silence.
            lines = nativeTransformCall('ReRef', params, 'EEG', 'out');
            message = testCase.errorFrom(lines, EEG);
            testCase.assertNotEmpty(message, ...
                ['The emitted lines average-referenced instead of refusing. ' ...
                 'pop_reref treats an empty reference as the average, which is ' ...
                 'exactly what ReRef will not do.']);
            testCase.verifySubstring(message, 'reference channels');
        end

        function anAbsentChannelToKeepIsRefusedByBothRoutes(testCase)
        %ANABSENTCHANNELTOKEEPISREFUSEDBYBOTHROUTES  The same shape for
        %   pop_select: SelectData errors rather than keeping nothing.
            EEG = testCase.continuousFixture();
            params = struct('channels', struct('mode', 'Keep', 'labels', {{'T7'}}));

            testCase.verifyError(@() SelectData(EEG, params), 'Alakazam:SelectData', ...
                'SelectData itself should refuse to keep channels it cannot find.');

            lines = nativeTransformCall('SelectData', params, 'EEG', 'out');
            message = testCase.errorFrom(lines, EEG);
            testCase.assertNotEmpty(message, ...
                'The emitted lines did not refuse an empty channel selection.');
            testCase.verifySubstring(message, 'channels to keep');
        end

        % ---- what is deliberately NOT emitted ---------------------------
        function aTimeSelectionKeepsTheTransformationCall(testCase)
        %ATIMESELECTIONKEEPSTHETRANSFORMATIONCALL  The channels-only rule.
        %   A time range carries a millisecond-to-second conversion that an
        %   emitted line would have to restate, so the exporter declines it.
            params = struct( ...
                'channels', struct('mode', 'Keep', 'labels', {{'Fz', 'Cz'}}), ...
                'time', struct('mode', 'Keep', 'range', [0 100]));
            testCase.verifyEmpty(nativeTransformCall('SelectData', params, 'EEG', 'out'), ...
                ['A selection with a time range was emitted natively; the unit ' ...
                 'conversion behind it is exactly what must not be restated.']);
        end

        function filterKeepsTheTransformationCall(testCase)
        %FILTERKEEPSTHETRANSFORMATIONCALL  Filter designs its own kernel.
            params = struct('highpass', struct('enabled', true, 'freq', 0.1, 'db', 60));
            testCase.verifyEmpty(nativeTransformCall('Filter', params, 'EEG', 'out'), ...
                'Filter was emitted natively, which would copy its design logic.');
        end

        function everyNativeEmissionHasAnEquivalenceCase(testCase)
        %EVERYNATIVEEMISSIONHASANEQUIVALENCECASE  The guard on this file's
        %   own completeness. Reads the emitter's switch and asserts that
        %   each transformation it is willing to spell natively is covered
        %   here. Adding an emission without adding a case fails THIS test,
        %   which is the only way the requirement survives the next change.
            root = fileparts(fileparts(mfilename('fullpath')));
            src = fileread(fullfile(root, 'src', 'IO', 'nativeTransformCall.m'));

            body = extractBetween(src, 'switch char(transformId)', 'end');
            testCase.assertNotEmpty(body, 'The emitter''s switch could not be located.');

            emitted = regexp(body{1}, '^\s*case\s+''(\w+)''', 'tokens', 'lineanchors');
            emitted = cellfun(@(c) c{1}, emitted, 'UniformOutput', false);

            covered = {'Resample', 'ReRef', 'Interpolate', 'SelectData'};
            missing = setdiff(emitted, covered);
            testCase.verifyEmpty(missing, sprintf( ...
                ['These transformations are emitted as native calls but have no ' ...
                 'equivalence case here: %s. A native emission nothing compares ' ...
                 'against is a guess.'], strjoin(missing, ', ')));
        end
    end

    methods (Access = private)
        function verifyEquivalent(testCase, EEG, transformId, params)
        %VERIFYEQUIVALENT  Run the transformation and the emitted lines on the
        %   same input, and require every shared field to agree.
            lines = nativeTransformCall(transformId, params, 'EEG', 'out');
            testCase.assertNotEmpty(lines, sprintf( ...
                '%s emitted no native call, so there is nothing to compare.', transformId));

            viaTransform = feval(transformId, EEG, params);
            viaNative = testCase.runEmitted(lines, EEG);

            fields = fieldnames(viaTransform);
            testCase.verifyEmpty(setdiff(fields, fieldnames(viaNative)), sprintf( ...
                '%s: the native route is missing fields the transformation returns.', transformId));

            for k = 1:numel(fields)
                f = fields{k};
                if ~isfield(viaNative, f)
                    continue;
                end
                a = viaTransform.(f);
                b = viaNative.(f);
                if isnumeric(a) && isnumeric(b) && isequal(size(a), size(b)) && ~isempty(a)
                    testCase.verifyEqual(double(b(:)), double(a(:)), 'AbsTol', 1e-12, ...
                        sprintf('%s: field "%s" differs between the two routes.', transformId, f));
                else
                    testCase.verifyTrue(isequaln(a, b), sprintf( ...
                        '%s: field "%s" differs between the two routes.', transformId, f));
                end
            end
        end

        function out = runEmitted(~, lines, EEG) %#ok<INUSD>
        %RUNEMITTED  Execute the emitted lines exactly as written.
        %   EEG and out are the variable names the lines were generated
        %   with, so they must not be renamed here. Errors propagate, which
        %   is what the refusal cases above check.
            eval(strjoin(lines, newline()));
        end

        function message = errorFrom(testCase, lines, EEG)
        %ERRORFROM  The message the emitted lines raise, or '' if they run.
            message = '';
            try
                testCase.runEmitted(lines, EEG);
            catch ME
                message = ME.message;
            end
        end

        function EEG = continuousFixture(testCase)
            EEG = testCase.completeSet(makeTestEEG('nbchan', 4, ...
                'labels', {'Fz', 'Cz', 'Pz', 'Oz'}, 'DataFormat', 'CONTINUOUS'));
        end

        function EEG = epochedFixture(testCase)
            EEG = testCase.completeSet(makeTestEEG('nbchan', 4, ...
                'labels', {'Fz', 'Cz', 'Pz', 'Oz'}));
        end

        function EEG = positionedFixture(testCase)
        %POSITIONEDFIXTURE  With real 10-5 positions, which pop_interp needs.
            EEG = TransTools.FillChanlocs(testCase.continuousFixture(), ...
                'Alakazam:NativeExportEquivalenceTest', ...
                TransTools.Template1005File('Alakazam:NativeExportEquivalenceTest'));
        end

        function EEG = completeSet(~, EEG)
        %COMPLETESET  The fixture laid over EEGLAB's own empty set.
        %   pop_select and pop_reref read fields (chaninfo, dipfit,
        %   specdata, ...) a hand-built struct does not have. Starting from
        %   eeg_emptyset gets them all at once instead of discovering them
        %   one error at a time.
            base = eeg_emptyset();
            f = fieldnames(EEG);
            for k = 1:numel(f)
                base.(f{k}) = EEG.(f{k});
            end
            EEG = base;
            EEG.xmin = EEG.times(1);
            EEG.xmax = EEG.times(end);
            EEG.setname = 'fixture';
        end
    end
end
