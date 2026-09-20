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

    methods (Test)
        function templateReferencesToTheAverageAsThePaperDid(testCase)
        %TEMPLATEREFERENCESTOTHEAVERAGEASTHEPAPERDID  Dimigen et al. (2025)
        %   recorded against an online average reference and analysed
        %   average-referenced data. The template used to re-reference to Cz
        %   instead, which lowered the Oz coherence at the tag by about 13%
        %   (0.242 against the paper's 0.280 at 60 Hz) and made the weak
        %   peripheral condition look significant when the paper's is barely
        %   so. With the average reference Alakazam reproduces the paper's
        %   t statistics to within 0.03, so this is the one preprocessing
        %   choice a template named after the paper must not get wrong. The
        %   photodiode is excluded so the average is over electrodes only.
            nodes = testCase.readTemplateNodes();
            ids = string({nodes.transformId});
            k = find(ids == "ReRef", 1);
            testCase.assertNotEmpty(k, 'The template has no ReRef node.');
            params = nodes(k).params;
            testCase.verifyEqual(string(params.mode), "Average", ...
                'The paper used an average reference; a Cz reference changes the Oz result.');
            testCase.verifyTrue(any(strcmpi(cellstr(string(params.exclude)), 'PhotoDiode')), ...
                'The photodiode is not an electrode and must stay out of the average.');
        end
    end

    methods (Test)
        function templateAsksForTheFrameAveragedCoherenceAndTheReferencesOwnTag(testCase)
        %TEMPLATEASKSFORTHEFRAMEAVERAGEDCOHERENCEANDTHEREFERENCESOWNTAG  On the same ten
        %   recordings the frame-averaged coherence agrees with newcrossf (the
        %   paper's estimator) to 0.001, where the single window this template's
        %   SpectralMeasure and topography used to use reads 2.4 to 2.9 times higher,
        %   and newcrossf itself cannot read a row outside its 52-68 Hz band (the 30 Hz
        %   SSVEP row). The topography's band search drew that condition at its 60 Hz
        %   harmonic. So the template must ask for the frame estimator and the
        %   reference's own tag, or it silently returns to numbers that do not compare
        %   with the paper or with the coherence map.
            nodes = testCase.readTemplateNodes();
            ids = string({nodes.transformId});

            sm = nodes(find(ids == "SpectralMeasure", 1)).params;
            testCase.verifyEqual(string(sm.coherenceMethod), "frames");
            testCase.verifyFalse(logical(sm.crossf.enabled), 'The older flag means newcrossf and only that.');

            topo = nodes(find(ids == "CoherenceTopography", 1)).params;
            testCase.verifyEqual(string(topo.Method), "frames");
            testCase.verifyEqual(string(topo.TagSource), "reference");
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
            used = cell(1, numel(nodes));     % the options each step settled on
            for k = 1:numel(nodes)
                if nodes(k).parent < 1
                    stepInput = EEG;
                else
                    stepInput = results{nodes(k).parent};
                end
                [results{k}, used{k}] = TransTools.invoke(nodes(k).transformId, stepInput, nodes(k).params);
            end
            final = results{end};

            % It ran end to end on the real montage/trigger scheme -- now
            % check the result actually looks like a RIFT analysis, not a
            % dataset that merely survived.
            testCase.verifyEqual(final.DataFormat, 'EPOCHED');
            testCase.verifyEqual(final.nbchan, 24);   % all 24 raw channels: an average reference drops none

            % The ReRef node really did produce an average reference: across
            % the electrodes (everything but the photodiode) the mean at
            % every sample is zero.
            reref = results{2};
            electrodes = ~strcmp({reref.chanlocs.labels}, 'PhotoDiode');
            testCase.verifyLessThan( ...
                max(abs(mean(double(reref.data(electrodes, :)), 1))), 1e-3, ...
                'The ReRef node did not leave the electrodes average-referenced.');
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

            testCase.assertTrue(isfield(final, 'spectralMeasures') && numel(final.spectralMeasures) == 3, ...
                'Expected 3 SpectralMeasure rows (60Hz, 64Hz, 30Hz).');
            for r = 1:numel(final.spectralMeasures)
                testCase.verifyTrue(any(isfinite(final.spectralMeasures{r}.coherence(:))), ...
                    sprintf('SpectralMeasure row %d has no finite coherence values.', r));
            end

            % The template asks for the frame-averaged coherence, and the 30 Hz row,
            % outside any newcrossf band, is read at 30 Hz rather than left at a
            % band edge: this subject's SSVEP bin is the one that responds to it.
            testCase.verifyEqual(used{end}.coherenceMethod, 'frames');
            ssvep = final.spectralMeasures{3}.coherence(:, 2);
            testCase.verifyGreaterThan(max(ssvep(isfinite(ssvep))), 0.2, ...
                'The 30 Hz row should read the SSVEP response, not the value at 52 Hz.');

            % The topography takes each bin's frequency from the photodiode's own
            % spectrum, so the 30 Hz condition is drawn at 30 Hz and not at the 60 Hz
            % harmonic a 52-68 Hz search band would find.
            topography = results{8};
            testCase.verifyEqual(topography.CohTopoMethod, 'frames');
            testCase.verifyEqual(topography.CohTopoFreqs(strcmp(topography.CohTopoBinLabels, 'SSVEP 30Hz')), ...
                30, 'AbsTol', 0.5);
            testCase.verifyEqual(topography.CohTopoFreqs(strcmp(topography.CohTopoBinLabels, 'RIFT 60Hz')), ...
                60, 'AbsTol', 0.5);
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
