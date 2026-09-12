classdef ReRefTest < matlab.unittest.TestCase
%REREFTEST  Unit tests for src/Transformations/ReRef/ReRef.m: re-referencing
%   itself (previously untested) and reconstructing an implicit reference
%   channel.
%
%   THE IMPLICIT-REFERENCE MATHS, IN ONE LINE. A channel referenced to
%   itself always reads zero, so its true signal relative to a NEW
%   reference is just the negative of whatever waveform re-referencing
%   subtracted from every other channel. Every implicit-reference test
%   below checks the reconstructed channel against that waveform computed
%   independently (a plain mean() over the pre-reref data), not against
%   ReRef's own working -- the point is to catch the maths being wrong, not
%   to confirm the code agrees with itself.
%
%   Run with: runtests('tests/ReRefTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Transformations', 'ReRef'), ...
                     fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end

        function requireEeglab(testCase)
            testCase.assumeTrue(exist('pop_reref', 'file') == 2 && exist('eeg_emptyset', 'file') == 2, ...
                'EEGLAB is not on the path, so ReRef (which wraps pop_reref) cannot be run.');
        end
    end

    methods (Test)
        % ---- re-referencing itself (no prior coverage existed) -----------

        function averageReferenceSubtractsTheChannelMean(testCase)
            EEG = testCase.fixture();
            opts = struct('mode', 'Average', 'refChannels', {{}}, 'exclude', {{}}, ...
                'keepref', false, 'implicitRef', '');

            out = ReRef(EEG, opts);

            expected = EEG.data - mean(EEG.data, 1);
            % 1e-4, not something tighter: pop_reref casts through single
            % precision internally, which on data of this magnitude rounds
            % at roughly the 1e-7 level -- comfortably below this tolerance,
            % well above exact equality.
            testCase.verifyEqual(double(out.data), expected, 'AbsTol', 1e-4);
        end

        function specificChannelReferenceSubtractsTheirMean(testCase)
            EEG = testCase.fixture();
            opts = struct('mode', 'Specific channels', 'refChannels', {{'A1', 'A2'}}, ...
                'exclude', {{}}, 'keepref', false, 'implicitRef', '');

            out = ReRef(EEG, opts);

            % keepref is false, so pop_reref removes the reference channels
            % themselves from the result -- that is the whole point of the
            % checkbox ("keep the reference channel(s) in the data").
            idx = TransTools.LabelsToIdx(EEG, {'A1', 'A2'});
            remaining = setdiff(1:EEG.nbchan, idx);
            expected = EEG.data(remaining, :) - mean(EEG.data(idx, :), 1);
            testCase.verifyEqual(out.nbchan, numel(remaining));
            testCase.verifyEqual(double(out.data), expected, 'AbsTol', 1e-4);
        end

        function excludeIsLeftOutOfTheAverageAndUntouched(testCase)
            EEG = testCase.fixture();
            opts = struct('mode', 'Average', 'refChannels', {{}}, 'exclude', {{'A2'}}, ...
                'keepref', false, 'implicitRef', '');

            out = ReRef(EEG, opts);

            a2 = TransTools.LabelsToIdx(EEG, {'A2'});
            others = setdiff(1:EEG.nbchan, a2);
            expectedAverage = mean(EEG.data(others, :), 1);
            testCase.verifyEqual(double(out.data(others, :)), EEG.data(others, :) - expectedAverage, 'AbsTol', 1e-4);
            testCase.verifyEqual(double(out.data(a2, :)), EEG.data(a2, :), 'AbsTol', 1e-4, ...
                'The excluded channel should be left untouched by re-referencing.');
        end

        % ---- reconstructing the implicit reference ------------------------

        function implicitReferenceUnderAverageModeIsMinusTheAverage(testCase)
            EEG = testCase.fixture();
            opts = struct('mode', 'Average', 'refChannels', {{}}, 'exclude', {{}}, ...
                'keepref', false, 'implicitRef', 'Cz');

            out = ReRef(EEG, opts);

            testCase.assertEqual(out.nbchan, EEG.nbchan + 1);
            cz = testCase.indexOf(out.chanlocs, 'Cz');
            expected = -mean(EEG.data, 1);
            testCase.verifyEqual(double(out.data(cz, :)), expected, 'AbsTol', 1e-4);
        end

        function implicitReferenceUnderSpecificChannelModeIsMinusTheirMean(testCase)
            EEG = testCase.fixture();
            opts = struct('mode', 'Specific channels', 'refChannels', {{'A1', 'A2'}}, ...
                'exclude', {{}}, 'keepref', false, 'implicitRef', 'Cz');

            out = ReRef(EEG, opts);

            idx = TransTools.LabelsToIdx(EEG, {'A1', 'A2'});
            expected = -mean(EEG.data(idx, :), 1);
            cz = testCase.indexOf(out.chanlocs, 'Cz');
            testCase.verifyEqual(double(out.data(cz, :)), expected, 'AbsTol', 1e-4);
        end

        function implicitReferenceStillCorrectWithAnExcludedChannel(testCase)
        %IMPLICITREFERENCESTILLCORRECTWITHANEXCLUDEDCHANNEL  The probe used
        %   to read the reference waveform back out must skip excluded
        %   channels (they are untouched, so they would read back a flat
        %   zero instead of the real waveform) -- this is what would break
        %   if that guard were removed.
            EEG = testCase.fixture();
            opts = struct('mode', 'Average', 'refChannels', {{}}, 'exclude', {{'A2'}}, ...
                'keepref', false, 'implicitRef', 'Cz');

            out = ReRef(EEG, opts);

            a2 = TransTools.LabelsToIdx(EEG, {'A2'});
            others = setdiff(1:EEG.nbchan, a2);
            expected = -mean(EEG.data(others, :), 1);
            cz = testCase.indexOf(out.chanlocs, 'Cz');
            testCase.verifyEqual(double(out.data(cz, :)), expected, 'AbsTol', 1e-4);
        end

        function implicitReferenceGetsA1005PositionWhenItsLabelMatches(testCase)
        %IMPLICITREFERENCEGETSA1005POSITIONWHENITSLABELMATCHES  A nicety
        %   (scalp maps, interpolation), not the point of the feature, but
        %   worth confirming FillChanlocs is actually reached.
            testCase.assumeTrue(~isempty(which('readlocs')), 'readlocs is not on the path.');
            EEG = testCase.fixture();
            opts = struct('mode', 'Average', 'refChannels', {{}}, 'exclude', {{}}, ...
                'keepref', false, 'implicitRef', 'Cz');

            out = ReRef(EEG, opts);

            cz = testCase.indexOf(out.chanlocs, 'Cz');
            testCase.verifyTrue(isfield(out.chanlocs, 'X') && ~isempty(out.chanlocs(cz).X) ...
                && ~isnan(out.chanlocs(cz).X), ...
                'Cz is on the standard 10-5 template and should have been positioned.');
        end

        % ---- where the reconstructed channel is inserted -------------------

        function implicitReferenceIsInsertedNextToItsNearestTemplateNeighbour(testCase)
        %IMPLICITREFERENCEISINSERTEDNEXTTOITSNEARESTTEMPLATENEIGHBOUR  Tacked
        %   onto the very end, a scalp channel would land after every
        %   peripheral one and say nothing about where on the head it sits.
        %   Cz sits on the midline between the two mastoids in the 10-5
        %   template, so with only Fz/Pz/Oz/A1/A2 in the dataset it should
        %   land next to whichever of those is geometrically closest -- not
        %   simply appended last.
            testCase.assumeTrue(~isempty(which('readlocs')), 'readlocs is not on the path.');
            EEG = testCase.fixture();
            opts = struct('mode', 'Average', 'refChannels', {{}}, 'exclude', {{}}, ...
                'keepref', false, 'implicitRef', 'Cz');

            out = ReRef(EEG, opts);

            cz = testCase.indexOf(out.chanlocs, 'Cz');
            testCase.verifyNotEqual(cz, out.nbchan, ...
                'Cz was appended at the very end instead of next to a template neighbour.');

            % Independently recompute the expected neighbour (nearest of
            % Fz/Pz/Oz/A1/A2 to Cz on the template) and check Cz landed
            % immediately next to it (either side -- insertion is "after",
            % but a neighbour at the start of the list has nothing before it
            % to be "after" other than itself).
            elcFile = TransTools.Template1005File('Alakazam:ReRefTest');
            template = readlocs(elcFile);
            tLabels = lower(string({template.labels}));
            czXYZ = testCase.templateXYZ(template, tLabels, 'cz');
            dists = arrayfun(@(c) norm(testCase.templateXYZ(template, tLabels, lower(c.labels)) - czXYZ), EEG.chanlocs);
            [~, nearest] = min(dists);
            nearestLabel = EEG.chanlocs(nearest).labels;
            nearestIdxInOut = testCase.indexOf(out.chanlocs, nearestLabel);
            testCase.verifyEqual(cz, nearestIdxInOut + 1, ...
                sprintf('Expected Cz right after its nearest template neighbour (%s).', nearestLabel));
        end

        function anImplicitReferenceNotOnTheTemplateFallsBackToTheEnd(testCase)
        %ANIMPLICITREFERENCENOTONTHETEMPLATEFALLSBACKTOTHEEND  A custom name
        %   (a lab that calls its reference "REF" rather than an electrode
        %   name) has no template position to place it by, so ordering falls
        %   back to the simple, always-available default.
            EEG = testCase.fixture();
            opts = struct('mode', 'Average', 'refChannels', {{}}, 'exclude', {{}}, ...
                'keepref', false, 'implicitRef', 'REF');

            out = ReRef(EEG, opts);

            testCase.verifyEqual(out.chanlocs(end).labels, 'REF');
        end

        function noImplicitReferenceFieldMeansNoNewChannel(testCase)
        %NOIMPLICITREFERENCEFIELDMEANSNONEWCHANNEL  Backward compatibility:
        %   an options struct stored before this feature existed has no
        %   implicitRef field at all, and must replay exactly as before.
            EEG = testCase.fixture();
            opts = struct('mode', 'Average', 'refChannels', {{}}, 'exclude', {{}}, 'keepref', false);

            out = ReRef(EEG, opts);

            testCase.verifyEqual(out.nbchan, EEG.nbchan);
        end

        function anImplicitReferenceNamedAfterAnExistingChannelThrows(testCase)
            EEG = testCase.fixture();
            opts = struct('mode', 'Average', 'refChannels', {{}}, 'exclude', {{}}, ...
                'keepref', false, 'implicitRef', 'Fz');

            testCase.verifyError(@() ReRef(EEG, opts), 'Alakazam:ReRef');
        end
    end

    methods (Access = private)
        function idx = indexOf(~, chanlocs, label)
            idx = find(strcmpi({chanlocs.labels}, label), 1);
        end

        function xyz = templateXYZ(~, template, templateLabelsLower, label)
            m = find(templateLabelsLower == label, 1);
            xyz = [template(m).X, template(m).Y, template(m).Z];
        end

        function EEG = fixture(testCase)
            EEG = testCase.completeSet(makeTestEEG('nbchan', 5, ...
                'labels', {'Fz', 'Pz', 'Oz', 'A1', 'A2'}, 'DataFormat', 'CONTINUOUS'));
        end

        function EEG = completeSet(~, EEG)
        %COMPLETESET  The fixture laid over EEGLAB's own empty set, so
        %   pop_reref finds every field it reads (chaninfo, dipfit, ...)
        %   instead of discovering them one error at a time. Same pattern as
        %   NativeExportEquivalenceTest's own completeSet.
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
