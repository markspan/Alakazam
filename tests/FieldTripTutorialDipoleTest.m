classdef (TestTags = {'Slow'}) FieldTripTutorialDipoleTest < matlab.unittest.TestCase
%FIELDTRIPTUTORIALDIPOLETEST  Dipole Fit against FieldTrip's own dipole
%   fitting tutorial, on the tutorial's data and head model.
%
%   FieldTrip's tutorial (tutorial/source/dipolefitting, from the NatMEG 2014
%   workshop) fits a pair of dipoles, mirrored across the midline, to the
%   auditory N100 of an oddball experiment, 80 to 110 ms, in a three-shell BEM
%   made from the subject's own MRI. Here the tutorial's recipe is run as
%   published, and Alakazam's fit (dipoleFitWindow, what DipoleFit does for
%   each bin) is run on the same average, electrodes and head model: they
%   must find the same pair with the same residual variance. Both call
%   ft_dipolefitting, so a difference is a difference in how Alakazam calls
%   it: the window, the units, the model, the grid, the optimiser, the
%   residual variance over the window.
%
%   TWO DEPARTURES FROM THE RECIPE, both for the same reason: as published
%   it no longer does what it says with FieldTrip 20260812.
%     The grid. The recipe asks for resolution 1 with unit 'cm', but
%       ft_dipolefitting never passes cfg.unit on to the grid
%       (ft_checkconfig's createsubcfg does not move 'unit' into
%       cfg.sourcemodel, although ft_dipolefitting's comment says it does),
%       so the spacing is read in the head model's millimetres: a 1 mm grid
%       of about 1.7 million pairs, hours of scanning. The 1 cm grid the
%       tutorial means is resolution 10 here, which is also how Alakazam
%       gives it (in the head model's unit).
%     The optimiser. FieldTrip's own choice, fminunc wherever MATLAB
%       reports the Optimization Toolbox, cannot run on the machine this was
%       written on (a shared fminunc without that toolbox's message
%       catalog), and FieldTrip then returns the grid search's starting
%       point, [+-35 -15 55] mm, with no residual variance. Both sides are
%       therefore run with fminsearch, FieldTrip's documented
%       cfg.dipfit.optimfun, which is DipoleFit's Optimiser setting.
%   With both, the two find the pair at [+-32.57 -11.86 51.58] mm (the
%   subject's head coordinates) with a residual variance of 0.313, to the
%   last digit (8 October 2026).
%
%   NOT A CHECK OF ANATOMY BY TEMPLATE. DipoleFit itself always uses
%   FieldTrip's template head, and these channels (EEG001 to EEG128) have no
%   10-5 names to place them on it, so DipoleFit cannot be run end to end on
%   this recording; its own test (DipoleFitTest) covers that route on
%   simulated data.
%
%   THE DATA: timelock_eeg.mat and headmodel_eeg.mat (48 MB) from
%   https://download.fieldtriptoolbox.org/workshop/natmeg2014/dipolefitting/,
%   in FieldTrip/natmeg2014/dipolefitting under the data folder: the
%   ALAKAZAM_DATA environment variable, the repository's Data folder, or
%   D:\data. The test skips without them and never downloads them.
%
%   See also DIPOLEFIT, DIPOLEFITWINDOW, DIPOLEFITTEST.

    properties (Constant)
        Files = {'timelock_eeg.mat', 'headmodel_eeg.mat'}
        Url = 'https://download.fieldtriptoolbox.org/workshop/natmeg2014/dipolefitting/'
    end

    properties
        Timelock
        HeadModel
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Transformations', 'DipoleFit')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end

        function requireFieldTrip(testCase)
            FieldTripFixtures.require(testCase);
        end

        function loadTheTutorialData(testCase)
            folder = FieldTripFixtures.dataFolder(fullfile('FieldTrip', 'natmeg2014', 'dipolefitting'), ...
                testCase.Files);
            testCase.assumeNotEmpty(folder, sprintf(['FieldTrip''s dipole fitting tutorial ' ...
                'data (%s) are not under FieldTrip/natmeg2014/dipolefitting in ALAKAZAM_DATA, ' ...
                'Data or D:\\data; they are at %s.'], strjoin(testCase.Files, ', '), testCase.Url));
            loaded = load(fullfile(folder, 'timelock_eeg.mat'), 'timelock_eeg_all');
            testCase.Timelock = loaded.timelock_eeg_all;
            loaded = load(fullfile(folder, 'headmodel_eeg.mat'), 'headmodel_eeg');
            testCase.HeadModel = loaded.headmodel_eeg;
        end
    end

    methods (Test)
        function findsTheTutorialsMirroredPair(testCase)
            tl = testCase.Timelock;

            % FieldTrip's tutorial, as published but for the grid's spacing
            % and the optimiser (see above).
            recipe = struct('latency', [0.080 0.110], 'numdipoles', 2, 'symmetry', 'x', ...
                'resolution', 10, 'gridsearch', 'yes', ...
                'headmodel', testCase.HeadModel, 'senstype', 'eeg', 'channel', 'all', ...
                'feedback', 'no', 'dipfit', struct('optimfun', 'fminsearch'));
            source = FieldTripFixtures.quietly(@() ft_dipolefitting(recipe, tl));
            expected = ft_scalingfactor(source.dip.unit, 'mm') * source.dip.pos;
            residual = source.Vdata - source.Vmodel;
            expectedRv = sum(residual(:) .^ 2) / sum(source.Vdata(:) .^ 2);

            % Alakazam's, on the same average, electrodes and head model, with
            % the electrodes in the head model's millimetres as the template's are.
            opts = struct('WindowStart', 80, 'WindowStop', 110, 'Model', 'Mirrored pair', ...
                'GridResolution', 10, 'Optimiser', 'fminsearch');
            fit = FieldTripFixtures.quietly(@() dipoleFitWindow(tl.avg, tl.time * 1000, tl.label, ...
                ft_convert_units(tl.elec, 'mm'), testCase.HeadModel, opts, 'all'));

            [~, e] = sort(expected(:, 1));
            [~, a] = sort(fit.pos(:, 1));
            apart = vecnorm(expected(e, :) - fit.pos(a, :), 2, 2);
            testCase.verifyLessThan(max(apart), 0.5, sprintf(['The tutorial''s pair is at [%s] mm, ' ...
                'Alakazam''s at [%s] mm.'], num2str(expected(e, :), '%.2f '), num2str(fit.pos(a, :), '%.2f ')));
            testCase.verifyEqual(fit.rv, expectedRv, 'AbsTol', 1e-4, ...
                'The residual variance over the window.');
            testCase.verifyEqual(fit.time([1 end]), [80 110], 'AbsTol', 2, 'The window, in ms.');
        end
    end
end
