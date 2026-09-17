classdef DimigenRiftTemplateTest < matlab.unittest.TestCase
%DIMIGENRIFTTEMPLATETEST  Regression coverage for templates/dimigen-rift.alztemplate.
%
%   Two tests, deliberately split by cost:
%
%   templateParentChainIsWellFormed -- always runs, no EEGLAB and no real
%   data needed. Checks the one thing that actually broke once already:
%   commit cff9865 trimmed the template from 8 nodes (Resample + DefineBins
%   at the front) down to 6, but left every remaining node's .parent index
%   pointing at its OLD position in the 8-node array -- node 1 (Filter)
%   pointed at itself, node 2 (AutoEyeICA) pointed forward at node 3, and
%   the last node's parent was out of range entirely. "Apply Template"
%   (onApplyTemplate.m) walks this array as resultNodes{templateNodes(k).
%   parent}, so a self- or forward-pointing parent handed Filter an empty
%   [] parent on the very first step. readTemplate's own header comment
%   states the contract plainly: "a parent appears before its children" --
%   this test checks exactly that, structurally, on every node.
%
%   appliesEndToEndToRealRiftData -- the real smoke test the structural
%   check above is a fast proxy for: threads a real subject's raw recording
%   through every node in template order (the same parent-index walk
%   onApplyTemplate.m itself does, just against plain EEG structs via
%   TransTools.invoke instead of the app's tree/cache-file machinery) and
%   checks the final result looks like a real RIFT analysis, not merely
%   "it didn't error". Needs EEGLAB + FastICA + ICLabel on the path, and
%   the real data/rift archive locally -- data/rift is real research data,
%   not part of version control (see dependencies.md and .gitignore), so
%   this is Incomplete/skipped, not Failed, on a fresh checkout or CI.
%   Tagged Slow: a real ICA decomposition on a 99-trial recording, ~25s on
%   a normal machine.
%
%   Run with: runtests('tests/DimigenRiftTemplateTest.m').

    properties (Constant, Access = private)
        TemplateFile = 'dimigen-rift.alztemplate'
        RawSubjectFile = 'ThriftyRIFT_1.set'
    end

    methods (Test)
        function templateParentChainIsWellFormed(testCase)
            nodes = testCase.readTemplateNodes();
            testCase.assertNotEmpty(nodes, 'Template has no nodes to check.');
            for k = 1:numel(nodes)
                parent = nodes(k).parent;
                testCase.verifyTrue(parent < 1 || (parent >= 1 && parent < k), sprintf( ...
                    ['Node %d ("%s") has parent=%d, which is not a valid earlier node ' ...
                     '(must be -1/root, or a positive index less than %d). ' ...
                     'onApplyTemplate.m replays resultNodes{parent}, so a self- or ' ...
                     'forward-pointing (or out-of-range) parent means Apply Template ' ...
                     'cannot be replayed correctly.'], ...
                    k, nodes(k).transformId, parent, k));
            end
        end
    end

    methods (Test, TestTags = {'Slow'})
        function appliesEndToEndToRealRiftData(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            rawDir = fullfile(root, 'data', 'rift', 'eeg_raw_set');
            setFile = fullfile(rawDir, testCase.RawSubjectFile);
            testCase.assumeTrue(isfile(setFile), ...
                ['ThriftyRIFT_1.set not found -- data/rift is real research data, not ' ...
                 'part of version control (see dependencies.md), so this end-to-end ' ...
                 'check only runs where that archive has been placed locally.']);

            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'src')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations'), 'IncludeSubfolders', true));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'src', 'Support')));

            try
                EEGLabEnvironment.ensure();
            catch
                % Fall through to the assumptions below, which report exactly
                % what is missing rather than this try/catch's own message.
            end
            testCase.assumeTrue(~isempty(which('pop_reref')), ...
                'EEGLAB is not available -- skipping the end-to-end RIFT template check.');
            testCase.assumeTrue(~isempty(which('firfilt')), ...
                'EEGLAB''s firfilt plugin is not available -- skipping.');
            testCase.assumeTrue(~isempty(which('fastica')), ...
                ['FastICA is not available -- skipping. (AutoEyeICA''s non-FastICA ' ...
                 'fallback opens pop_runica''s own GUI dialog, which a headless test ' ...
                 'cannot drive.)']);
            testCase.assumeTrue(~isempty(which('iclabel')), ...
                'EEGLAB''s ICLabel plugin is not available -- skipping.');

            % Load exactly as loadSETFile.m would (see its own header comment
            % for why DataFormat is derived rather than assumed): a plain
            % pop_loadset here, not the @WorkSpace wrapper, since this test
            % has no need for a live workspace/cache/tree.
            EEG = pop_loadset(testCase.RawSubjectFile, rawDir);
            EEG = eeg_checkset(EEG);
            EEG.DataType = 'TIMEDOMAIN';
            EEG.File = setFile;
            EEG.DataFormat = inferDataFormat(EEG);
            if strcmpi(EEG.DataFormat, 'CONTINUOUS')
                EEG.times = ((1:EEG.pnts) - 1) / EEG.srate;
            end
            EEG = deriveBinsFromEpochs(EEG);

            % The same parent-index walk onApplyTemplate.m does, on plain EEG
            % structs via TransTools.invoke instead of tree nodes/cache files.
            nodes = testCase.readTemplateNodes();
            results = cell(1, numel(nodes));
            for k = 1:numel(nodes)
                if nodes(k).parent < 1
                    stepInput = EEG;
                else
                    stepInput = results{nodes(k).parent};
                end
                [results{k}, ~] = TransTools.invoke(nodes(k).transformId, stepInput, nodes(k).params);
            end
            final = results{end};

            % It ran end to end on the real montage/trigger scheme -- now
            % check the result actually looks like a RIFT analysis, not a
            % dataset that merely survived.
            testCase.verifyEqual(final.DataFormat, 'EPOCHED');
            testCase.verifyEqual(final.nbchan, 23);   % 24 raw channels, minus Cz (re-ref)
            testCase.verifyGreaterThan(final.trials, 0);

            testCase.assertTrue(isfield(final, 'bindesc') && numel(final.bindesc) == 4, ...
                'Expected 4 bins: RIFT 64Hz, SSVEP 30Hz, RIFT 60Hz, RIFT 60Hz peripheral.');
            counts = cellfun(@numel, {final.bindesc.trials});
            testCase.verifyEqual(sum(counts), final.trials);
            % Subject 1 is in the 1-3 group (30Hz SSVEP control): that bin
            % should be populated, and the 4-10 group's peripheral-RIFT bin
            % (added by this fix -- see rift.binscript) should be empty for
            % this subject, not silently absorbing the wrong trigger.
            testCase.verifyEqual(string(final.bindesc(2).label), "SSVEP 30Hz");
            testCase.verifyGreaterThan(counts(2), 0);
            testCase.verifyEqual(string(final.bindesc(4).label), "RIFT 60Hz peripheral");
            testCase.verifyEqual(counts(4), 0);

            testCase.assertTrue(isfield(final, 'spectralMeasures') && numel(final.spectralMeasures) == 2, ...
                'Expected 2 SpectralMeasure rows (60Hz, 64Hz).');
            for r = 1:numel(final.spectralMeasures)
                testCase.verifyTrue(any(isfinite(final.spectralMeasures{r}.coherence(:))), ...
                    sprintf('SpectralMeasure row %d has no finite coherence values.', r));
            end
        end
    end

    methods (Access = private)
        function nodes = readTemplateNodes(testCase)
        %READTEMPLATENODES  The template's node list, parsed the same way
        %   Alakazam.readTemplate interprets a version-2 template (a "nodes"
        %   list, each node carrying its own parent index) -- done directly
        %   here, rather than via a live Alakazam instance, since
        %   readTemplate does not use its own (unused) first argument and
        %   this test has no other need for a running app.
            root = fileparts(fileparts(mfilename('fullpath')));
            file = fullfile(root, 'templates', testCase.TemplateFile);
            testCase.assertTrue(isfile(file), sprintf('Template not found: %s', file));
            raw = jsondecode(fileread(file));
            testCase.assertTrue(isfield(raw, 'nodes'), 'Template has no "nodes" list.');
            nodes = raw.nodes;
        end
    end
end
