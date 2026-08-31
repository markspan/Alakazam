classdef ParcellateTest < matlab.unittest.TestCase
%PARCELLATETEST  The Parcellate transformation.
%
%   Most of these tests exercise paths that reject bad input BEFORE any
%   source modelling happens, so they cost nothing. The end-to-end ones need
%   a real forward model, which costs about 22 seconds to build once per
%   session (a leadfield over 20484 cortical points x N electrodes), and are
%   tagged 'Slow' so they can be singled out or skipped:
%
%       runtests('tests/ParcellateTest.m', 'Tag', 'Slow')   % just those
%
%   They are NOT excluded from the ordinary run. A tag that removes a test
%   from the only lane anyone runs is a tag that removes the test, and this
%   is the one place the whole pipeline is exercised against the real
%   template files rather than a synthetic fixture. The 22 seconds is paid
%   once, because the forward model is cached for the session.
%
%   The pieces those tests are not the only cover for -- the inverse, the
%   normals, the atlas mapping, the sign flipping -- are each tested
%   directly and quickly in SourceInverseTest and ParcellationTest against
%   synthetic forward models. This file is about the wiring.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Dialogs'), ...
                     fullfile(root, 'src', 'Transformations', 'Parcellate')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        % ---- refusing what it cannot do -----------------------------------
        function aDatasetWithNoDataIsRefused(testCase)
            EEG = struct('data', [], 'chanlocs', struct('labels', {'Cz'}));

            testCase.verifyError(@() Parcellate(EEG, testCase.opts()), ...
                'Alakazam:Parcellate');
        end

        function aDatasetWithNoChannelsIsRefused(testCase)
            EEG = struct('data', randn(4, 10), 'chanlocs', []);

            testCase.verifyError(@() Parcellate(EEG, testCase.opts()), ...
                'Alakazam:Parcellate');
        end

        function parcellatingTwiceIsRefusedWithAReason(testCase)
        %PARCELLATINGTWICEISREFUSEDWITHAREASON  The output of this
        %   transformation looks like an ordinary dataset by design, which is
        %   exactly why it can be dragged back onto itself. Its "channels"
        %   are regions, so there are no scalp signals left to invert, and
        %   the forward model would silently resolve nothing.
            EEG = struct('data', randn(4, 10), ...
                'chanlocs', struct('labels', {'Precentral_L'}), ...
                'isParcellated', true);

            testCase.verifyError(@() Parcellate(EEG, testCase.opts()), 'Alakazam:Parcellate');
            try
                Parcellate(EEG, testCase.opts());
                testCase.verifyFail('A parcellated dataset was accepted for parcellation.');
            catch err
                testCase.verifySubstring(err.message, 'already parcellated');
            end
        end

        % ---- the plugin contract --------------------------------------------
        %
        %   NOTHING IN THIS FILE MAY CALL Parcellate WITH THE 'Init'
        %   SENTINEL, OR WITH NO OPTIONS AT ALL. InitGuard sets
        %   interactive = true for exactly those cases, so either one opens
        %   the real modal dialog and waits for a human -- which, in a test
        %   run, means the suite hangs until somebody notices and presses
        %   Cancel. It does not time out. An earlier version of this file
        %   did precisely that, on the mistaken assumption that passing
        %   'Init' explicitly was the replay path; it is not, it IS the
        %   interactive trigger. Replay means passing a real options struct.
        function unrecognisedOptionsLeaveTheDatasetAlone(testCase)
        %UNRECOGNISEDOPTIONSLEAVETHEDATASETALONE  The defensive branch: an
        %   options value that is not a struct (and not the interactive
        %   sentinel) means nothing was recorded, so the dataset passes
        %   through rather than being computed from guesses.
            EEG = testCase.smallDataset();

            [out, options] = Parcellate(EEG, 'not-a-recorded-options-struct');

            testCase.verifyEqual(out.data, EEG.data);
            testCase.verifyEqual(options, 'not-a-recorded-options-struct');
        end

        function theManifestMatchesTheEntryFunction(testCase)
        %THEMANIFESTMATCHESTHEENTRYFUNCTION  The manifest IS the
        %   registration -- the ribbon scans for it and never consults a
        %   central list -- so a manifest naming a file that is not there
        %   produces a button that fails only when pressed.
            root = fileparts(fileparts(mfilename('fullpath')));
            dir = fullfile(root, 'src', 'Transformations', 'Parcellate');
            manifest = jsondecode(fileread(fullfile(dir, 'Parcellate.json')));

            testCase.verifyEqual(manifest.Name, 'Parcellate');
            testCase.verifyTrue(isfile(fullfile(dir, manifest.Entry)));
            testCase.verifyTrue(isfile(fullfile(dir, manifest.Icon)));

            [~, ~, alpha] = imread(fullfile(dir, manifest.Icon));
            testCase.verifyNotEmpty(alpha, ...
                'The icon has no alpha channel, so it will show a white box in the ribbon.');
        end

    end

    % ---- the real thing, against the real template files --------------------
    methods (Test, TestTags = {'Slow'})
        function theWholePipelineProducesARegionDataset(testCase)
        %THEWHOLEPIPELINEPRODUCESAREGIONDATASET  End to end against the real
        %   template head model. Tagged Slow: the leadfield alone is ~22 s.
            FieldTripFixtures.require(testCase);
            EEG = testCase.realisticDataset();

            out = FieldTripFixtures.quietly(@() Parcellate(EEG, testCase.opts()));

            testCase.verifySize(out.data, [out.nbchan, size(EEG.data, 2), size(EEG.data, 3)]);
            testCase.verifyGreaterThan(out.nbchan, 60);
            testCase.verifyTrue(out.isParcellated);

            % Signed, which is the whole reason for the normal projection.
            testCase.verifyLessThan(min(out.data(:)), 0);
            testCase.verifyGreaterThan(max(out.data(:)), 0);

            % No scalp geometry: a topography of 85 scattered region
            % centroids would be a picture of nothing, so the positions are
            % left empty and the scalp views refuse the dataset outright.
            testCase.verifyEmpty(out.chanlocs(1).X);

            % Everything else about the dataset must survive, or it stops
            % being usable by Measure and the export.
            testCase.verifyEqual(out.times, EEG.times);
            testCase.verifyEqual(out.bindesc, EEG.bindesc);
        end

        function choosingRegionsKeepsOnlyThose(testCase)
            FieldTripFixtures.require(testCase);
            EEG = testCase.realisticDataset();

            all = FieldTripFixtures.quietly(@() Parcellate(EEG, testCase.opts()));
            wanted = {all.chanlocs(1).labels, all.chanlocs(5).labels};
            some = FieldTripFixtures.quietly(@() Parcellate(EEG, testCase.opts('Regions', wanted)));

            testCase.verifyEqual({some.chanlocs.labels}, wanted);
            testCase.verifySize(some.data, [2, size(EEG.data, 2), size(EEG.data, 3)]);
        end

        function itSurvivesTheContractSeam(testCase)
        %ITSURVIVESTHECONTRACTSEAM  Through TransTools.invoke, with a real
        %   options struct -- the replay path. Slow, because a genuine replay
        %   really does compute.
            FieldTripFixtures.require(testCase);
            EEG = testCase.realisticDataset();

            [out, options] = FieldTripFixtures.quietly(@() TransTools.invoke('Parcellate', EEG, testCase.opts()));

            testCase.verifyTrue(out.isParcellated);
            testCase.verifyTrue(isstruct(options));
        end

        function askingForRegionsThatDoNotExistSaysSo(testCase)
            FieldTripFixtures.require(testCase);
            EEG = testCase.realisticDataset();

            testCase.verifyError(@() Parcellate(EEG, ...
                testCase.opts('Regions', {'Left_Hippocampus_Of_Narnia'})), ...
                'Alakazam:Parcellate');
        end
    end

    methods (Access = private)
        function o = opts(~, varargin)
            o = struct('Method', 'mne', 'Atlas', 'aal', 'Mode', 'mean_flip', ...
                'MinVertices', 20, 'Regions', {{}});
            for k = 1:2:numel(varargin)
                o.(varargin{k}) = varargin{k + 1};
            end
        end

        function EEG = smallDataset(~)
            EEG = struct();
            EEG.data = randn(3, 10);
            EEG.times = linspace(-100, 300, 10);
            EEG.srate = 25;
            EEG.chanlocs = struct('labels', {'Cz', 'Pz', 'Fz'});
        end

        function EEG = realisticDataset(~)
            labels = {'Fp1','Fp2','F7','F3','Fz','F4','F8','FC5','FC1','FC2','FC6', ...
                      'T7','C3','Cz','C4','T8','CP5','CP1','CP2','CP6','P7','P3', ...
                      'Pz','P4','P8','O1','Oz','O2'};
            rng(3);
            EEG = struct();
            EEG.data = randn(numel(labels), 40, 2) * 5e-6;
            EEG.times = linspace(-200, 600, 40);
            EEG.srate = 50;
            EEG.pnts = 40;
            EEG.nbchan = numel(labels);
            EEG.chanlocs = struct('labels', labels);
            EEG.bindesc = struct('label', {'Target', 'Standard'});
        end
    end
end


