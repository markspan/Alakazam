classdef PhotodiodePreviewTest < matlab.unittest.TestCase
%PHOTODIODEPREVIEWTEST  What the Photodiode dialog draws, and that
%   SignalView draws it the way the preview intends.
%
%   The picture is the argument the dialog makes: a detector that reports a
%   plausible median lag while marking the wrong samples is exactly what a
%   preview exists to expose. The assembly of that picture is a plain
%   function over vectors (photodiodePreview), so it can be checked here
%   without opening a window, and the two SignalView features it leans on
%   are checked against a real view.
%
%   Run with: runtests('tests/PhotodiodePreviewTest.m').

    properties (Constant)
        Srate = 500
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            here = fileparts(mfilename('fullpath'));
            root = fileparts(here);
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Views')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Support')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations', 'Photodiode')));
        end
    end

    methods (Test)
        function everyOnsetIsMarked(testCase)
            [signal, onsets, events, pairs] = testCase.scenario();

            preview = photodiodePreview(signal, testCase.Srate, onsets, events, pairs, 'diode');
            types = string({preview.event.type});

            testCase.verifyEqual(sum(types == "diode"), numel(onsets), ...
                'Every detected onset should appear as its own mark.');
        end

        function theTriggersAreKeptAsTheyWere(testCase)
        %THETRIGGERSAREKEPTASTHEYWERE  A trigger is drawn as a line, and a
        %   line is an event with no duration. Giving the trigger the lag as
        %   its duration would turn its own line into a band and lose it.
            [signal, onsets, events, pairs] = testCase.scenario();

            preview = photodiodePreview(signal, testCase.Srate, onsets, events, pairs, 'diode');

            for k = 1:numel(events)
                match = find([preview.event.latency] == events(k).latency & ...
                    strcmp({preview.event.type}, events(k).type), 1);
                testCase.assertNotEmpty(match, ...
                    sprintf('Trigger %s is missing from the preview.', events(k).type));
                testCase.verifyEqual(preview.event(match).duration, 0, ...
                    'A trigger must stay a line, not become a band.');
            end
        end

        function eachPairBecomesABandFromTriggerToOnset(testCase)
        %EACHPAIRBECOMESABANDFROMTRIGGERTOONSET  The width of the band is
        %   the measurement. If it started anywhere but the trigger, or
        %   ended anywhere but the onset, the picture would disagree with
        %   the number in the summary underneath it.
            [signal, onsets, events, pairs] = testCase.scenario();

            preview = photodiodePreview(signal, testCase.Srate, onsets, events, pairs, 'diode');
            bands = preview.event([preview.event.duration] > 0);

            testCase.assertEqual(numel(bands), numel(pairs));
            for k = 1:numel(pairs)
                start = events(pairs(k).event).latency;
                match = bands([bands.latency] == start);
                testCase.assertNotEmpty(match, 'A pair produced no band at its trigger.');
                testCase.verifyEqual(match(1).duration, pairs(k).onset - start, ...
                    'The band should end at the onset it was paired with.');
            end
        end

        function theBandIsLabelledWithItsOwnLag(testCase)
            [signal, onsets, events, pairs] = testCase.scenario();

            preview = photodiodePreview(signal, testCase.Srate, onsets, events, pairs, 'diode');
            bands = preview.event([preview.event.duration] > 0);

            testCase.verifySubstring(bands(1).type, 'ms');
            testCase.verifySubstring(bands(1).type, sprintf('%.0f', pairs(1).lagMs));
        end

        function theOnsetsAreDistinguishableFromTheTriggers(testCase)
        %THEONSETSAREDISTINGUISHABLEFROMTHETRIGGERS  Both are point events,
        %   so without a style rule they arrive as one indivisible blue and
        %   the reader cannot see which mark the detector contributed.
            [signal, onsets, events, pairs] = testCase.scenario();

            [~, styleFor] = photodiodePreview(signal, testCase.Srate, onsets, events, pairs, 'diode');

            testCase.verifyNotEmpty(styleFor('diode'));
            testCase.verifyEmpty(styleFor('S 1'), ...
                'A trigger should get no opinion, and fall through to the default.');
        end

        function theDiodeLabelIsLiftedClearOfTheTrigger(testCase)
        %THEDIODELABELISLIFTEDCLEAROFTHETRIGGER  A diode onset sits one
        %   display lag after its trigger, which is tens of milliseconds.
        %   With both labels at the bottom of the axes the later one covers
        %   the earlier, and the one it covers is the trigger code, which is
        %   the value being checked.
        %
        %   The middle rather than the top, and the exact value is pinned
        %   because it is constrained rather than arbitrary: the trigger has
        %   the bottom and the lag band draws its own label at the top of
        %   the axes (see @label), so the top was tried first and the two
        %   labels overlapped there instead. Confirmed by rendering it and
        %   looking, which is the only way this kind of collision shows up.
            [signal, onsets, events, pairs] = testCase.scenario();

            [~, styleFor] = photodiodePreview(signal, testCase.Srate, onsets, events, pairs, 'diode');
            diode = styleFor('diode');

            testCase.assertTrue(isfield(diode, 'LabelVerticalAlignment'));
            testCase.verifyEqual(diode.LabelVerticalAlignment, 'middle', ...
                'The diode label should sit clear of both the trigger and the band.');
        end

        function eventsAreInTimeOrder(testCase)
            [signal, onsets, events, pairs] = testCase.scenario();

            preview = photodiodePreview(signal, testCase.Srate, onsets, events, pairs, 'diode');

            testCase.verifyEqual([preview.event.latency], sort([preview.event.latency]));
        end

        function aRecordingWithNoTriggersStillDraws(testCase)
        %ARECORDINGWITHNOTRIGGERSSTILLDRAWS  Importing onsets as events is a
        %   supported mode, and in it there may be nothing to pair against.
            signal = testCase.scenario();

            preview = photodiodePreview(signal, testCase.Srate, [100 200]);

            testCase.verifyEqual(numel(preview.event), 2);
            testCase.verifyEqual(numel(preview.times), numel(signal));
        end
    end

    methods (Test, TestTags = {'Slow'})
        function signalViewDrawsABandOfTheRightWidth(testCase)
        %SIGNALVIEWDRAWSABANDOFTHERIGHTWIDTH  The bug this pins. An event's
        %   duration is in samples, and SignalView positions it on a time
        %   axis whose unit is whatever the caller's time vector uses. It
        %   used to convert with 1/srate, which is seconds, so against the
        %   millisecond axis the application actually passes, every band was
        %   drawn a thousand times too narrow to see.
            [signal, onsets, events, pairs] = testCase.scenario();
            preview = photodiodePreview(signal, testCase.Srate, onsets, events, pairs, 'diode');

            % In milliseconds, which is what an EEGLAB recording carries.
            inMs = preview;
            inMs.times = preview.times * 1000;

            fig = uifigure('Visible', 'off', 'Position', [100 100 900 500]);
            testCase.addTeardown(@() delete(fig));
            view = SignalView(fig, inMs.times, inMs, 'FitWholeRecording', true);

            expectedMs = pairs(1).lagMs;
            widths = view.Overlay.AreaDur;

            testCase.assertNotEmpty(widths, 'No band reached the view at all.');
            testCase.verifyEqual(widths(1), expectedMs, 'RelTol', 1e-6, ...
                'The band should be as wide as the lag, in the axis''s own unit.');
        end

        function signalViewColoursTheOnsetsDifferently(testCase)
            [signal, onsets, events, pairs] = testCase.scenario();
            [preview, styleFor] = photodiodePreview(signal, testCase.Srate, ...
                onsets, events, pairs, 'diode');

            fig = uifigure('Visible', 'off', 'Position', [100 100 900 500]);
            testCase.addTeardown(@() delete(fig));
            view = SignalView(fig, preview.times, preview, ...
                'FitWholeRecording', true, 'EventStyleFcn', styleFor);

            lines = findobj(view.Axes, 'Type', 'ConstantLine');
            testCase.assertNotEmpty(lines, 'No event lines were drawn.');

            colours = unique(round(vertcat(lines.Color) * 1000) / 1000, 'rows');
            testCase.verifyGreaterThan(size(colours, 1), 1, ...
                'Triggers and diode onsets were drawn in the same colour.');

            % And the labels are not all in one place, which is what makes a
            % trigger readable next to the onset that answered it.
            alignments = unique(string({lines.LabelVerticalAlignment}));
            testCase.verifyGreaterThan(numel(alignments), 1, ...
                'Every label was drawn at the same height, so they overlap.');
        end
    end

    methods (Access = private)
        function [signal, onsets, events, pairs] = scenario(testCase)
        %SCENARIO  Four trials, each a trigger followed 20 ms later by a
        %   patch, which is the shape the whole transformation is about.
            srate = testCase.Srate;
            n = 10 * srate;
            signal = zeros(1, n);

            triggerAt = round((1:4) * 2 * srate);
            lagSamples = round(0.020 * srate);
            onsets = triggerAt + lagSamples;

            for k = 1:numel(onsets)
                signal(onsets(k):onsets(k) + round(0.1 * srate)) = 1000;
            end

            events = struct('type', {}, 'latency', {});
            for k = 1:numel(triggerAt)
                events(k) = struct('type', sprintf('S %d', k), 'latency', triggerAt(k));
            end

            pairs = struct('onset', {}, 'event', {}, 'lagMs', {});
            for k = 1:numel(onsets)
                pairs(k) = struct('onset', onsets(k), 'event', k, ...
                    'lagMs', lagSamples / srate * 1000);
            end
        end
    end
end
