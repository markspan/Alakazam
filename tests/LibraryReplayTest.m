classdef LibraryReplayTest < matlab.unittest.TestCase
%LIBRARYREPLAYTEST  The library's templates, replayed on their own data,
%   still give the results recorded when they were checked.
%
%   Each template with a recorded result was run on real data once, by hand,
%   and the result written down: in Docs/luck.md (the Luck chapters and
%   N400-complete), chapter 20 of the manual (the N400 worked example),
%   Docs/dimigen.md (RIFT) and chapter 17 (the face-saccade deconvolution).
%   A check made once goes stale as the code changes, and a change that moves
%   what a template produces would pass every other test. This replays each
%   template the way Apply Template does (every step through
%   TransTools.invoke, each on its parent's result) and compares with those
%   numbers.
%
%   Two templates have no recorded result, dimigen-rift-simplified and
%   ReadingDeconvolution. For those this checks that they run end to end on
%   their data and produce what they are for.
%
%   THE DATA IS NOT IN THE REPOSITORY (see DATA.md). Every case assumes its
%   recording is present under Data/, and skips rather than fails where it is
%   not, naming the file it looked for. The toolboxes a template needs
%   (EEGLAB with firfilt, FastICA and ICLabel, GEDAI, Unfold, EYE-EEG) are
%   assumed the same way. Tagged Slow: the ICA, GEDAI and deconvolution steps
%   take minutes.
%
%   WHICH RECORDING. A Luck chapter's result was recorded on the first
%   participant in that chapter's folder ("subject 1" in Docs/luck.md), so
%   each case runs on the lowest-numbered recording there and names it in
%   any failure. Chapter 10 runs on the continuous LRP recording, as the
%   manual's capture does.
%
%   TOLERANCES follow how each value was written down: half a unit of its
%   last digit, and a little more for the rounding. ICA is not seeded, so a
%   template that runs it gets a wider tolerance: a new decomposition moves
%   the result slightly.
%
%   Run with: runtests('tests/LibraryReplayTest.m').
%
%   See also LIBRARYTEST, DIMIGENRIFTTEMPLATETEST, FACESACCADESTEMPLATETEST.

    properties (TestParameter)
        % The Luck chapter templates: the difference bin's mean amplitude, in
        % the template's first measurement window, recorded in Docs/luck.md
        % ("A template per chapter").
        Chapter = struct( ...
            'ch02', struct('template', 'luck/ch02-N400-one-participant.alztemplate', ...
                'folder', 'ch2', 'suffix', '_N400_preprocessed.set', 'value', -7.05, 'tolerance', 0.006), ...
            'ch03', struct('template', 'luck/ch03-N400-many-participants.alztemplate', ...
                'folder', 'ch3', 'suffix', '_N400_preprocessed.set', 'value', -5.90, 'tolerance', 0.006), ...
            'ch06', struct('template', 'luck/ch06-P3b.alztemplate', ...
                'folder', 'ch6', 'suffix', '_P3_corrected.set', 'value', 5.88, 'tolerance', 0.006), ...
            'ch07', struct('template', 'luck/ch07-MMN.alztemplate', ...
                'folder', 'ch7', 'suffix', '_MMN_preprocessed.set', 'value', -2.61, 'tolerance', 0.006), ...
            'ch08', struct('template', 'luck/ch08-N2pc.alztemplate', ...
                'folder', 'ch8', 'suffix', '_N2pc_ICA_preprocessed.set', 'value', -1.72, 'tolerance', 0.006), ...
            'ch09', struct('template', 'luck/ch09-MMN-with-ICA.alztemplate', ...
                'folder', 'ch9', 'suffix', '_MMN_preprocessed.set', 'value', -1.86, 'tolerance', 0.1), ...
            'ch10', struct('template', 'luck/ch10-LRP.alztemplate', ...
                'folder', 'ch10', 'suffix', '_LRP_continuous.set', 'value', -2.50, 'tolerance', 0.006))
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = LibraryReplayTest.root();
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'src')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations'), 'IncludeSubfolders', true));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'src', 'Support')));
            try
                EEGLabEnvironment.ensure();
            catch
                % The assumptions in each case say what is missing.
            end
        end
    end

    methods (Test, TestTags = {'Slow'})
        function aLuckChapterGivesItsRecordedDifference(testCase, Chapter)
            file = testCase.luckRecording(Chapter.folder, Chapter.suffix);
            nodes = testCase.templateNodes(Chapter.template);
            results = testCase.replay(nodes, file);

            measured = results{stepIndex(nodes, 'Measure')};
            testCase.verifyEqual(differenceBinValue(measured, 1, 'amplitude'), Chapter.value, ...
                'AbsTol', Chapter.tolerance, sprintf( ...
                '%s on %s no longer gives the %.2f uV recorded in Docs/luck.md.', ...
                Chapter.template, fileName(file), Chapter.value));
        end

        function n400CompleteGivesItsRecordedRun(testCase)
        %N400COMPLETEGIVESITSRECORDEDRUN  Docs/luck.md, "The fullest chain":
        %   on chapter 3's first subject the N400 difference is -5.9 uV at
        %   CPz, its 50% negative-area onset near 391 ms, and 70 of 230
        %   epochs are rejected (the book's own Butterworth filter rejects 67).
            file = testCase.luckRecording('ch3', '_N400_preprocessed.set');
            nodes = testCase.templateNodes('N400-complete.alztemplate');
            results = testCase.replay(nodes, file);

            measured = results{stepIndex(nodes, 'Measure')};
            testCase.verifyEqual(differenceBinValue(measured, 1, 'amplitude'), -5.9, 'AbsTol', 0.06);
            testCase.verifyEqual(differenceBinValue(measured, 2, 'latency'), 391, 'AbsTol', 2);

            rejection = results{stepIndex(nodes, 'ArtefactDetect')}.etc.alz.artefactDetectors;
            testCase.verifyEqual(rejection.nTrials, 230, 'Epochs examined.');
            testCase.verifyEqual(rejection.totalEpochs, 70, 'Epochs rejected.');
        end

        function theN400WorkedExampleGivesTheManualsTable(testCase)
        %THEN400WORKEDEXAMPLEGIVESTHEMANUALSTABLE  Chapter 20 of the manual:
        %   N400.alztemplate on the ten chapter 3 subjects, the N400 window's
        %   mean amplitude at Cz averaged over subjects, per bin.
        %
        %   The manual also gives the difference bin as M = -2.79 uV, SD =
        %   1.69, which does not agree with its own table (0.804 - 3.563 =
        %   -2.759); a mean amplitude is linear, so the two cannot both be
        %   right. The difference bin is checked here against the table,
        %   bin by bin and subject by subject, and its mean and SD are logged
        %   so the manual can be corrected to whichever is current.
            files = testCase.luckRecordings('ch3', '_N400_preprocessed.set');
            testCase.assumeNumElements(files, 10, sprintf( ...
                'The worked example uses ten chapter 3 recordings; %d were found.', numel(files)));
            nodes = testCase.templateNodes('N400.alztemplate');

            amplitude = zeros(numel(files), 5);
            for s = 1:numel(files)
                results = testCase.replay(nodes, files{s});
                measured = results{stepIndex(nodes, 'Measure')};
                amplitude(s, :) = measured.measurements{1}.amplitude(1, 1:5);
            end

            testCase.verifyEqual(mean(amplitude(:, 1:4), 1), [0.178, 0.186, 3.563, 0.804], ...
                'AbsTol', 0.0006, 'The per-bin means no longer match the manual''s table.');
            testCase.verifyEqual(std(amplitude(:, 1:4), 0, 1), [1.647, 2.027, 2.247, 1.763], ...
                'AbsTol', 0.0006, 'The per-bin SDs no longer match the manual''s table.');
            testCase.verifyEqual(amplitude(:, 5), amplitude(:, 4) - amplitude(:, 3), 'AbsTol', 1e-9, ...
                'The N400 bin should be bin 4 minus bin 3 in every subject.');
            testCase.log(matlab.unittest.Verbosity.Terse, sprintf( ...
                'N400 difference bin over ten subjects: M = %.3f uV, SD = %.3f.', ...
                mean(amplitude(:, 5)), std(amplitude(:, 5))));
        end

        function theRiftTemplateGivesItsRecordedCoherence(testCase)
        %THERIFTTEMPLATEGIVESITSRECORDEDCOHERENCE  Docs/dimigen.md, "Which
        %   coherence estimator": the frame-averaged coherence to the
        %   photodiode at Oz, over the ten recordings, is 0.283 at 60 Hz in
        %   the 60 Hz trials and 0.238 at 64 Hz in the 64 Hz trials (the
        %   paper: 0.280 and 0.241).
            files = testCase.riftRecordings(1:10);
            nodes = testCase.templateNodes('dimigen-rift.alztemplate');

            coherence = zeros(numel(files), 2);
            for s = 1:numel(files)
                results = testCase.replay(nodes, files{s});
                final = results{stepIndex(nodes, 'SpectralMeasure')};
                coherence(s, :) = [tagCoherence(final, 1, 'RIFT 60Hz'), tagCoherence(final, 2, 'RIFT 64Hz')];
            end
            testCase.verifyEqual(mean(coherence(:, 1)), 0.283, 'AbsTol', 0.005, '60 Hz in 60 Hz trials.');
            testCase.verifyEqual(mean(coherence(:, 2)), 0.238, 'AbsTol', 0.005, '64 Hz in 64 Hz trials.');
        end

        function theSimplifiedRiftTemplateRunsEndToEnd(testCase)
        %THESIMPLIFIEDRIFTTEMPLATERUNSENDTOEND  No recorded result: the
        %   template gives the same four bins and three coherence rows as the
        %   full one, with a coherence at Oz for every tagged bin this subject
        %   saw.
            files = testCase.riftRecordings(1);
            nodes = testCase.templateNodes('dimigen-rift-simplified.alztemplate');
            results = testCase.replay(nodes, files{1});
            final = results{stepIndex(nodes, 'SpectralMeasure')};

            testCase.verifyEqual(final.DataFormat, 'EPOCHED');
            testCase.verifyEqual(string({final.bindesc.label}), ...
                ["RIFT 64Hz", "SSVEP 30Hz", "RIFT 60Hz", "RIFT 60Hz peripheral"]);
            testCase.assertNumElements(final.spectralMeasures, 3, 'Rows for 60, 64 and 30 Hz.');
            testCase.verifyTrue(isfinite(tagCoherence(final, 1, 'RIFT 60Hz')));
            testCase.verifyTrue(isfinite(tagCoherence(final, 2, 'RIFT 64Hz')));
        end

        function theFaceSaccadeTemplateGivesFigureElevensNumbers(testCase)
        %THEFACESACCADETEMPLATEGIVESFIGUREELEVENSNUMBERS  Chapter 17 of the
        %   manual: between 300 and 500 ms at Oz the plain average of the
        %   stimulus bin peaks at 23.6 uV and the deconvolved waveform at
        %   17.7 uV, and 3337 of the 3829 events keep an overlap-corrected
        %   trial.
            file = testCase.dataFile('opendata', 'face_saccades_opendata_fig10.set');
            nodes = testCase.templateNodes('FaceSaccadesDeconvolution.alztemplate');
            results = testCase.replay(nodes, file);

            deconvolved = results{1};
            trials = results{2};
            plain = results{stepIndex(nodes, 'Average')};
            testCase.verifyEqual(peakIn(deconvolved, 'Stimulus', 'Oz', [300 500]), 17.7, 'AbsTol', 0.06);
            testCase.verifyEqual(peakIn(plain, 'Stimulus', 'Oz', [300 500]), 23.6, 'AbsTol', 0.06);
            testCase.verifyEqual(trials.trials, 3337, 'Overlap-corrected trials kept.');
        end

        function theReadingTemplateRunsEndToEnd(testCase)
        %THEREADINGTEMPLATERUNSENDTOEND  No recorded result: the eye track
        %   joins onto the EEG, with its synchronisation recorded, and the
        %   deconvolution returns a waveform per bin with numbers in it.
            file = testCase.dataFile('reading', 'reading_eeg.set');
            nodes = testCase.templateNodes('ReadingDeconvolution.alztemplate');
            results = testCase.replay(nodes, file);

            joined = results{stepIndex(nodes, 'EyeTracking')};
            testCase.verifyTrue(isfield(joined.etc, 'alz') && isfield(joined.etc.alz, 'eyeTracking'), ...
                'EyeTracking should record how good the synchronisation was.');
            testCase.verifyTrue(any(strcmpi({joined.chanlocs.type}, 'EYE')), ...
                'The gaze and pupil channels should be typed EYE.');

            fitted = results{stepIndex(nodes, 'Deconvolve')};
            testCase.verifyEqual(char(fitted.DataFormat), 'Averaged');   % a string, as Average sets it
            testCase.verifyNotEmpty(fitted.bindesc);
            testCase.verifyTrue(any(isfinite(fitted.data(:))), 'The fit returned no numbers.');
        end
    end

    methods (Access = private)
        function nodes = templateNodes(testCase, name)
        %TEMPLATENODES  A library template as Apply Template reads it
        %   (Alakazam.readTemplate): a node list, or an older flat list of
        %   steps, each step then the child of the one before.
            file = fullfile(libraryFolder('templates'), name);
            testCase.assertTrue(isfile(file), sprintf('%s is not in the library.', name));
            raw = jsondecode(fileread(file));
            if isfield(raw, 'nodes')
                items = asItems(raw.nodes);
                parents = cellfun(@(it) double(it.parent), items);
            else
                items = asItems(raw.steps);
                parents = (1:numel(items)) - 1;
                parents(1) = -1;
            end
            nodes = struct('transformId', cellfun(@(it) char(it.transformId), items, 'UniformOutput', false), ...
                'params', cellfun(@(it) it.params, items, 'UniformOutput', false), ...
                'parent', num2cell(parents));
        end

        function results = replay(testCase, nodes, file)
        %REPLAY  Every step on its parent's result, as onApplyTemplate walks
        %   the node list, after the toolboxes the steps need are confirmed.
        %   Each dataset carries a cache path in .File, as in the app, where
        %   the workspace gives the recording one and every result gets
        %   resultCacheFile's (see replayBranch): AutoEyeICA and AutoGEDAI
        %   name their output after it and ScalpDistribution keeps it.
            testCase.requireToolboxesFor(nodes);
            cache = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            raw = loadRecording(file);
            [~, name] = fileparts(file);
            raw.File = fullfile(cache, [name '.mat']);
            results = cell(1, numel(nodes));
            for k = 1:numel(nodes)
                if nodes(k).parent < 1
                    input = raw;
                else
                    input = results{nodes(k).parent};
                end
                results{k} = TransTools.invoke(nodes(k).transformId, input, nodes(k).params);
                results{k}.File = resultCacheFile(input.File, nodes(k).transformId);
            end
        end

        function requireToolboxesFor(testCase, nodes)
            ids = {nodes.transformId};
            testCase.assumeTrue(~isempty(which('pop_loadset')), 'EEGLAB is not on the path.');
            if ismember('Filter', ids)
                testCase.assumeTrue(~isempty(which('firfilt')), 'EEGLAB''s firfilt plugin is not available.');
            end
            if ismember('AutoEyeICA', ids)
                testCase.assumeTrue(~isempty(which('fastica')) && ~isempty(which('iclabel')), ...
                    'FastICA or ICLabel is not available.');
            end
            if ismember('AutoGEDAI', ids) && isempty(which('GEDAI'))
                % Installed but not on this session's path: attach it here,
                % as AutoGEDAI would, since its install prompt is a dialog a
                % headless test cannot answer.
                installed = EEGLabEnvironment.findInstalled('GEDAI', 'GEDAI.m');
                testCase.assumeNotEmpty(installed, 'GEDAI is not installed.');
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(installed));
            end
            if ismember('Deconvolve', ids)
                testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            end
            if ismember('EyeTracking', ids)
                testCase.assumeTrue(EyeEeg.isAvailable(), 'EYE-EEG is not installed.');
            end
        end

        function file = luckRecording(testCase, folder, suffix)
        %LUCKRECORDING  The lowest-numbered subject's recording in a chapter.
            files = testCase.luckRecordings(folder, suffix);
            testCase.assumeNotEmpty(files, sprintf( ...
                'No *%s in Data/Luck/%s (run downloadLuckData.m).', suffix, folder));
            file = files{1};
        end

        function files = luckRecordings(~, folder, suffix)
        %LUCKRECORDINGS  A chapter's recordings ending in SUFFIX, by subject.
            listing = dir(fullfile(LibraryReplayTest.root(), 'Data', 'Luck', folder, ['*' suffix]));
            subject = arrayfun(@(d) str2double(regexp(d.name, '^\d+', 'match', 'once')), listing);
            [~, order] = sort(subject);
            files = arrayfun(@(d) fullfile(d.folder, d.name), listing(order), 'UniformOutput', false);
            files = reshape(files, 1, []);
        end

        function files = riftRecordings(testCase, subjects)
        %RIFTRECORDINGS  ThriftyRIFT_<n>.set, under Data/RIFT as the capture
        %   script has it, or data/rift as DimigenRiftTemplateTest has it.
            files = arrayfun(@(n) sprintf('ThriftyRIFT_%d.set', n), subjects, 'UniformOutput', false);
            for folder = {fullfile('Data', 'RIFT'), fullfile('data', 'rift')}
                where = fullfile(LibraryReplayTest.root(), folder{1}, 'eeg_raw_set');
                if all(cellfun(@(f) isfile(fullfile(where, f)), files))
                    files = cellfun(@(f) fullfile(where, f), files, 'UniformOutput', false);
                    return;
                end
            end
            testCase.assumeFail(sprintf('The RIFT recordings %s are not under Data/RIFT/eeg_raw_set.', ...
                strjoin(files, ', ')));
        end

        function file = dataFile(testCase, folder, name)
            file = fullfile(LibraryReplayTest.root(), 'Data', folder, name);
            testCase.assumeTrue(isfile(file), sprintf('%s is not present (see DATA.md).', file));
        end
    end

    methods (Static, Access = private)
        function r = root()
            r = fileparts(fileparts(mfilename('fullpath')));
        end
    end
