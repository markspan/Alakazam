classdef EyeEegCovariatesTest < matlab.unittest.TestCase
%EYEEEGCOVARIATESTEST  Reading EYE-EEG's eye-movement measures off EEG.event.
%
%   The fixture is an EEG.event list shaped the way EYE-EEG's
%   detecteyemovements leaves one: the experiment's own triggers, saccade
%   events carrying sac_* measures, and fixation events carrying both their
%   own fix_* measures and the sac_* properties of the saccade that produced
%   them (EYE-EEG has written those onto fixations since September 2021).
%   Fields a given event type does not have are empty on that event, which is
%   what a mixed event list looks like in MATLAB and the reason the reader
%   cannot simply concatenate a field.
%
%   THE THREE THINGS WORTH TESTING are the ones that would be silently wrong
%   rather than loudly broken:
%     - duration arrives in SAMPLES and must be converted, or a
%       fixation-duration predictor means different things in two recordings
%       at different sampling rates;
%     - sac_angle is CIRCULAR and must be marked as such, or a spline fits a
%       discontinuity at the wrap-around that the data does not have;
%     - a recording that never went through EYE-EEG has to answer "nothing
%       here" rather than fail, since callers will ask before they know.
%
%   Run with: runtests('tests/EyeEegCovariatesTest.m').
%
%   See also UNFOLD.EYEEEGCOVARIATES.

    properties (Constant)
        Srate = 500
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Transformations')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function everyEyeMovementBecomesOneRow(testCase)
            EEG = EyeEegCovariatesTest.recording();

            covariates = Unfold.eyeEegCovariates(EEG);

            testCase.verifyEqual(height(covariates), 4, ...
                'Two saccades and two fixations, and none of the triggers.');
            testCase.verifyEqual(covariates.eventType', {'saccade', 'fixation', 'saccade', 'fixation'});
            testCase.verifyEqual(covariates.eventIndex', [2 3 5 6], ...
                'eventIndex points back at the row in EEG.event it came from.');
            testCase.verifyEqual(covariates.latency', [120 140 320 350]);
        end

        function durationIsConvertedFromSamplesToMilliseconds(testCase)
        %DURATIONISCONVERTEDFROMSAMPLESTOMILLISECONDS  EYE-EEG writes the
        %   sample count; a model needs milliseconds, and the raw field is
        %   kept beside it so nothing is hidden.
            EEG = EyeEegCovariatesTest.recording();

            [covariates, meta] = Unfold.eyeEegCovariates(EEG);

            testCase.verifyEqual(covariates.duration', [10 150 12 200], ...
                'The raw field stays as EYE-EEG wrote it.');
            testCase.verifyEqual(covariates.durationMs', [20 300 24 400], 'AbsTol', 1e-9, ...
                'At 500 Hz, 150 samples is 300 ms.');
            testCase.verifyEqual(EyeEegCovariatesTest.unitOf(meta, 'durationMs'), 'ms');
            testCase.verifyEqual(EyeEegCovariatesTest.unitOf(meta, 'duration'), 'samples');
        end

        function saccadeAngleIsMarkedCircular(testCase)
            [~, meta] = Unfold.eyeEegCovariates(EyeEegCovariatesTest.recording());

            testCase.verifyEqual(EyeEegCovariatesTest.kindOf(meta, 'sac_angle'), 'circular');
            for linearOne = {'sac_amplitude', 'sac_vmax', 'fix_avgpos_x', 'durationMs'}
                testCase.verifyEqual(EyeEegCovariatesTest.kindOf(meta, linearOne{1}), 'linear', ...
                    sprintf('%s is not an angle.', linearOne{1}));
            end
        end

        function fixationsKeepTheirIncomingSaccadeProperties(testCase)
        %FIXATIONSKEEPTHEIRINCOMINGSACCADEPROPERTIES  This is what makes "the
        %   response to a fixation, given the saccade that brought the eye
        %   here" expressible, so the sac_* columns must survive on fixation
        %   rows rather than being treated as saccade-only.
            covariates = Unfold.eyeEegCovariates(EyeEegCovariatesTest.recording(), ...
                'EventTypes', {'fixation'});

            testCase.verifyEqual(height(covariates), 2);
            testCase.verifyEqual(covariates.sac_amplitude', [4.5 7.25], 'AbsTol', 1e-9);
            testCase.verifyEqual(covariates.fix_avgpos_x', [512 300], 'AbsTol', 1e-9);
        end

        function aMeasureThisRecordingLacksIsNotInvented(testCase)
        %AMEASURETHISRECORDINGLACKSISNOTINVENTED  EYE-EEG writes pupil size
        %   only when the tracker recorded it. A column of NaN would read as
        %   a failed measurement instead of a field that was never there.
            EEG = EyeEegCovariatesTest.recording();

            [covariates, meta] = Unfold.eyeEegCovariates(EEG);

            testCase.verifyFalse(ismember('fix_avgpupilsize', covariates.Properties.VariableNames));
            testCase.verifyFalse(any(strcmp({meta.name}, 'fix_avgpupilsize')));
        end

        function monocularEventTypesAreRecognised(testCase)
        %MONOCULAREVENTTYPESARERECOGNISED  A one-eye recording gets
        %   L_fixation/R_saccade instead of fixation/saccade, and must give
        %   the same table rather than an empty one.
            EEG = EyeEegCovariatesTest.recording();
            EEG.event(2).type = 'R_saccade';
            EEG.event(3).type = 'R_fixation';

            covariates = Unfold.eyeEegCovariates(EEG);

            testCase.verifyEqual(height(covariates), 4);
            testCase.verifyTrue(ismember('R_fixation', covariates.eventType));
        end

        function aDatasetWithoutEyeEegAnswersNothingHere(testCase)
            EEG = EyeEegCovariatesTest.recording();
            EEG.event = EEG.event([1 4]);          % the triggers only

            [covariates, meta] = Unfold.eyeEegCovariates(EEG);

            testCase.verifyEqual(height(covariates), 0);
            testCase.verifyEmpty(meta);
            testCase.verifyEqual(covariates.Properties.VariableNames, ...
                {'eventIndex', 'eventType', 'latency'}, ...
                'The empty answer still has a shape a caller can read.');
            testCase.verifyEqual(height(Unfold.eyeEegCovariates(struct('srate', 500))), 0, ...
                'A dataset with no event field at all is a question, not an error.');
        end
    end

    methods (Static)
        function EEG = recording()
        %RECORDING  An EYE-EEG-shaped event list: triggers, saccades and
        %   fixations, with each type carrying only the fields EYE-EEG gives
        %   it and the others left empty, as in a real mixed EEG.event.
            blank = struct('type', '', 'latency', [], 'duration', [], ...
                'sac_vmax', [], 'sac_amplitude', [], 'sac_angle', [], ...
                'sac_startpos_x', [], 'sac_startpos_y', [], 'sac_endpos_x', [], 'sac_endpos_y', [], ...
                'fix_avgpos_x', [], 'fix_avgpos_y', []);

            event = repmat(blank, 1, 6);
            event(1).type = 'S112';  event(1).latency = 100;

            event(2).type = 'saccade'; event(2).latency = 120; event(2).duration = 10;
            event(2).sac_vmax = 210.5; event(2).sac_amplitude = 4.5; event(2).sac_angle = 12;
            event(2).sac_startpos_x = 500; event(2).sac_startpos_y = 400;
            event(2).sac_endpos_x = 540; event(2).sac_endpos_y = 402;

            event(3).type = 'fixation'; event(3).latency = 140; event(3).duration = 150;
            event(3).fix_avgpos_x = 512; event(3).fix_avgpos_y = 401;
            event(3).sac_vmax = 210.5; event(3).sac_amplitude = 4.5; event(3).sac_angle = 12;
            event(3).sac_startpos_x = 500; event(3).sac_startpos_y = 400;
            event(3).sac_endpos_x = 540; event(3).sac_endpos_y = 402;

            event(4).type = 'S122'; event(4).latency = 300;

            event(5).type = 'saccade'; event(5).latency = 320; event(5).duration = 12;
            event(5).sac_vmax = 305.0; event(5).sac_amplitude = 7.25; event(5).sac_angle = 358;
            event(5).sac_startpos_x = 540; event(5).sac_startpos_y = 402;
            event(5).sac_endpos_x = 300; event(5).sac_endpos_y = 399;

            event(6).type = 'fixation'; event(6).latency = 350; event(6).duration = 200;
            event(6).fix_avgpos_x = 300; event(6).fix_avgpos_y = 399;
            event(6).sac_vmax = 305.0; event(6).sac_amplitude = 7.25; event(6).sac_angle = 358;
            event(6).sac_startpos_x = 540; event(6).sac_startpos_y = 402;
            event(6).sac_endpos_x = 300; event(6).sac_endpos_y = 399;

            EEG = struct('srate', EyeEegCovariatesTest.Srate, 'DataFormat', 'CONTINUOUS', ...
                'event', event);
        end

        function kind = kindOf(meta, name)
            hit = strcmp({meta.name}, name);
            assert(any(hit), 'No metadata for %s', name);
            kind = meta(hit).kind;
        end

        function unit = unitOf(meta, name)
            hit = strcmp({meta.name}, name);
            assert(any(hit), 'No metadata for %s', name);
            unit = meta(hit).unit;
        end
    end
end
