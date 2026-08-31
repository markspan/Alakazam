classdef SignedOrientationTest < matlab.unittest.TestCase
%SIGNEDORIENTATIONTEST  Cortical surface normals, and the signed source
%   estimate the 3D brain view draws from them.
%
%   A free-orientation inverse gives three dipole components per vertex, and
%   something has to reduce them to one number. The L2 norm is a magnitude
%   and is always positive, so it cannot represent the polarity of a
%   component; projecting onto the cortical normal keeps the sign. These
%   tests cover the normals themselves and the projection that uses them.
%
%   The normals tests use a synthetic sphere rather than the real cortical
%   sheet: on a sphere centred at the origin "outward" is radial, so the
%   global sign convention can be checked vertex by vertex rather than on
%   average, which no folded surface allows.
%
%   Run with: runtests('tests/SignedOrientationTest.m').
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





    end

    methods (Access = private)

        function s = icosphere(~)
        %ICOSPHERE  A closed triangulated sphere: the one surface where
        %   "outward" is checkable vertex by vertex.
            [x, y, z] = sphere(24);
            p = unique([x(:), y(:), z(:)], 'rows');
            s = struct('pos', p, 'tri', convhull(p(:, 1), p(:, 2), p(:, 3)));
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