end

% ======================================================================= %
function EEG = loadRecording(file)
%LOADRECORDING  A .set file as WorkSpace.loadSETFile prepares it.
    [folder, name, ext] = fileparts(file);
    EEG = pop_loadset([name ext], folder);
    EEG = eeg_checkset(EEG);
    EEG = recordRawFile(EEG, file);
    EEG.DataType = 'TIMEDOMAIN';
    EEG.DataFormat = inferDataFormat(EEG);
    if strcmpi(EEG.DataFormat, 'CONTINUOUS')
        EEG.times = ((1:EEG.pnts) - 1) / EEG.srate;
    elseif strcmpi(EEG.DataFormat, 'EPOCHED') && ~isempty(EEG.times) && max(abs(EEG.times(:))) < 10
        EEG.times = EEG.times * 1000;
    end
    EEG = deriveBinsFromEpochs(EEG);
end

function items = asItems(list)
%ASITEMS  A decoded JSON list as a cell array, whichever shape it came in.
    if iscell(list)
        items = reshape(list, 1, []);
    else
        items = reshape(num2cell(list), 1, []);
    end
end

function k = stepIndex(nodes, transformId)
%STEPINDEX  The template's first step of this transformation.
    k = find(strcmp({nodes.transformId}, transformId), 1);
    assert(~isempty(k), 'The template has no %s step.', transformId);
