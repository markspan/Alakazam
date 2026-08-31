classdef ParcellationTest < matlab.unittest.TestCase
%PARCELLATIONTEST  Signed source estimates and anatomical region time courses.
%
%   THE TEST THAT CARRIES THIS FILE is aFoldedRegionSurvivesAveraging. The
%   whole reason region time courses need sign flipping is that cortex is
%   folded: two vertices on opposite walls of a sulcus have nearly opposing
%   normals, so a plain average of a SIGNED estimate cancels a real effect
%   down to nothing for a purely geometric reason. That failure is silent --
%   it produces a small number, not an error -- so it is reproduced here
%   deliberately, and the fix is asserted to rescue it.
%
%   The geometry tests use a synthetic folded strip rather than the real
%   cortical sheet, so they run in milliseconds and need nothing on disk.
%   The one test that does touch FieldTrip's real template files
%   (theRealCorticalSheetMapsOntoTheAtlas) is what stops the synthetic ones
%   from being self-congratulatory: it checks the mapping against the actual
%   20484-vertex sheet and the actual AAL volume, and skips when FieldTrip
%   is absent.
%
%   Run with: runtests('tests/ParcellationTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src')));
        end
    end

    methods (Test)
        % ---- surface normals ----------------------------------------------
        function normalsAreUnitVectorsPointingOutward(testCase)
            sphere = testCase.icosphere();

            n = TransTools.SurfaceNormals(sphere);

            testCase.verifySize(n, size(sphere.pos));
            testCase.verifyEqual(vecnorm(n, 2, 2), ones(size(n, 1), 1), 'AbsTol', 1e-10);

            % On a sphere centred at the origin, outward IS radial, so every
            % normal should agree with its own position vector. This is the
            % one surface where the global convention can be checked vertex
            % by vertex rather than on average.
            radial = sphere.pos ./ vecnorm(sphere.pos, 2, 2);
            testCase.verifyGreaterThan(min(sum(n .* radial, 2)), 0.9);
        end

        function windingOrderDoesNotDecideTheDirection(testCase)
        %WINDINGORDERDOESNOTDECIDETHEDIRECTION  A mesh saved with its
        %   triangles wound the other way must not produce an inside-out
        %   surface, or every sign in every report would flip with the file
        %   it happened to be read from.
            sphere = testCase.icosphere();
            flipped = sphere;
            flipped.tri = sphere.tri(:, [1 3 2]);

            a = TransTools.SurfaceNormals(sphere);
            b = TransTools.SurfaceNormals(flipped);

            testCase.verifyEqual(b, a, 'AbsTol', 1e-10);
        end

        function aVolumetricGridIsRefusedWithAReason(testCase)
            grid = struct('pos', randn(50, 3));

            testCase.verifyError(@() TransTools.SurfaceNormals(grid), ...
                'Alakazam:SurfaceNormals');
        end

        % ---- the folded-cortex problem -------------------------------------
        function aFoldedRegionSurvivesAveraging(testCase)
        %AFOLDEDREGIONSURVIVESAVERAGING  The reason mean_flip is the default.
            [region, normals] = testCase.foldedStrip();
            t = linspace(0, 1, 40);
            truth = sin(2 * pi * t);

            % Each vertex sees the same underlying source, but projected onto
            % ITS OWN normal -- so half the strip records it inverted. That
            % is what a real sulcus does to a signed estimate.
            signedData = (normals * [0 0 1]') * truth;

            plain = mean(signedData, 1);
            flipped = mean(signedData .* sign(signedData(:, argmax(abs(truth)))), 1);

            testCase.verifyLessThan(max(abs(plain)), 0.1 * max(abs(truth)), ...
                'The fixture is not actually cancelling, so this proves nothing.');
            testCase.verifyGreaterThan(max(abs(flipped)), 0.5 * max(abs(truth)));
            testCase.verifyEqual(numel(region), size(normals, 1));
        end

        % ---- signed inverse output -----------------------------------------
        function anOrientationOfNormalGivesSignedValues(testCase)
            FieldTripFixtures.require(testCase);
            [lf, elec, headmodel, values, sm] = testCase.forwardFixture();
            normals = TransTools.SurfaceNormals(sm);

            magnitude = FieldTripFixtures.quietly(@() TransTools.InverseSolution( ...
                values, lf, elec, headmodel, 'mne'));
            signed = FieldTripFixtures.quietly(@() TransTools.InverseSolution( ...
                values, lf, elec, headmodel, 'mne', ...
                struct('Orientation', 'normal', 'Normals', normals)));

            testCase.verifyGreaterThanOrEqual(min(magnitude(:)), 0, ...
                'The magnitude orientation produced a negative value.');
            testCase.verifyLessThan(min(signed(:)), 0, ...
                'The signed orientation produced nothing negative, so it is not signed.');
            testCase.verifySize(signed, size(magnitude));

            % A projection onto one axis can never exceed the full vector's
            % length: a cheap check that the two really describe one estimate.
            testCase.verifyLessThanOrEqual(max(abs(signed(:))), max(magnitude(:)) + 1e-9);
        end

        function magnitudeRemainsTheDefault(testCase)
        %MAGNITUDEREMAINSTHEDEFAULT  Existing 3-D source maps, and the
        %   bit-exact equivalence with ComputeSourceEstimate, both depend on
        %   the default not moving.
            FieldTripFixtures.require(testCase);
            [lf, elec, headmodel, values] = testCase.forwardFixture();

            byDefault = FieldTripFixtures.quietly(@() TransTools.InverseSolution( ...
                values, lf, elec, headmodel, 'mne'));
            handRolled = TransTools.ComputeSourceEstimate(values, lf);

            testCase.verifyEqual(byDefault, handRolled, 'AbsTol', 1e-12);
        end

        function askingForSignedWithoutNormalsSaysSo(testCase)
            FieldTripFixtures.require(testCase);
            [lf, elec, headmodel, values] = testCase.forwardFixture();

            testCase.verifyError(@() TransTools.InverseSolution(values, lf, elec, ...
                headmodel, 'mne', struct('Orientation', 'normal')), ...
                'Alakazam:InverseSolution');
        end

        function normalsForTheWrongSurfaceAreRefused(testCase)
        %NORMALSFORTHEWRONGSURFACEAREREFUSED  Silent scrambling otherwise:
        %   the sign would come from an unrelated vertex.
            FieldTripFixtures.require(testCase);
            [lf, elec, headmodel, values] = testCase.forwardFixture();

            testCase.verifyError(@() TransTools.InverseSolution(values, lf, elec, ...
                headmodel, 'mne', struct('Orientation', 'normal', ...
                    'Normals', randn(7, 3))), 'Alakazam:InverseSolution');
        end

        % ---- against the real template files --------------------------------
        function theRealCorticalSheetMapsOntoTheAtlas(testCase)
        %THEREALCORTICALSHEETMAPSONTOTHEATLAS  The claim the whole feature
        %   rests on: a volumetric atlas and a surface source model, both
        %   nominally MNI, actually line up. Asserted against the real files,
        %   because a synthetic fixture cannot fail this in the way that
        %   matters (a coordinate-space mismatch).
            FieldTripFixtures.require(testCase);
            ftRoot = fileparts(which('ft_defaults'));
            sm = FieldTripFixtures.quietly(@() ft_read_headshape(fullfile(ftRoot, 'template', ...
                'sourcemodel', 'cortex_20484.surf.gii')));

            [vertexLabel, labels] = FieldTripFixtures.quietly(@() ...
                TransTools.AtlasVertexLabels(sm, 'aal'));

            testCase.verifyNumElements(vertexLabel, size(sm.pos, 1));
            testCase.verifyGreaterThan(mean(vertexLabel > 0), 0.80, ...
                'Fewer than 80% of cortical vertices got a region: check the coordinate spaces.');
            testCase.verifyGreaterThan(numel(unique(vertexLabel(vertexLabel > 0))), 80);
            testCase.verifyNumElements(labels, 116);
        end

        % ---- region time courses, on the real cortex -----------------------
        function signFlippingRecoversWhatPlainAveragingCancels(testCase)
        %SIGNFLIPPINGRECOVERSWHATPLAINAVERAGINGCANCELS  The folded-strip test
        %   above proves the principle on a toy; this proves it matters on
        %   the ACTUAL cortical sheet, where the folding is real and nobody
        %   chose it. Measured: mean_flip recovers about three times the
        %   amplitude a plain mean does, from identical input.
            [sm, signed] = testCase.realSheetWithPatch();

            withFlip = TransTools.ParcellateSource(signed, sm, struct('Mode', 'mean_flip'));
            without  = TransTools.ParcellateSource(signed, sm, struct('Mode', 'mean'));

            [flipPeak, region] = max(max(abs(withFlip), [], 2));
            plainPeak = max(abs(without(region, :)));

            testCase.verifyGreaterThan(flipPeak / plainPeak, 2, sprintf( ...
                ['Plain averaging lost only %.2fx here. If the gap has closed, either ' ...
                 'the fixture stopped spanning a sulcus or the flipping stopped ' ...
                 'happening -- and the second one fails silently.'], flipPeak / plainPeak));
        end

        function regionCoursesAreSignedAndNamed(testCase)
            [sm, signed] = testCase.realSheetWithPatch();

            [courses, labels, info] = TransTools.ParcellateSource(signed, sm);

            testCase.verifySize(courses, [numel(labels), size(signed, 2)]);
            testCase.verifyLessThan(min(courses(:)), 0, 'Region courses came out unsigned.');
            testCase.verifyGreaterThan(max(courses(:)), 0);
            testCase.verifyEqual(numel(info.VertexCounts), numel(labels));
            testCase.verifyGreaterThan(info.NRegionsKept, 60);
            testCase.verifyLessThan(info.NRegionsKept, info.NRegionsTotal, ...
                'Every AAL region was kept, including the cerebellum -- which a cortical sheet has no vertices in.');
        end

        function regionsTooSmallToTrustAreDropped(testCase)
            [sm, signed] = testCase.realSheetWithPatch();

            [~, fewer] = TransTools.ParcellateSource(signed, sm, struct('MinVertices', 400));
            [~, more]  = TransTools.ParcellateSource(signed, sm, struct('MinVertices', 20));

            testCase.verifyLessThan(numel(fewer), numel(more));
            testCase.verifyTrue(all(ismember(fewer, more)), ...
                'Raising the threshold introduced a region rather than only removing some.');
        end

        function anUnknownAtlasIsRefusedByName(testCase)
            FieldTripFixtures.require(testCase);
            sm = testCase.icosphere();

            testCase.verifyError(@() TransTools.AtlasVertexLabels(sm, 'phrenology'), ...
                'Alakazam:AtlasVertexLabels');
        end
    end

    methods (Access = private)
        function [sm, signed] = realSheetWithPatch(testCase)
        %REALSHEETWITHPATCH  FieldTrip's actual 20484-vertex cortical sheet,
        %   with one synthetic dipolar patch projected onto each vertex's own
        %   normal -- which is exactly what makes opposite sulcal walls record
        %   the same source with opposite sign.
            FieldTripFixtures.require(testCase);
            ftRoot = fileparts(which('ft_defaults'));
            sm = FieldTripFixtures.quietly(@() ft_convert_units(ft_read_headshape(fullfile( ...
                ftRoot, 'template', 'sourcemodel', 'cortex_20484.surf.gii')), 'mm'));

            normals = TransTools.SurfaceNormals(sm);
            t = linspace(0, 1, 50);
            d = vecnorm(sm.pos - sm.pos(1000, :), 2, 2);
            amplitude = exp(-(d / 25) .^ 2);              % a 25 mm patch
            signed = (amplitude .* (normals * [0 0 1]')) * sin(2 * pi * t);
        end

        function s = icosphere(~)
        %ICOSPHERE  A closed triangulated sphere: the one surface where
        %   "outward" is checkable vertex by vertex.
            [x, y, z] = sphere(24);
            p = unique([x(:), y(:), z(:)], 'rows');
            s = struct('pos', p, 'tri', convhull(p(:, 1), p(:, 2), p(:, 3)));
        end

        function [region, normals] = foldedStrip(~)
        %FOLDEDSTRIP  A sulcus in miniature: two banks whose normals oppose.
            n = 40;
            region = (1:n)';
            normals = repmat([0 0 1], n, 1);
            normals(2:2:end, 3) = -1;   % alternating walls
        end

        function [lf, elec, headmodel, values, sm] = forwardFixture(testCase)
            rng(11);
            nChan = 16; nSrc = 30; nTime = 12;
            elecPos = randn(nChan, 3);
            elecPos = 9 * elecPos ./ vecnorm(elecPos, 2, 2);

            sm = testCase.icosphere();
            sm.pos = sm.pos(1:nSrc, :) * 2;
            sm.tri = sm.tri(all(sm.tri <= nSrc, 2), :);

            labels = arrayfun(@(k) sprintf('E%d', k), 1:nChan, 'UniformOutput', false);
            elec = struct();
            elec.label = labels(:); elec.elecpos = elecPos;
            elec.chanpos = elecPos; elec.unit = 'cm';
            headmodel = struct('type', 'singlesphere', 'o', [0 0 0], ...
                'r', 9, 'cond', 0.33, 'unit', 'cm');

            gain = cell(1, nSrc);
            for i = 1:nSrc
                d = elecPos - sm.pos(i, :);
                gain{i} = d ./ (vecnorm(d, 2, 2) .^ 3);
            end

            lf = struct();
            lf.pos = sm.pos; lf.inside = true(nSrc, 1);
            lf.leadfield = gain; lf.label = labels(:); lf.unit = 'cm';
            values = randn(nChan, nTime) * 1e-6;
        end
    end
end

% ======================================================================= %
function i = argmax(v)
    [~, i] = max(v);
end
