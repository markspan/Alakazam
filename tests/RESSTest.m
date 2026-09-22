classdef RESSTest < matlab.unittest.TestCase
%RESSTEST  Rhythmic entrainment source separation: the filter and the
%   transformation.
%
%   The fixture is a small RIFT-shaped recording: 12 scalp channels, two eye
%   channels named by position (IO1, LO1), two mastoids and a photodiode,
%   with four bins ("RIFT 60Hz", "RIFT 60Hz peripheral", "RIFT 64Hz",
%   "SSVEP 30Hz"). The 60 and 64 Hz trials carry a response with a known
%   scalp pattern peaking at Oz, under independent noise that is strongest on
%   the eye channels. The photodiode carries the flicker itself, far larger
%   than any response, which is exactly why it must never enter the filter.
%
%   The filter's agreement with the authors' own code (github.com/mikexcohen/
%   RESS) was checked on the RIFT data outside the suite, since that code has
%   no licence to be vendored: weights, maps and components correlated
%   0.99999 or better, and the largest eigenvalues differed by 0.5 to 1.7%,
%   the frequency grid and filter width being corrected here. See
%   TransTools.RESSFilter.
%
%   Run with: runtests('tests/RESSTest.m').
%
%   See also RESS, TRANSTOOLS.RESSFILTER, TRANSTOOLS.RESSPLAN.

    properties (Constant)
        Scalp = {'Fz', 'Cz', 'C3', 'C4', 'Pz', 'PO7', 'PO3', 'POz', 'PO4', 'PO8', 'O1', 'Oz'}
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), fullfile(root, 'src', 'Dialogs'), ...
                     fullfile(root, 'src', 'Transformations'), fullfile(root, 'src', 'Transformations', 'RESS')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function theGaussianFilterHasUnitGainAndNoPhaseShift(testCase)
            srate = 500; t = (0:1999) / srate;
            at = TransTools.GaussianBandpass(sin(2 * pi * 60 * t), srate, 60, 0.5);
            half = TransTools.GaussianBandpass(sin(2 * pi * 60.25 * t), srate, 60, 0.5);

            mid = 500:1500;
            testCase.verifyEqual(at(mid), sin(2 * pi * 60 * t(mid)), 'AbsTol', 1e-2, ...
                'A sine at the centre passes unchanged, without delay.');
            testCase.verifyEqual(max(abs(half(mid))), 0.5, 'AbsTol', 5e-3, ...
                'Half the FWHM away the gain is one half.');
        end

        function theFilterFindsAKnownPattern(testCase)
            EEG = RESSTest.recording();
            scalp = ismember({EEG.chanlocs.labels}, RESSTest.Scalp);
            trials = [EEG.bindesc(1:2).trials];

            r = TransTools.RESSFilter(EEG.data(scalp, :, trials), EEG.srate, 60, struct());

            truth = RESSTest.pattern();
            testCase.verifyGreaterThan(abs(corr(r.map, truth(:))), 0.98);
            [~, peak] = max(abs(r.map));
            testCase.verifyEqual(RESSTest.Scalp{peak}, 'Oz');
            testCase.verifyGreaterThan(r.map(peak), 0, 'The map''s largest channel is positive.');
            testCase.verifyGreaterThan(r.eigenvalues(1), 5 * r.eigenvalues(2), ...
                'A real response stands out from the second component.');
        end

        function theSignFollowsTheMapNotTheData(testCase)
        %THESIGNFOLLOWSTHEMAPNOTTHEDATA  The authors' code forces the sign of
        %   the map but not of the weights, so its component's sign, and its
        %   phase lag to a photodiode, is arbitrary. Here negating the data
        %   leaves the weights as they were.
            EEG = RESSTest.recording();
            scalp = ismember({EEG.chanlocs.labels}, RESSTest.Scalp);
            X = EEG.data(scalp, :, [EEG.bindesc(1:2).trials]);

            a = TransTools.RESSFilter(X, EEG.srate, 60, struct());
            b = TransTools.RESSFilter(-X, EEG.srate, 60, struct());

            testCase.verifyEqual(b.weights, a.weights, 'AbsTol', 1e-10);
        end

        function aRankDeficientReferenceNeedsShrinkage(testCase)
            EEG = RESSTest.recording();
            scalp = ismember({EEG.chanlocs.labels}, RESSTest.Scalp);
            X = EEG.data(scalp, :, [EEG.bindesc(1:2).trials]);
            X = X - mean(X, 1);                                   % average reference: rank 11 of 12

            testCase.verifyError(@() TransTools.RESSFilter(X, EEG.srate, 60, struct('Shrinkage', 0)), ...
                'Alakazam:RESSFilter');
            r = TransTools.RESSFilter(X, EEG.srate, 60, struct());
            testCase.verifyEqual(r.rank, 11);
            truth = RESSTest.pattern();
            testCase.verifyGreaterThan(abs(corr(r.map, truth(:) - mean(truth))), 0.98);
        end

        function aRejectedTrialIsLeftOut(testCase)
            EEG = RESSTest.recording();
            scalp = ismember({EEG.chanlocs.labels}, RESSTest.Scalp);
            X = EEG.data(scalp, :, [EEG.bindesc(1:2).trials]);
            X(:, 10:20, 2) = NaN;

            r = TransTools.RESSFilter(X, EEG.srate, 60, struct());
            c = TransTools.RESSComponent(X, r.weights);

            testCase.verifyEqual(nnz(r.trialsUsed), size(X, 3) - 1);
            testCase.verifyTrue(any(isnan(c(1, :, 2))));
            testCase.verifyFalse(any(isnan(c(1, :, 1))));
        end

        function eachRowAddsItsComponentAsAChannel(testCase)
            EEG = RESSTest.recording();

            [out, options] = RESS(EEG, RESSTest.options());

            labels = {out.chanlocs.labels};
            testCase.verifyEqual(labels(end - 1:end), {'RESS60Hz', 'RESS64Hz'});
            testCase.verifyEqual({out.chanlocs(end - 1:end).type}, {'RESS', 'RESS'});
            testCase.verifyEqual(out.nbchan, EEG.nbchan + 2);
            testCase.verifySize(out.data, [EEG.nbchan + 2, EEG.pnts, EEG.trials]);
            testCase.verifyEqual(out.data(1:EEG.nbchan, :, :), EEG.data, 'The electrodes are untouched.');
            testCase.verifyTrue(iscell(options.rows) && numel(options.rows) == 2);
            scalp = eegChannelMask(out.chanlocs);
            testCase.verifyFalse(any(scalp(end - 1:end)), ...
                'A component is not a scalp channel, for any later step that picks scalp channels.');
        end

        function aFilterIsBuiltFromItsPooledBinsAndAppliedToAll(testCase)
            EEG = RESSTest.recording();

            out = RESS(EEG, RESSTest.options());

            info = out.etc.alz.ress(1);
            testCase.verifyEqual(info.bins, {'RIFT 60Hz', 'RIFT 60Hz peripheral'});
            testCase.verifyEqual(info.nTrials, numel([EEG.bindesc(1:2).trials]));
            used = ismember({EEG.chanlocs.labels}, info.channels);
            direct = TransTools.RESSFilter(EEG.data(used, :, [EEG.bindesc(1:2).trials]), EEG.srate, 60, struct());
            testCase.verifyEqual(info.weights, direct.weights, 'AbsTol', 1e-12);
            component = TransTools.RESSComponent(EEG.data(used, :, :), direct.weights);
            testCase.verifyEqual(out.data(end - 1, :, :), component, 'AbsTol', 1e-12, ...
                'Every trial gets the component, the 64 Hz and 30 Hz trials included.');
        end

        function aRowWithoutTrialsIsLeftEmptyAndNoted(testCase)
        %AROWWITHOUTTRIALSISLEFTEMPTYANDNOTED  One recording of a study may
        %   lack a condition another has (the RIFT 30 Hz control, run by
        %   subjects 1 to 3 only). RESS then adds that component empty and
        %   notes it, and builds the others as usual, so Apply to All carries
        %   on and every recording keeps the same channels.
            EEG = RESSTest.recording();
            EEG.bindesc(4).trials = [];
            opts = RESSTest.options();
            opts.rows{3} = struct('label', 'RESS30Hz', 'freq', 30, 'bins', 'SSVEP 30Hz');

            out = testCase.verifyWarning(@() RESS(EEG, opts), 'Alakazam:RESS:noTrials');
            full = RESS(EEG, RESSTest.options());

            testCase.verifyEqual({out.chanlocs(end - 2:end).labels}, {'RESS60Hz', 'RESS64Hz', 'RESS30Hz'});
            testCase.verifyTrue(all(isnan(out.data(end, :, :)), 'all'), 'Missing, not zero.');
            testCase.verifyEqual(out.data(1:end - 1, :, :), full.data, 'AbsTol', 1e-12, ...
                'The other components are built as usual.');
            info = out.etc.alz.ress(3);
            testCase.verifyEqual(info.nTrials, 0);
            testCase.verifySubstring(info.note, 'SSVEP 30Hz');
            testCase.verifyEmpty(out.etc.alz.ress(1).note);
        end

        function aRowWhoseTrialsAreAllRejectedIsLeftEmpty(testCase)
            EEG = RESSTest.recording();
            EEG.data(:, :, EEG.bindesc(3).trials) = NaN;   % how ArtefactDetect rejects a trial

            out = testCase.verifyWarning(@() RESS(EEG, RESSTest.options()), 'Alakazam:RESS:noTrials');

            testCase.verifyEqual(out.etc.alz.ress(2).nTrials, 0);
            testCase.verifyTrue(all(isnan(out.data(end, :, :)), 'all'));
            testCase.verifyEqual(out.etc.alz.ress(1).nTrials, 8);
            testCase.verifyFalse(any(isnan(out.data(end - 1, :, 1:8)), 'all'));
        end

        function eyesPhotodiodeAndMastoidsStayOut(testCase)
            EEG = RESSTest.recording();

            out = RESS(EEG, RESSTest.options());
            withMastoids = RESSTest.options();
            withMastoids.includeMastoids = true;
            out2 = RESS(EEG, withMastoids);

            testCase.verifyEqual(sort(out.etc.alz.ress(1).channels), sort(RESSTest.Scalp));
            testCase.verifyEqual(sort(out2.etc.alz.ress(1).channels), sort([RESSTest.Scalp, {'M1', 'M2'}]));
        end

        function runningAgainReplacesTheComponents(testCase)
            EEG = RESSTest.recording();
            once = RESS(EEG, RESSTest.options());

            twice = RESS(once, RESSTest.options());

            testCase.verifyEqual(twice.nbchan, once.nbchan);
            testCase.verifyEqual(twice.data, once.data, 'AbsTol', 1e-12, ...
                'The earlier components are removed first, so they never enter the new filter.');
        end

        function storedOptionsReplayAfterAJsonRoundTrip(testCase)
        %STOREDOPTIONSREPLAYAFTERAJSONROUNDTRIP  A template or a saved node
        %   brings the rows back as a struct array, not the cell array RESS
        %   stores.
            EEG = RESSTest.recording();
            [a, options] = RESS(EEG, RESSTest.options());

            b = RESS(EEG, jsondecode(jsonencode(options)));

            testCase.verifyEqual(b.data, a.data, 'AbsTol', 1e-12);
        end

        function settingsItCannotApplyAreExplained(testCase)
            EEG = RESSTest.recording();
            bad = RESSTest.options();
            bad.rows{1}.bins = 'RIFT 61Hz';
            testCase.verifyError(@() RESS(EEG, bad), 'Alakazam:RESS');
            bad = RESSTest.options();
            bad.rows{2}.label = 'RESS60Hz';
            testCase.verifyError(@() RESS(EEG, bad), 'Alakazam:RESS');
            bad = RESSTest.options();
            bad.rows{1}.label = 'Oz';
            testCase.verifyError(@() RESS(EEG, bad), 'Alakazam:RESS');
            bad = RESSTest.options();
            bad.rows{1}.label = 'RESS 60Hz';   % Spectral Measure would read "RESS" and "60Hz"
            testCase.verifyError(@() RESS(EEG, bad), 'Alakazam:RESS');
            bad = RESSTest.options();
            bad.timeStart = 100;
            testCase.verifyError(@() RESS(EEG, bad), 'Alakazam:RESS');
            continuous = EEG;
            continuous.DataFormat = 'CONTINUOUS';
            testCase.verifyError(@() RESS(continuous, RESSTest.options()), 'Alakazam:RESS');
        end

        function aBinLabelNamesItsFrequency(testCase)
            testCase.verifyEqual(TransTools.FrequencyFromLabel({'RIFT 64Hz', 'SSVEP 7.5 Hz left', 'Target'}), ...
                [64 7.5 NaN]);
        end
    end

    methods (Static)
        function p = pattern()
        %PATTERN  The response's scalp pattern over RESSTest.Scalp, largest at Oz.
            p = [0.05 0.1 0.08 0.08 0.3 0.5 0.55 0.7 0.55 0.5 0.8 1.0];
        end

        function EEG = recording()
            rng(11);
            srate = 500; nsamp = 1500; nTrials = 16;
            labels = [RESSTest.Scalp, {'IO1', 'LO1', 'M1', 'M2', 'PhotoDiode'}];
            nChan = numel(labels);
            t = (0:nsamp - 1) / srate;
            bins = {'RIFT 60Hz', 'RIFT 60Hz peripheral', 'RIFT 64Hz', 'SSVEP 30Hz'};
            binFreq = [60 60 64 30];
            data = zeros(nChan, nsamp, nTrials);
            p = RESSTest.pattern();
            mixing = 0.6 * randn(nChan, nChan);
            for tr = 1:nTrials
                b = ceil(tr / 4);
                noise = mixing * filter(1, [1 -0.95], randn(nChan, nsamp), [], 2);
                noise(13:14, :) = noise(13:14, :) * 6;                  % eye channels: large
                flicker = sin(2 * pi * binFreq(b) * t + 2 * pi * rand);
                data(:, :, tr) = noise;
                data(1:12, :, tr) = data(1:12, :, tr) + 1.5 * p' * flicker;
                data(end, :, tr) = 50 * flicker;                        % the photodiode
            end
            EEG = struct('DataFormat', 'EPOCHED', 'DataType', 'TimeDomain', 'srate', srate, ...
                'nbchan', nChan, 'pnts', nsamp, 'trials', nTrials, 'times', t * 1000, ...
                'chanlocs', struct('labels', labels), 'data', data, ...
                'bindesc', struct('label', bins, 'trials', {1:4, 5:8, 9:12, 13:16}, 'combo', {[], [], [], []}));
        end

        function o = options()
            o = struct('rows', {{struct('label', 'RESS60Hz', 'freq', 60, 'bins', 'RIFT 60Hz, RIFT 60Hz peripheral'), ...
                                 struct('label', 'RESS64Hz', 'freq', 64, 'bins', 'RIFT 64Hz')}}, ...
                'includeMastoids', false, 'timeStart', [], 'timeStop', [], ...
                'peakFWHM', 0.5, 'neighbourDistance', 1, 'neighbourFWHM', 1, 'shrinkage', 0.01);
        end
    end
end
