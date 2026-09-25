classdef OverlapCorrectedTrialsTest < matlab.unittest.TestCase
%OVERLAPCORRECTEDTRIALSTEST  Deconvolve's second output: one trial per
%   binned event with every other event's fitted response taken out.
%
%   TWO HALVES. The arithmetic (Unfold.overlapCorrectedTrials) is checked
%   without the toolbox, on a model built by hand to fit its data exactly,
%   where the answer is known sample for sample: each trial must come out as
%   its own event's response and nothing else. The rest is checked against
%   the real fit (External): that the trials average back to the fitted
%   waveforms, which is the property that says the trials and the model
%   agree; that each single trial has lost the overlap, not just their mean;
%   and that the result is shaped like the epoch node DefineBins cuts, since
%   that is what lets Average, EpochView and the data-quality report take it.
%
%   Run with: runtests('tests/OverlapCorrectedTrialsTest.m').
%
%   See also UNFOLD.OVERLAPCORRECTEDTRIALS, UNFOLD.FITBINS, DECONVOLVE,
%   DECONVOLVETEST, DECONVOLUTIONROWS.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Transformations', 'Deconvolve'), ...
                     fullfile(root, 'src', 'Transformations', 'DefineBins'), ...
                     fullfile(root, 'src', 'Transformations', 'Average'), ...
                     fullfile(root, 'src', 'Support'), fullfile(root, 'src', 'IO'), ...
                     fullfile(root, 'src', 'Reports'), fullfile(root, 'src', 'Views'), ...
                     fullfile(root, 'tests')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    % ---- the arithmetic, on a model that fits exactly ------------------- %
    methods (Test)
        function eachTrialIsItsOwnResponseAndNothingElse(testCase)
        %EACHTRIALISITSOWNRESPONSEANDNOTHINGELSE  With data that is exactly
        %   the model's prediction, what is left of a trial once the others
        %   are subtracted is its own event's response, however close the
        %   neighbours were.
            m = OverlapCorrectedTrialsTest.exactModel();

            [trials, usable] = Unfold.overlapCorrectedTrials(m.data, m.model, m.owner, m.anchors, m.none);

            testCase.verifyTrue(all(usable));
            testCase.verifyEqual(trials, repmat(m.model.beta_dc(:, :, 1), 1, 1, numel(m.anchors)), ...
                'AbsTol', 1e-10);
        end

        function anEventInTwoBinsKeepsBothShares(testCase)
        %ANEVENTINTWOBINSKEEPSBOTHSHARES  Its two design rows are both its
        %   own, so neither bin's share is subtracted as a neighbour.
            m = OverlapCorrectedTrialsTest.exactModel('SecondRowOnFirstTrial', true);

            trials = Unfold.overlapCorrectedTrials(m.data, m.model, m.owner, m.anchors, m.none);

            both = m.model.beta_dc(:, :, 1) + m.model.beta_dc(:, :, 2);
            testCase.verifyEqual(trials(:, :, 1), both, 'AbsTol', 1e-10);
            testCase.verifyEqual(trials(:, :, 2), m.model.beta_dc(:, :, 1), 'AbsTol', 1e-10);
        end

        function aTrialOnAStretchLeftOutIsNotUsable(testCase)
        %ATRIALONASTRETCHLEFTOUTISNOTUSABLE  The model was told nothing about
        %   those samples, so nothing was subtracted from them.
            m = OverlapCorrectedTrialsTest.exactModel();
            bad = m.none;
            % Windows are 60 samples and trials 40 apart, so most samples lie
            % in two windows; 15 after the second anchor lies in its alone.
            bad(round(m.anchors(2)) + 15) = true;

            [trials, usable] = Unfold.overlapCorrectedTrials(m.data, m.model, m.owner, m.anchors, bad);

            testCase.verifyEqual(usable, [true false true(1, numel(m.anchors) - 2)]);
            testCase.verifyTrue(all(isnan(trials(:, :, 2)), 'all'));
            testCase.verifyTrue(all(isfinite(trials(:, :, [1 3:end])), 'all'));
        end

        function aTrialOffTheRecordingIsNotUsable(testCase)
            m = OverlapCorrectedTrialsTest.exactModel();
            anchors = m.anchors;
            anchors(1) = 3;              % its pre-event samples do not exist

            [~, usable] = Unfold.overlapCorrectedTrials(m.data, m.model, m.owner, anchors, m.none);

            testCase.verifyFalse(usable(1));
            testCase.verifyTrue(all(usable(2:end)));
        end

        function theReportSaysHowManyTrialsTheModelCorrected(testCase)
        %THEREPORTSAYSHOWMANYTRIALSTHEMODELCORRECTED  The trials form is
        %   described by its counts; the averaged form, by having no SME.
            template = struct('step', '', 'item', '', 'n', NaN, 'n_total', NaN, 'pct', NaN, ...
                'channels_tested', NaN, 'scope', '', 'threshold', NaN, ...
                'n_samples_rejected', NaN, 'n_samples', NaN, 'detail', '');
            info = struct('output', 'trials', 'window', [-200 800], 'baseline', [-200 0], ...
                'nuisanceTypes', {{'evt_response'}}, 'notes', {{'A note.'}}, ...
                'excludedSeconds', 2, 'recordingSeconds', 100, ...
                'artifact', struct('thresholdUv', 0), ...
                'trials', 240, 'trialCandidates', 246, 'trialsDropped', 6);
            EEG.etc.alz.unfold = info;

            rows = deconvolutionRows(EEG, template, 64);
            info.output = 'average';
            EEG.etc.alz.unfold = info;
            averaged = deconvolutionRows(EEG, template, 64);

            testCase.verifyEqual({rows.item}, {'seconds of recording', 'model note'});
            testCase.verifySubstring(rows(1).detail, 'overlap-corrected trials: 240 of 246 kept, 6 dropped');
            testCase.verifyFalse(contains(rows(1).detail, 'no SME'));
            testCase.verifySubstring(averaged(1).detail, 'no SME');
            testCase.verifyEqual(rows(1).pct, 2);
            testCase.verifyEmpty(deconvolutionRows(struct(), template, 64), ...
                'A dataset that was not deconvolved has no rows.');
        end
    end

    % ---- against the real fit ------------------------------------------- %
    methods (Test, TestTags = {'External'})
        function theTrialsAverageBackToTheFittedWaveforms(testCase)
        %THETRIALSAVERAGEBACKTOTHEFITTEDWAVEFORMS  At the least-squares fit
        %   each bin's residuals sum to zero at every lag, so Average of the
        %   corrected trials is the fitted waveform. Were the trials cut one
        %   sample off the rows the betas were fitted to, or a neighbour
        %   subtracted twice, this is where it would show.
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            EEG = DeconvolveTest.untaggedRecording();

            waveforms = Deconvolve(EEG, DeconvolveTest.options());
            trials = Deconvolve(EEG, DeconvolveTest.options('output', 'trials'));
            averaged = Average(trials);

            testCase.assertEqual(trials.etc.alz.unfold.trialsDropped, 0, ...
                'The fixture keeps every window on the recording, so the identity is exact.');
            testCase.verifyEqual(averaged.times, waveforms.times);
            testCase.verifyEqual(averaged.data, waveforms.data, 'AbsTol', 1e-4, ...
                'Average of the overlap-corrected trials is the deconvolved waveform.');
        end

        function everySingleTrialHasLostTheOverlap(testCase)
        %EVERYSINGLETRIALHASLOSTTHEOVERLAP  Not only their mean: every
        %   stimulus is followed 300 to 700 ms later by a response whose own
        %   waveform lands inside the stimulus's window, and each corrected
        %   trial should be the stimulus's waveform alone (zero after 400 ms)
        %   plus the recording's noise.
        %
        %   Its own recording, because the shared fixture's responses come
        %   exactly 600 ms after every frequent stimulus: a lag that never
        %   varies, which is the one design deconvolution cannot separate
        %   (Unfold.binModel says so in a note), so there the overlapping
        %   part of a single trial is not identified and cannot be checked.
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            [EEG, waveform] = OverlapCorrectedTrialsTest.jitteredRecording();

            trials = Deconvolve(EEG, DeconvolveTest.options('output', 'trials', ...
                'baselineMs', [], 'binScript', 'bin 1 "Stimulus" "S1"'));

            target = zeros(1, numel(trials.times));
            own = find(abs(trials.times) < 1e-9) + (0:numel(waveform) - 1);
            target(own) = waveform;
            offsets = round(trials.times / 1000 * EEG.srate);
            worstCorrected = 0;
            worstRaw = 0;
            for t = reshape(TransTools.BinTrials(trials, 1), 1, [])
                latency = EEG.event(trials.epoch(t).event).latency;
                worstCorrected = max(worstCorrected, max(abs(trials.data(1, :, t) - target)));
                worstRaw = max(worstRaw, max(abs(EEG.data(1, latency + offsets) - target)));
            end
            testCase.verifyLessThan(worstCorrected, 0.5, ...
                'Every corrected trial is its own response plus noise.');
            testCase.verifyGreaterThan(worstRaw, 1.5, ...
                'The raw epochs do carry the overlap, or this test shows nothing.');
        end

        function theTrialsKnowWhenTheirNeighboursCame(testCase)
        %THETRIALSKNOWWHENTHEIRNEIGHBOURSCAME  So EpochView can sort them by
        %   the next response without the bin having to name it.
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            EEG = OverlapCorrectedTrialsTest.jitteredRecording();

            trials = Deconvolve(EEG, DeconvolveTest.options('output', 'trials', ...
                'binScript', 'bin 1 "Stimulus" "S1"'));

            stimuli = [EEG.event(strcmp({EEG.event.type}, 'S1')).latency];
            responses = [EEG.event(strcmp({EEG.event.type}, 'R')).latency];
            % The first response after each stimulus, which is not always its
            % own: where two stimuli fall close together, the earlier one's
            % response can come after the later one.
            expected = arrayfun(@(s) min(responses(responses > s)) - s, stimuli) / EEG.srate * 1000;
            key = epochSortKeys(trials);
            key = key(strcmp({key.id}, 'next:R'));
            testCase.assertNotEmpty(key, 'The next response is offered as a sort key.');
            testCase.verifyEqual(key.values, expected, 'AbsTol', 1e-9);
        end

        function theTrialsAreShapedLikeAnEpochNode(testCase)
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            EEG = DeconvolveTest.untaggedRecording();

            trials = Deconvolve(EEG, DeconvolveTest.options('output', 'trials'));

            testCase.verifyEqual(trials.DataFormat, 'EPOCHED');
            testCase.verifyEqual(size(trials.data), [2 numel(trials.times) 120]);
            testCase.verifyEqual(trials.trials, 120);
            testCase.verifyEqual(numel(trials.epoch), 120);
            testCase.verifyEqual(numel(TransTools.BinTrials(trials, 1)), 90);
            testCase.verifyEqual(numel(TransTools.BinTrials(trials, 2)), 30);
            testCase.verifyEqual([trials.bindesc.n], [90 30]);
            zero = find(abs(trials.times) < 1e-9);
            for k = [1 60 120]
                anchor = trials.event(trials.epoch(k).event);
                testCase.verifyEqual(anchor.epoch, k);
                testCase.verifyEqual(anchor.latency, (k - 1) * trials.pnts + zero, ...
                    'Anchor latencies are on the epoched timeline, as cutEpochs leaves them.');
            end
            testCase.verifyEqual(trials.etc.alz.unfold.output, 'trials');
        end

        function aCutDropsOnlyTheTrialsAroundIt(testCase)
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            EEG = DeconvolveTest.untaggedRecording();
            cut = 10000;
            EEG.event(end + 1) = struct('type', 'boundary', 'latency', cut);
            [~, order] = sort([EEG.event.latency]);
            EEG.event = EEG.event(order);

            trials = Deconvolve(EEG, DeconvolveTest.options('output', 'trials'));

            info = trials.etc.alz.unfold;
            spans = info.excludedIntervals;
            span = spans(spans(:, 1) <= cut & spans(:, 2) >= cut, :);
            stimuli = strcmp({EEG.event.type}, 'S1') | strcmp({EEG.event.type}, 'S2');
            latency = [EEG.event(stimuli).latency];
            first = latency - 20;        % the window is -200 to 800 ms at 100 Hz
            last = latency + 79;
            touching = nnz(first <= span(2) & last >= span(1));
            testCase.assertGreaterThan(touching, 0, 'The cut has to land among the trials.');
            testCase.verifyEqual(info.trialsDropped, touching);
            testCase.verifyEqual(trials.trials, 120 - touching);
            testCase.verifyTrue(all(isfinite(trials.data), 'all'));
        end

        function theDataQualityReportMeasuresTheTrials(testCase)
        %THEDATAQUALITYREPORTMEASURESTHETRIALS  The point of having trials
        %   for a deconvolved subject: the noise figures exist, and what the
        %   model left out is still reported beside them.
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            EEG = DeconvolveTest.untaggedRecording();
            trials = Deconvolve(EEG, DeconvolveTest.options('output', 'trials'));

            q = dataQualityMetrics(trials, Average(trials), {}, false);

            testCase.verifyEqual(q.subject.n_trials, 120);
            testCase.verifyTrue(all(isfinite([q.byBinChannel.sme_uv])), ...
                'Every bin and channel has an SME, which a fitted waveform alone cannot give.');
            steps = {q.provenance.step};
            testCase.verifyTrue(any(strcmp(steps, 'Deconvolve')));
            detail = q.provenance(find(strcmp(steps, 'Deconvolve'), 1)).detail;
            testCase.verifySubstring(detail, 'overlap-corrected trials: 120 of 120 kept');
        end

        function theChoiceSurvivesATemplate(testCase)
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            EEG = DeconvolveTest.untaggedRecording();
            stored = jsondecode(jsonencode(DeconvolveTest.options('output', 'trials')));

            trials = Deconvolve(EEG, stored);

            testCase.verifyEqual(trials.DataFormat, 'EPOCHED');
        end
    end

    methods (Static)
        function [EEG, waveform] = jitteredRecording()
        %JITTEREDRECORDING  Stimuli ('S1') each followed by a response ('R')
        %   30 to 70 samples later, at 100 Hz, both with a 400 ms waveform,
        %   so every stimulus window holds a response at a lag that varies.
            srate = 100;
            npnts = 20000;
            t = (0:round(0.4 * srate)) / srate;
            waveform = 5 * sin(pi * t / 0.4) .* exp(-t / 0.25);
            rng(11);
            stimuli = round(linspace(300, 19000, 90) + 40 * randn(1, 90));
            responses = stimuli + randi([30 70], 1, 90);
            data = 0.05 * randn(2, npnts);
            for k = stimuli
                data = UnfoldBinsTest.addResponse(data, k, waveform);
            end
            for k = responses
                data = UnfoldBinsTest.addResponse(data, k, -0.8 * waveform);
            end
            event = struct('type', [repmat({'S1'}, 1, 90), repmat({'R'}, 1, 90)], ...
                'latency', num2cell([stimuli, responses]));
            [~, order] = sort([event.latency]);
            EEG = struct('data', data, 'srate', srate, 'pnts', npnts, 'trials', 1, ...
                'nbchan', 2, 'xmin', 0, 'xmax', (npnts - 1) / srate, ...
                'times', (0:npnts - 1) / srate * 1000, 'DataFormat', 'CONTINUOUS', ...
                'chanlocs', struct('labels', {'Cz', 'Pz'}), 'event', event(order));
        end

        function m = exactModel(varargin)
        %EXACTMODEL  A design built by uf_timeexpandDesignmat's own rule, and
        %   data that is exactly its prediction: trials of type A every 40
        %   samples with a 60-sample response, so each overlaps the next, and
        %   a type B event 17 samples after each.
            parsed = inputParser();
            parsed.addParameter('SecondRowOnFirstTrial', false);
            parsed.parse(varargin{:});

            srate = 100;
            timelimits = [-0.1 0.5];
            lags = round(timelimits(1) * srate):round(timelimits(2) * srate - 1);
            nlags = numel(lags);
            shift = (1:nlags) + timelimits(1) * srate - 1;
            npnts = 1500;
            anchors = 100:40:1300;
            latency = [anchors, anchors + 17];
            type = [ones(1, numel(anchors)), 2 * ones(1, numel(anchors))];
            owner = [1:numel(anchors), zeros(1, numel(anchors))];
            if parsed.Results.SecondRowOnFirstTrial
                latency(end + 1) = anchors(1);
                type(end + 1) = 2;
                owner(end + 1) = 1;
            end
            X = zeros(numel(latency), 2);
            X(sub2ind(size(X), 1:numel(latency), type)) = 1;

            rows = [];
            cols = [];
            for r = 1:numel(latency)
                rows = [rows, round(round(latency(r)) + shift)]; %#ok<AGROW>
                cols = [cols, (type(r) - 1) * nlags + (1:nlags)]; %#ok<AGROW>
            end
            Xdc = sparse(rows, cols, 1, npnts, 2 * nlags);

            t = (0:nlags - 1) / nlags;
            beta = zeros(2, nlags, 2);
            beta(:, :, 1) = [sin(2 * pi * t); 0.5 * cos(3 * pi * t)];
            beta(:, :, 2) = [-2 * t; exp(-4 * t)];
            flat = reshape(permute(beta, [2 3 1]), 2 * nlags, 2);

            m.model = struct('Xdc', Xdc, 'Xdc_terms2cols', kron(1:2, ones(1, nlags)), ...
                'X', X, 'beta_dc', beta, 'timelimits', timelimits, 'srate', srate);
            m.data = (Xdc * flat).';
            m.owner = owner;
            m.anchors = anchors;
            m.none = false(1, npnts);
        end
    end
end
