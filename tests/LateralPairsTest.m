classdef LateralPairsTest < matlab.unittest.TestCase
%LATERALPAIRSTEST  Matching each left electrode to its right-hemisphere
%   mirror, which is what makes a contralateral waveform definable.
%
%   Getting a pair backwards does not produce an error or an obviously wrong
%   figure: it produces a clean waveform of the opposite sign, which is the
%   worst failure available here. So these cases are mostly about the ways a
%   plausible shortcut would get one wrong.
%
%   Run with: runtests('tests/LateralPairsTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations')));
        end
    end

    methods (Test)
        % --- geometry ---------------------------------------------------- %
        function mirroredPositionsPairUp(testCase)
            chanlocs = testCase.positioned( ...
                {'A', 'B', 'Mid', 'Bmirror', 'Amirror'}, ...
                [10 30 0; 20 50 0; 5 0 0; 20 -50 0; 10 -30 0]);

            r = TransTools.LateralPairs(chanlocs);

            testCase.verifyEqual(r.method, 'geometry');
            testCase.verifyEqual(testCase.pairLabels(r), {'A/Amirror', 'B/Bmirror'});
            testCase.verifyEqual(r.midline, 3);
            testCase.verifyEmpty(r.unpaired);
        end

        function pairingIsNotByChannelOrder(testCase)
        %PAIRINGISNOTBYCHANNELORDER  The shortcut this exists to rule out.
        %   ANT's own standard_waveguard64_equidistant.elc lists every pair
        %   left-then-right except 3RD/3LD, which is inverted; pairing
        %   adjacent rows would swap contralateral for ipsilateral there, in
        %   a montage where no label would let anyone notice.
            chanlocs = testCase.positioned({'oneL', 'oneR', 'twoR', 'twoL'}, ...
                [40 20 0; 40 -20 0; 60 -35 0; 60 35 0]);

            r = TransTools.LateralPairs(chanlocs);

            byLabel = containers.Map(testCase.pairLabels(r), num2cell(1:numel(r.pairs)));
            testCase.assertTrue(byLabel.isKey('twoL/twoR'), ...
                'The inverted pair must still be found.');
            p = r.pairs(byLabel('twoL/twoR'));
            testCase.verifyEqual(p.left, 4, 'Left is the one at positive Y, whatever its row.');
            testCase.verifyEqual(p.right, 3);
        end

        function theNearestMirrorWinsRatherThanTheFirstFound(testCase)
        %THENEARESTMIRRORWINSRATHERTHANTHEFIRSTFOUND  A sweep in index order
        %   would let the first left electrode claim a right one that fits
        %   another left electrode far better, and then cascade.
            chanlocs = testCase.positioned({'near', 'far', 'farMirror', 'nearMirror'}, ...
                [50 20 0; 50 40 0; 50 -40 0; 50 -20 0]);

            r = TransTools.LateralPairs(chanlocs);

            testCase.verifyEqual(sort(testCase.pairLabels(r)), ...
                {'far/farMirror', 'near/nearMirror'});
        end

        function anElectrodeWithNoMirrorIsLeftUnpaired(testCase)
        %ANELECTRODEWITHNOMIRRORISLEFTUNPAIRED  Rather than matched to
        %   whatever is nearest: an EOG electrode has no contralateral
        %   counterpart, and inventing one would collapse it into a pair.
            chanlocs = testCase.positioned({'L', 'R', 'lonely'}, ...
                [30 25 0; 30 -25 0; 95 60 -10]);

            r = TransTools.LateralPairs(chanlocs);

            testCase.verifyEqual(testCase.pairLabels(r), {'L/R'});
            testCase.verifyEqual(r.unpaired, 3);
        end

        function theToleranceIsRelativeToTheMontageScale(testCase)
        %THETOLERANCEISRELATIVETOTHEMONTAGESCALE  chanlocs carries no unit,
        %   so a montage may be in mm, in cm, or on a unit sphere. A fixed
        %   millimetre tolerance would pair everything on a unit sphere and
        %   nothing in metres.
            labels = {'L', 'R', 'Mid'};
            mm = [30 25 0; 30 -25 0; 5 0 0];

            for scale = [0.001, 1, 1000]
                r = TransTools.LateralPairs(testCase.positioned(labels, mm * scale));
                testCase.verifyEqual(testCase.pairLabels(r), {'L/R'}, ...
                    sprintf('Failed at scale %g.', scale));
                testCase.verifyEqual(r.midline, 3, sprintf('Failed at scale %g.', scale));
            end
        end

        % --- labels ------------------------------------------------------ %
        function tenTwentyLabelsPairOddWithEven(testCase)
            r = TransTools.LateralPairs(testCase.unpositioned( ...
                {'F3', 'Fz', 'F4', 'PO7', 'PO8', 'P9', 'P10', 'O1', 'O2'}));

            testCase.verifyEqual(r.method, 'labels');
            testCase.verifyEqual(testCase.pairLabels(r), ...
                {'F3/F4', 'PO7/PO8', 'P9/P10', 'O1/O2'});
            testCase.verifyEqual(r.midline, 2);
        end

        function equidistantLabelsPairByTheirLandRLetter(testCase)
        %EQUIDISTANTLABELSPAIRBYTHEIRLANDRLETTER  An equidistant montage
        %   names electrodes by position in the array, not by anatomy, so
        %   odd/even numbering finds nothing: 1L pairs with 1R, and 2LB with
        %   2RB. Labels from ANT's waveguard64 equidistant montage.
            r = TransTools.LateralPairs(testCase.unpositioned( ...
                {'0Z', '1L', '1R', '1LB', '1RB', '10L', '10R', '4Z'}));

            testCase.verifyEqual(r.method, 'labels');
            testCase.verifyEqual(testCase.pairLabels(r), ...
                {'1L/1R', '1LB/1RB', '10L/10R'});
            testCase.verifyEqual(r.midline, [1 8]);
        end

        function aPartnerThatDoesNotExistIsNotInvented(testCase)
        %APARTNERTHATDOESNOTEXISTISNOTINVENTED  Both label rules predict a
        %   partner and then require it to be present, which is what makes
        %   each safe to try on a montage it was not meant for.
            r = TransTools.LateralPairs(testCase.unpositioned({'F3', 'PO7', '1L'}));

            testCase.verifyEmpty(r.pairs);
            testCase.verifyEqual(sort(r.unpaired), [1 2 3]);
        end

        % --- choosing between them --------------------------------------- %
        function geometryIsUsedWhenPositionsArePresent(testCase)
            positioned = testCase.positioned({'F3', 'F4'}, [30 25 0; 30 -25 0]);
            testCase.verifyEqual(TransTools.LateralPairs(positioned).method, 'geometry');
        end

        function labelsAreUsedWhenPositionsAreNot(testCase)
            testCase.verifyEqual( ...
                TransTools.LateralPairs(testCase.unpositioned({'F3', 'F4'})).method, 'labels');
        end

        function eitherMethodCanBeForced(testCase)
        %EITHERMETHODCANBEFORCED  Positions and labels can disagree (a
        %   mislabelled electrode, a cap fitted the other way round), and an
        %   analyst who suspects that needs to be able to see both answers.
            chanlocs = testCase.positioned({'F3', 'F4'}, [30 25 0; 30 -25 0]);

            testCase.verifyEqual(TransTools.LateralPairs(chanlocs, 'labels').method, 'labels');
            testCase.verifyEqual(TransTools.LateralPairs(chanlocs, 'geometry').method, 'geometry');
        end

        function anUnknownMethodIsRefusedRatherThanGuessed(testCase)
            testCase.verifyError(@() TransTools.LateralPairs( ...
                testCase.unpositioned({'F3', 'F4'}), 'nearest'), ...
                'Alakazam:LateralPairs');
        end

        function noChannelsIsNotAnError(testCase)
            r = TransTools.LateralPairs(struct('labels', {}));

            testCase.verifyEmpty(r.pairs);
            testCase.verifyEmpty(r.midline);
        end

        function pairsComeBackInMontageOrder(testCase)
        %PAIRSCOMEBACKINMONTAGEORDER  The matching finds them closest-first,
        %   which is not an order anyone reading a report expects.
            chanlocs = testCase.positioned({'front', 'frontR', 'back', 'backR'}, ...
                [80 30 0; 80 -30 0; -80 10 0; -80 -10 0]);

            r = TransTools.LateralPairs(chanlocs);

            testCase.verifyEqual(testCase.pairLabels(r), {'front/frontR', 'back/backR'}, ...
                'Ordered by the left member''s own place in the channel list.');
        end
    end

    methods (Access = private)
        function chanlocs = positioned(~, labels, xyz)
            chanlocs = struct('labels', labels, ...
                'X', num2cell(xyz(:, 1)'), 'Y', num2cell(xyz(:, 2)'), ...
                'Z', num2cell(xyz(:, 3)'));
        end

        function chanlocs = unpositioned(~, labels)
            chanlocs = struct('labels', labels);
        end

        function names = pairLabels(~, r)
            names = arrayfun(@(p) p.label, r.pairs, 'UniformOutput', false);
        end
    end
end
