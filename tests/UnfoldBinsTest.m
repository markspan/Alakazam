classdef UnfoldBinsTest < matlab.unittest.TestCase
%UNFOLDBINSTEST  Binning a continuous recording by deconvolution instead of
%   by epoch-and-average: Unfold.binModel and Unfold.fitBins.
%
%   THE TEST THAT MATTERS IS THE RECOVERY ONE. Everything else here checks
%   plumbing, which is worth checking but proves nothing about whether the
%   method works. So the fixture is a continuous recording built from two
%   KNOWN waveforms at known event times, overlapping each other on purpose,
%   and the assertion is that the fit returns the waveforms that went in,
%   AND that a plain average of the same events does not. If deconvolution
%   were not doing anything, both would be equally wrong.
%
%   The overlap is built the way it arises in real data: the second event
%   follows the first at a lag that varies from trial to trial. That varying
%   lag is exactly what makes the two responses separable, which is why the
%   model builder warns when a pair has no jitter at all.
%
%   THE MAPPING TESTS NEED NO TOOLBOX, and run everywhere: bins to event
%   types, combination bins left out of the model, unbinned events kept as
%   nuisance, an empty bin noted rather than fatal, and the two designs that
%   cannot be identified refused or flagged. The fitting tests assume Unfold
%   is installed and skip cleanly when it is not, exactly as the FieldTrip
%   tests do, since a test must never trigger the consent-gated download.
%
%   Run with: runtests('tests/UnfoldBinsTest.m').
%
%   See also UNFOLD.BINMODEL, UNFOLD.FITBINS, AVERAGE, DEFINEBINS.

    properties (Constant)
        Srate = 100
        WindowMs = [-200 800]
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Support')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function eachOrdinaryBinBecomesOneEventType(testCase)
            EEG = UnfoldBinsTest.recording();

            plan = Unfold.binModel(EEG);

            testCase.verifyEqual(plan.binLabels, {'Frequent', 'Rare'});
            testCase.verifyEqual(plan.binTypes, {'bin_Frequent', 'bin_Rare'});
            testCase.verifyEqual(numel(plan.formulas), numel(plan.eventTypes), ...
                'One formula per event type, which uf_designmat requires.');
            testCase.verifyTrue(all(strcmp(plan.formulas, 'y ~ 1')), ...
                'A bin carries no covariate, so its rERP is an intercept.');
            testCase.verifyEqual(plan.binCounts, [numel(UnfoldBinsTest.frequentLatencies()), ...
                numel(UnfoldBinsTest.rareLatencies())]);
        end

        function eventsInNoBinAreModelledAsNuisance(testCase)
        %EVENTSINNOBINAREMODELLEDASNUISANCE  Overlap correction only removes
        %   the overlap that is modelled, so an unbinned event left out does
        %   not stop overlapping: it just stops being accounted for.
            EEG = UnfoldBinsTest.recording();

            withOthers = Unfold.binModel(EEG, 'OtherEvents', 'all');
            without = Unfold.binModel(EEG, 'OtherEvents', {});

            testCase.verifyEqual(withOthers.nuisanceTypes, {'evt_response'});
            testCase.verifyEmpty(without.nuisanceTypes);
            testCase.verifyEqual(numel(withOthers.eventTypes), 3);
            testCase.verifyEqual(numel(without.eventTypes), 2);
            testCase.verifyFalse(any(strcmp({withOthers.events.type}, 'boundary')), ...
                'A boundary marks an edit in the recording, not a response to model.');
        end

        function everyUnbinnedCodeIsListedWithItsCount(testCase)
        %EVERYUNBINNEDCODEISLISTEDWITHITSCOUNT  What the dialog shows the user
        %   to choose from. The count is the point: a code with three events
        %   costs a whole window of parameters for very little.
            EEG = UnfoldBinsTest.withProbes(UnfoldBinsTest.recording());

            plan = Unfold.binModel(EEG);

            testCase.verifyEqual({plan.unbinnedCodes.code}, {'response', 'probe'});
            testCase.verifyEqual([plan.unbinnedCodes.n], [90 3]);
            testCase.verifyEqual([plan.unbinnedCodes.modelled], [true true], ...
                'By default every code in no bin is modelled.');
            testCase.verifyEqual(plan.nuisanceTypes, {'evt_response', 'evt_probe'});
        end

        function onlyTheChosenCodesAreModelled(testCase)
            EEG = UnfoldBinsTest.withProbes(UnfoldBinsTest.recording());

            plan = Unfold.binModel(EEG, 'OtherEvents', {'response'});

            testCase.verifyEqual(plan.nuisanceTypes, {'evt_response'});
            testCase.verifyFalse(any(strcmp({plan.events.type}, 'evt_probe')), ...
                'An unchosen code contributes no rows to the design.');
            testCase.verifyEqual([plan.unbinnedCodes.modelled], [true false], ...
                'It is still listed, so the user can see what was left out.');
            testCase.verifyTrue(any(contains(plan.notes, 'probe x3')), ...
                'A code left out is named, because its overlap is still in the result.');
        end

        function anEmptyChoiceModelsNone(testCase)
            EEG = UnfoldBinsTest.withProbes(UnfoldBinsTest.recording());

            plan = Unfold.binModel(EEG, 'OtherEvents', {});

            testCase.verifyEmpty(plan.nuisanceTypes);
            testCase.verifyEqual(numel(plan.unbinnedCodes), 2, 'Still listed, none ticked.');
        end

        function aChosenCodeAbsentHereIsNoted(testCase)
        %ACHOSENCODEABSENTHEREISNOTED  What a replay meets on a recording
        %   that lacks a code chosen on another one.
            EEG = UnfoldBinsTest.recording();

            plan = Unfold.binModel(EEG, 'OtherEvents', {'response', 'probe'});

            testCase.verifyEqual(plan.nuisanceTypes, {'evt_response'});
            testCase.verifyTrue(any(contains(plan.notes, 'probe')));
        end

        function aStoredChoiceIsReadOneWayEverywhere(testCase)
        %ASTOREDCHOICEISREADONEWAYEVERYWHERE  Unfold.otherEventsChoice is
        %   what Deconvolve, its dialog and binModel all ask, so these are
        %   the cases a stored template can present: the older true/false
        %   field, both fields at once, and the shapes JSON brings back.
            choice = @Unfold.otherEventsChoice;

            testCase.verifyEqual(choice(struct('modelOtherEvents', false)), {}, ...
                'The older field''s false still means none.');
            testCase.verifyEqual(choice(struct('modelOtherEvents', true)), 'all');
            testCase.verifyEqual(choice(struct('modelOtherEvents', false, 'otherEvents', {{'probe'}})), ...
                {'probe'}, 'Given both, the per-code choice decides.');
            testCase.verifyEqual(choice(struct('otherEvents', [])), {}, ...
                'An empty list, as JSON returns it, is none rather than the default.');
            testCase.verifyEqual(choice(struct('otherEvents', 'probe')), {'probe'}, ...
                'One code, as JSON returns a list of one, is that code.');
            testCase.verifyEqual(choice([]), 'all', 'Nothing stored is the default.');
        end

        function combinationBinsAreNotPredictors(testCase)
        %COMBINATIONBINSARENOTPREDICTORS  A difference bin has no events of
        %   its own; asking the model to estimate a response to it would be
        %   asking for a response to nothing.
            EEG = UnfoldBinsTest.recording('WithComboBin', true);

            plan = Unfold.binModel(EEG);

            testCase.verifyEqual(plan.comboBins, 3);
            testCase.verifyEqual(plan.binLabels, {'Frequent', 'Rare'});
            testCase.verifyFalse(any(contains(plan.eventTypes, 'Rare_minus')));
        end

        function twoBinsOverTheSameEventsAreRefused(testCase)
            EEG = UnfoldBinsTest.recording();
            for k = 1:numel(EEG.event)                    % every Rare event also Frequent
                if any(EEG.event(k).bini == 2)
                    EEG.event(k).bini = [1 2];
                end
            end
            for k = 1:numel(EEG.event)
                if isequal(EEG.event(k).bini, 1)
                    EEG.event(k).bini = [1 2];
                end
            end

            testCase.verifyError(@() Unfold.binModel(EEG), 'Alakazam:Unfold:CollinearBins');
        end

        function aPairWithNoJitterIsFlagged(testCase)
        %APAIRWITHNOJITTERISFLAGGED  Deconvolution separates responses by
        %   seeing them at different offsets. Where every event of one bin is
        %   the same distance from one of the other, in both directions,
        %   there are no different offsets to see and the fit returns a pair
        %   that cannot be attributed separately, without failing.
        %
        %   A fixed lag in ONE direction only is not this case, and must not
        %   be flagged: the events with no partner are exactly what lets the
        %   fit separate them, which is why the default fixture (a rare event
        %   on every third frequent one) is a perfectly good design.
            EEG = UnfoldBinsTest.recording('FixedLag', true);

            plan = Unfold.binModel(EEG);

            testCase.verifyNotEmpty(plan.notes);
            testCase.verifySubstring(strjoin(plan.notes, ' '), 'not identified apart');
        end

        function anEmptyBinIsNotedRatherThanFatal(testCase)
            EEG = UnfoldBinsTest.recording();
            for k = 1:numel(EEG.event)
                EEG.event(k).bini(EEG.event(k).bini == 2) = [];
            end

            plan = Unfold.binModel(EEG);

            testCase.verifyEqual(plan.binCounts, [numel(UnfoldBinsTest.frequentLatencies()) 0]);
            testCase.verifySubstring(strjoin(plan.notes, ' '), '"Rare" has no events');
            testCase.verifyEqual(plan.eventTypes(1:1), {'bin_Frequent'});
        end

        function epochedDataIsRefusedWithTheReasonWhy(testCase)
            EEG = UnfoldBinsTest.recording();
            EEG.DataFormat = 'EPOCHED';

            message = '';
            try
                Unfold.binModel(EEG);
            catch err
                testCase.verifyEqual(err.identifier, 'Alakazam:Unfold:NeedsContinuous');
                message = err.message;
            end
            testCase.assertNotEmpty(message, 'Epoched data has to be refused, not fitted.');
            testCase.verifySubstring(message, 'overlap');
        end
    end

    methods (Test, TestTags = {'External'})
        function itRecoversOverlappingResponsesThatAveragingSmears(testCase)
            testCase.assumeTrue(Unfold.isAvailable(), ...
                'The Unfold toolbox is not installed, so the fit cannot be exercised.');
            [EEG, truth] = UnfoldBinsTest.recording();

            fitted = Unfold.fitBins(EEG, 'WindowMs', UnfoldBinsTest.WindowMs, ...
                'ArtifactThresholdUv', 0);

            keep = fitted.times >= 0 & fitted.times <= 400;
            for b = 1:2
                estimate = reshape(fitted.data(1, keep, b), 1, []);
                target = reshape(truth.waveform(b, :), 1, []);
                naive = UnfoldBinsTest.naiveAverage(EEG, b, fitted.times);
                naive = reshape(naive(keep), 1, []);

                testCase.verifyGreaterThan(corr(estimate(:), target(:)), 0.98, ...
                    sprintf('Bin %d: the deconvolved waveform should be the one that went in.', b));
                testCase.verifyLessThan(max(abs(estimate - target)), 0.5, ...
                    sprintf('Bin %d: and at the right amplitude.', b));
                testCase.verifyLessThan(max(abs(estimate - target)), max(abs(naive - target)), ...
                    sprintf(['Bin %d: deconvolution has to beat the plain average, or it is ' ...
                             'not doing anything.'], b));
            end
        end

        function theResultIsShapedLikeAnAverage(testCase)
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            EEG = UnfoldBinsTest.recording('WithComboBin', true);

            fitted = Unfold.fitBins(EEG, 'WindowMs', UnfoldBinsTest.WindowMs, ...
                'ArtifactThresholdUv', 0);

            testCase.verifyEqual(char(string(fitted.DataFormat)), 'Averaged');
            testCase.verifyEqual(size(fitted.data), [2 numel(fitted.times) 3], ...
                'channels x samples x bins, the combination bin included.');
            testCase.verifyEqual(size(fitted.stErr), size(fitted.data), ...
                'AverageView indexes stErr without checking, so it has to be there.');
            testCase.verifyEqual(fitted.trials, 1);
            testCase.verifyEqual([fitted.bindesc(1:2).n], ...
                [numel(UnfoldBinsTest.frequentLatencies()), numel(UnfoldBinsTest.rareLatencies())]);
            testCase.verifyEqual(fitted.times(1), UnfoldBinsTest.WindowMs(1), 'AbsTol', 1000 / UnfoldBinsTest.Srate);
            testCase.verifyFalse(fitted.etc.alz.unfold.hasStandardError, ...
                'The provenance has to say the error band is not one.');
        end

        function aDifferenceBinIsTheDifferenceOfTheFittedWaveforms(testCase)
            testCase.assumeTrue(Unfold.isAvailable(), 'The Unfold toolbox is not installed.');
            EEG = UnfoldBinsTest.recording('WithComboBin', true);

            fitted = Unfold.fitBins(EEG, 'WindowMs', UnfoldBinsTest.WindowMs, ...
                'ArtifactThresholdUv', 0);

            testCase.verifyEqual(fitted.data(:, :, 3), ...
                fitted.data(:, :, 2) - fitted.data(:, :, 1), 'AbsTol', 1e-9, ...
                'Subtracting two fitted waveforms is what subtracting two averages was.');
        end
    end

    methods (Static)
        function latencies = frequentLatencies()
            rng(7);
            latencies = round(linspace(300, 19000, 90) + 40 * randn(1, 90));
        end

        function latencies = rareLatencies()
        %RARELATENCIES  Each rare event follows a frequent one at a lag that
        %   varies from trial to trial: heavy overlap, but identifiable.
            rng(11);
            base = UnfoldBinsTest.frequentLatencies();
            base = base(1:3:end);
            latencies = base + round(20 + 25 * rand(1, numel(base)));
        end

        function [EEG, truth] = recording(varargin)
        %RECORDING  A continuous dataset built from two known waveforms.
            parsed = inputParser();
            parsed.addParameter('WithComboBin', false);
            parsed.addParameter('FixedLag', false);
            parsed.parse(varargin{:});

            srate = UnfoldBinsTest.Srate;
            npnts = 20000;
            t = (0:round(0.4 * srate)) / srate;               % 0 to 400 ms
            waveform = [ 5 * sin(pi * t / 0.4) .* exp(-t / 0.25); ...
                        -3 * sin(pi * t / 0.4) .* exp(-t / 0.15)];

            frequent = UnfoldBinsTest.frequentLatencies();
            if parsed.Results.FixedLag
                rare = frequent + 30;    % one per frequent event, never varies:
                                         % the pair is then unidentifiable
            else
                rare = UnfoldBinsTest.rareLatencies();
            end
            responses = round(frequent + 60);                 % unbinned, overlapping too

            rng(3);
            data = 0.05 * randn(2, npnts);
            for k = frequent
                data = UnfoldBinsTest.addResponse(data, k, waveform(1, :));
            end
            for k = rare
                data = UnfoldBinsTest.addResponse(data, k, waveform(2, :));
            end
            for k = responses
                data = UnfoldBinsTest.addResponse(data, k, 0.8 * waveform(1, :));
            end

            event = struct('type', {}, 'latency', {}, 'bini', {});
            for k = frequent
                event(end + 1) = struct('type', 'stim', 'latency', k, 'bini', 1); %#ok<AGROW>
            end
            for k = rare
                event(end + 1) = struct('type', 'stim', 'latency', k, 'bini', 2); %#ok<AGROW>
            end
            for k = responses
                event(end + 1) = struct('type', 'response', 'latency', k, 'bini', []); %#ok<AGROW>
            end
            event(end + 1) = struct('type', 'boundary', 'latency', 1, 'bini', []);
            [~, order] = sort([event.latency]);
            event = event(order);

            bindesc = struct('index', {1, 2}, 'label', {'Frequent', 'Rare'}, 'combo', {[], []});
            if parsed.Results.WithComboBin
                bindesc(3) = struct('index', 3, 'label', 'Rare_minus_Frequent', ...
                    'combo', struct('bin', {2, 1}, 'coeff', {1, -1}));
            end

            EEG = struct('data', data, 'srate', srate, 'pnts', npnts, 'trials', 1, ...
                'nbchan', 2, 'xmin', 0, 'xmax', (npnts - 1) / srate, ...
                'times', (0:npnts - 1) / srate * 1000, 'DataFormat', 'CONTINUOUS', ...
                'chanlocs', struct('labels', {'Cz', 'Pz'}), 'event', event, 'bindesc', bindesc);
            truth = struct('waveform', waveform, 'frequent', frequent, 'rare', rare);
        end

        function EEG = withProbes(EEG)
        %WITHPROBES  Three stray events of a second unbinned code, the case
        %   the per-code choice exists for: a code too rare to be worth a
        %   window of parameters.
            for latency = [5003 11007 17011]
                EEG.event(end + 1) = struct('type', 'probe', 'latency', latency, 'bini', []);
            end
            [~, order] = sort([EEG.event.latency]);
            EEG.event = EEG.event(order);
        end

        function data = addResponse(data, latency, waveform)
            span = latency + (0:numel(waveform) - 1);
            keep = span >= 1 & span <= size(data, 2);
            data(:, span(keep)) = data(:, span(keep)) + waveform(keep);
        end

        function averaged = naiveAverage(EEG, bin, times)
        %NAIVEAVERAGE  What epoch-and-average would give for this bin: the
        %   comparison the recovery test is against.
            latencies = [];
            for k = 1:numel(EEG.event)
                if any(EEG.event(k).bini == bin)
                    latencies(end + 1) = EEG.event(k).latency; %#ok<AGROW>
                end
            end
            offsets = round(times / 1000 * EEG.srate);
            acc = zeros(1, numel(offsets));
            n = 0;
            for k = latencies
                span = k + offsets;
                if all(span >= 1 & span <= size(EEG.data, 2))
                    acc = acc + EEG.data(1, span);
                    n = n + 1;
                end
            end
            averaged = acc / max(n, 1);
        end
    end
end