end

function value = differenceBinValue(EEG, window, field)
%DIFFERENCEBINVALUE  A measurement window's value on the difference bin, at
%   the window's one channel.
    isCombo = arrayfun(@(b) isfield(b, 'combo') && ~isempty(b.combo), EEG.bindesc);
    bin = find(isCombo, 1);
    assert(~isempty(bin), 'The result has no difference bin.');
    value = EEG.measurements{window}.(field)(1, bin);
end

function value = tagCoherence(EEG, row, binLabel)
%TAGCOHERENCE  Spectral Measure's coherence at Oz for one row and bin. A
%   row's matrices run over its own channels (.channels), not the dataset's.
    m = EEG.spectralMeasures{row};
    oz = strcmpi(cellstr(string(m.channels)), 'Oz');
    bin = strcmp({EEG.bindesc.label}, binLabel);
    assert(nnz(oz) == 1 && nnz(bin) == 1, 'Row %d has no single Oz, or no bin "%s".', row, binLabel);
    value = m.coherence(oz, bin);
end

function value = peakIn(EEG, binLabel, channel, windowMs)
%PEAKIN  The largest value of one bin's waveform at a channel in a window.
    c = strcmpi({EEG.chanlocs.labels}, channel);
    b = strcmp({EEG.bindesc.label}, binLabel);
    t = EEG.times >= windowMs(1) & EEG.times <= windowMs(2);
    value = max(EEG.data(c, t, b));
end

function name = fileName(file)
    [~, stem, ext] = fileparts(file);
    name = [stem ext];
end
