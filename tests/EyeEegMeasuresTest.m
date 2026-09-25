classdef EyeEegMeasuresTest < matlab.unittest.TestCase
%EYEEEGMEASURESTEST  What Deconvolve offers as covariates on an EYE-EEG
%   recording, and what it says about each (Unfold.eyeEegMeasures, read
%   through Unfold.eventCovariates, which is what the dialog asks).
%
%   The fixture is an EEG.event list shaped the way EYE-EEG's
%   detecteyemovements leaves one: the experiment's own triggers, saccades
%   carrying sac_* measures, and fixations carrying their own fix_* measures
%   and the sac_* of the saccade that produced them. Fields a type does not
%   have are empty on its events, as in any mixed EEG.event.
%
%   THE THINGS WORTH TESTING are the ones that would be silently wrong:
%   sac_angle offered as if it were linear, a unit reported that is not
%   EYE-EEG's, or duration (a sample count) offered as a covariate.
%
%   Run with: runtests('tests/EyeEegMeasuresTest.m').
%
%   See also UNFOLD.EYEEEGMEASURES, UNFOLD.EVENTCOVARIATES.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Transformations')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function saccadeAngleIsOfferedAsCircular(testCase)
            found = Unfold.eventCovariates(EyeEegMeasuresTest.recording());

            angle = found(strcmp({found.name}, 'sac_angle'));
            testCase.assertNotEmpty(angle);
            testCase.verifyEqual(angle.kind, 'circular');
            testCase.verifyEqual(angle.unit, 'degrees');
        end

        function eyeEegMeasuresCarryTheirUnits(testCase)
            found = Unfold.eventCovariates(EyeEegMeasuresTest.recording());

            amplitude = found(strcmp({found.name}, 'sac_amplitude'));
            testCase.verifyEqual(amplitude.kind, 'linear');
            testCase.verifyEqual(amplitude.unit, 'degrees or pixels', ...
                'EYE-EEG converts only when it was given degperpixel, and nothing records whether it was.');
            testCase.verifyEqual(sort(amplitude.types), {'fixation', 'saccade'}, ...
                'Fixations carry their incoming saccade.');
        end

        function durationIsNotOffered(testCase)
        %DURATIONISNOTOFFERED  A sample count: a slope on it would mean
        %   something different at every sampling rate.
            found = Unfold.eventCovariates(EyeEegMeasuresTest.recording());

            testCase.verifyFalse(ismember('duration', {found.name}));
            testCase.verifyFalse(ismember('latency', {found.name}));
        end

        function aFieldEyeEegDoesNotWriteIsLinearWithNoUnit(testCase)
            EEG = EyeEegMeasuresTest.recording();
            for k = 1:numel(EEG.event)
                EEG.event(k).rating = k;
            end

            found = Unfold.eventCovariates(EEG);

            rating = found(strcmp({found.name}, 'rating'));
            testCase.verifyEqual(rating.kind, 'linear');
            testCase.verifyEmpty(rating.unit, 'Nothing is known about it, so nothing is claimed.');
        end

        function aRecordingWithoutEyeMovementsAnswersNothingHere(testCase)
            EEG = EyeEegMeasuresTest.recording();
            EEG.event = EEG.event([1 4]);          % the triggers only

            testCase.verifyEmpty(Unfold.eventCovariates(EEG));
            testCase.verifyEmpty(Unfold.eventCovariates(struct('srate', 500)), ...
                'A dataset with no event field at all is a question, not an error.');
        end

        function everyCatalogueEntryIsComplete(testCase)
            catalogue = Unfold.eyeEegMeasures();

            testCase.verifyEqual(numel(unique({catalogue.name})), numel(catalogue));
            testCase.verifyTrue(all(ismember({catalogue.kind}, {'linear', 'circular'})));
            for k = 1:numel(catalogue)
                testCase.verifyNotEmpty(catalogue(k).unit, catalogue(k).name);
                testCase.verifyNotEmpty(catalogue(k).description, catalogue(k).name);
            end
        end
    end

    methods (Static)
        function EEG = recording()
        %RECORDING  Triggers, two saccades and two fixations, each type
        %   carrying only the fields EYE-EEG gives it.
            blank = struct('type', '', 'latency', [], 'duration', [], ...
                'sac_vmax', [], 'sac_amplitude', [], 'sac_angle', [], ...
                'fix_avgpos_x', [], 'fix_avgpos_y', []);
            event = repmat(blank, 1, 6);
            event(1).type = 'S112';     event(1).latency = 100;
            event(2).type = 'saccade';  event(2).latency = 120; event(2).duration = 10;
            event(2).sac_vmax = 210.5;  event(2).sac_amplitude = 4.5;  event(2).sac_angle = 12;
            event(3).type = 'fixation'; event(3).latency = 140; event(3).duration = 150;
            event(3).fix_avgpos_x = 512; event(3).fix_avgpos_y = 401;
            event(3).sac_vmax = 210.5;  event(3).sac_amplitude = 4.5;  event(3).sac_angle = 12;
            event(4).type = 'S122';     event(4).latency = 300;
            event(5).type = 'saccade';  event(5).latency = 320; event(5).duration = 12;
            event(5).sac_vmax = 305.0;  event(5).sac_amplitude = 7.25; event(5).sac_angle = 358;
            event(6).type = 'fixation'; event(6).latency = 350; event(6).duration = 200;
            event(6).fix_avgpos_x = 300; event(6).fix_avgpos_y = 399;
            event(6).sac_vmax = 305.0;  event(6).sac_amplitude = 7.25; event(6).sac_angle = 358;
            EEG = struct('srate', 500, 'DataFormat', 'CONTINUOUS', 'event', event);
        end
    end
end
