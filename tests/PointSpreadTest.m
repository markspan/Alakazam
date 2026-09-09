classdef PointSpreadTest < matlab.unittest.TestCase
%POINTSPREADTEST  The point spread function the source cluster report draws,
%   checked against what a point spread function is supposed to do.
%
%   THE FIGURE IS AN ARGUMENT, SO IT HAS TO BE RIGHT. The report shows one
%   vertex's point spread to make a claim a reader is asked to act on: that
%   the smoothness of every cortical map above it is interpolation and not
%   measurement. A point spread function that quietly came out of the wrong
%   vertex would make that argument with a picture of nothing, and would
%   look exactly as convincing.
%
%   WHAT THESE TESTS CATCH, AND WHAT THEY DO NOT. They were written against
%   deliberate breakage rather than by inspection, and the results are worth
%   recording because one of them is counter-intuitive:
%
%     Taking the leadfield column from the WRONG vertex IS caught. An
%     off-by-one moved eLORETA's median peak error from 0.0 mm to 18.1 mm
%     and its maximum to 89.9 mm; taking the mirror vertex in the other
%     hemisphere gave a median of 65.8 mm. Both blow past the bounds below.
%
%     Getting the ORIENTATION wrong is NOT caught, and cannot be caught this
%     way. Every orientation of a given vertex is still that vertex's own
%     field, so an exact localiser still localises it exactly: scrambling
%     the normals left the median peak error at 0.0 mm. The sign at the
%     vertex does not help either, since the pattern and the projection are
%     taken from the same normals array and so agree with each other
%     whatever it holds. These tests pin the indexing; the orientation is
%     pinned where it is decided, in TransTools.SurfaceNormals.
%
%   ELORETA IS THE ONE WITH A SHARP PREDICTION. Its defining property is
%   exact zero localisation error for a single source (Pascual-Marqui,
%   2007), so "the estimate peaks where the source was" is a real assertion
%   there rather than a loose bound. dSPM has no such property and is not
%   expected to satisfy it: it is displaced by tens of millimetres, which is
%   the number the report quotes, so that is asserted as the separate and
%   different fact it is.
%
%   These need FieldTrip's template files, and the first test pays about
%   15 s for the 5124-vertex leadfield. The rest are cache hits.
%
%   Run with: runtests('tests/PointSpreadTest.m').
%
%   See also TRANSTOOLS.POINTSPREADFUNCTION, TRANSTOOLS.INVERSESOLUTION,
%   SOURCECLUSTERREPORTTEST, FIELDTRIPFIXTURES.

    properties (Constant)
        Labels = {'FP1','FP2','F7','F3','FZ','F4','F8','FC5','FC1','FC2', ...
                  'FC6','T7','C3','CZ','C4','T8','CP5','CP1','CP2','CP6', ...
                  'P7','P3','PZ','P4','P8','O1','OZ','O2','POZ'}
        SourceSpace = 5124
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src')));
        end

        function requireFieldTrip(testCase)
            FieldTripFixtures.require(testCase);
        end
    end

    methods (Test)
        function anExactLocaliserPeaksAtItsOwnVertex(testCase)
        %ANEXACTLOCALISERPEAKSATITSOWNVERTEX  The central test here. eLORETA
        %   has zero localisation error for a single source by construction,
        %   so the point spread function of vertex i must peak at vertex i.
        %   It does not peak there by accident: see the class comment for
        %   what an off-by-one leadfield column does to these numbers.
            [model, picks] = testCase.forwardModel();
            peakError = testCase.sweep(model, picks, 'eloreta');

            testCase.verifyLessThanOrEqual(median(peakError), 5, sprintf( ...
                ['eLORETA localises a single source exactly, so its point spread ' ...
                 'should peak at the vertex it belongs to. The median peak was ' ...
                 '%.1f mm away, which means the leadfield column, the vertex index ' ...
                 'or the inside/outside mapping is not lining up.'], median(peakError)));
            testCase.verifyLessThanOrEqual(max(peakError), 15, sprintf( ...
                ['One point spread peaked %.1f mm from its own vertex. A few ' ...
                 'millimetres is the mesh spacing; this is a different vertex.'], ...
                 max(peakError)));
        end

        function theDefaultMethodIsDisplacedByTensOfMillimetres(testCase)
        %THEDEFAULTMETHODISDISPLACEDBYTENSOFMILLIMETRES  dSPM, the default,
        %   is NOT an exact localiser, and the report says so in millimetres
        %   ("a median peak localisation error in the tens of millimetres").
        %   That sentence is only honest while this holds, so it is measured
        %   rather than repeated.
        %
        %   The bound is two-sided on purpose. Too small would mean the
        %   report is now overstating a limitation; too large would mean
        %   something is broken rather than merely limited.
            [model, picks] = testCase.forwardModel();
            peakError = testCase.sweep(model, picks, 'mne');

            testCase.verifyGreaterThanOrEqual(median(peakError), 10, sprintf( ...
                ['dSPM''s median peak error came out at %.1f mm. If it really is ' ...
                 'that good, the report''s resolution paragraph is now overstating ' ...
                 'the limitation and should be rewritten, rather than this bound ' ...
                 'lowered.'], median(peakError)));
            testCase.verifyLessThanOrEqual(median(peakError), 80, sprintf( ...
                'dSPM''s median peak error was %.1f mm, which is most of a head.', ...
                median(peakError)));
        end

        function thePointSpreadIsTensOfMillimetresWide(testCase)
        %THEPOINTSPREADISTENSOFMILLIMETRESWIDE  The claim the report's figure
        %   is actually making. Spatial dispersion is the average distance
        %   the estimate of a vertex is drawn from, so a value in the tens of
        %   millimetres is the statement "this map is far smoother than it
        %   looks", in a number. Both methods, because the claim is about the
        %   montage and the sheet rather than about one inverse.
            [model, picks] = testCase.forwardModel();

            for method = {'eloreta', 'mne'}
                [~, dispersion] = testCase.sweep(model, picks, method{1});
                testCase.verifyGreaterThanOrEqual(min(dispersion), 20, sprintf( ...
                    ['%s reported a dispersion of %.1f mm. A point spread that ' ...
                     'tight on a 29-electrode montage would be a finding, not a ' ...
                     'passing test.'], method{1}, min(dispersion)));
                testCase.verifyLessThanOrEqual(max(dispersion), 100, sprintf( ...
                    '%s reported a dispersion of %.1f mm, which exceeds the head.', ...
                    method{1}, max(dispersion)));
            end
        end

        function distantCortexCarriesRealWeight(testCase)
        %DISTANTCORTEXCARRIESREALWEIGHT  Dispersion is a summary, and a
        %   summary can be large because of a thin tail. This checks the
        %   thing the picture actually shows: that a substantial part of the
        %   cortex sits at a substantial fraction of the peak, which is why
        %   the figure looks like a lobe rather than a dot.
            [model, picks] = testCase.forwardModel();
            vertex = picks(round(numel(picks) / 2));

            psf = FieldTripFixtures.quietly(@() TransTools.PointSpreadFunction( ...
                vertex, model.leadfield, model.sourcemodel, model.elec, ...
                model.headmodel, 'mne', testCase.solveOpts(model)));

            magnitude = abs(psf);
            share = mean(magnitude >= 0.25 * max(magnitude));
            testCase.verifyGreaterThan(share, 0.02, sprintf( ...
                ['Only %.1f%% of the sheet reached a quarter of the peak, so the ' ...
                 'estimate is far more focal than the report claims and the ' ...
                 'figure would not show what its caption says.'], 100 * share));
        end

        function verticesOutsideTheModelAreExcludedNotReadAsZero(testCase)
        %VERTICESOUTSIDETHEMODELAREEXCLUDEDNOTREADASZERO  InverseSolution
        %   marks an outside vertex NaN. Read as zero it would drag the
        %   dispersion down and could put the peak on a vertex carrying no
        %   estimate at all, which is the second of the two ways this
        %   computation goes wrong.
            model = testCase.forwardModel();
            masked = model;
            band = 1:600;
            masked.leadfield.inside(band) = false;

            [psf, info] = FieldTripFixtures.quietly(@() TransTools.PointSpreadFunction( ...
                2600, masked.leadfield, masked.sourcemodel, masked.elec, ...
                masked.headmodel, 'mne', testCase.solveOpts(masked)));

            testCase.verifyTrue(all(isnan(psf(band))), ...
                'Vertices outside the model came back with numbers on them.');
            testCase.verifyFalse(ismember(info.PeakVertex, band), ...
                'The peak was placed on a vertex the model does not estimate.');
            testCase.verifyTrue(isfinite(info.DispersionMm), ...
                'A NaN leaked into the dispersion instead of being excluded.');
        end

        function aVertexOutsideTheModelIsRefused(testCase)
        %AVERTEXOUTSIDETHEMODELISREFUSED  It has no scalp pattern, so there
        %   is nothing to spread, and returning zeros would look like an
        %   answer.
            model = testCase.forwardModel();
            masked = model;
            masked.leadfield.inside(41) = false;

            testCase.verifyError(@() TransTools.PointSpreadFunction(41, ...
                masked.leadfield, masked.sourcemodel, masked.elec, ...
                masked.headmodel, 'mne', testCase.solveOpts(masked)), ...
                'Alakazam:PointSpreadFunction');
        end

        function aVertexOffTheSheetIsRefusedByNumber(testCase)
            model = testCase.forwardModel();
            n = size(model.sourcemodel.pos, 1);

            testCase.verifyError(@() TransTools.PointSpreadFunction(n + 1, ...
                model.leadfield, model.sourcemodel, model.elec, model.headmodel, ...
                'mne', testCase.solveOpts(model)), 'Alakazam:PointSpreadFunction');
        end
    end

    methods (Access = private)
        function [model, picks] = forwardModel(testCase)
        %FORWARDMODEL  The real template forward model, built once per
        %   session by BuildSourceForwardModel's own cache and a hit
        %   thereafter.
            [lf, sm, ~, el, hm] = FieldTripFixtures.quietly(@() ...
                TransTools.BuildSourceForwardModel(testCase.Labels, testCase.SourceSpace));
            model = struct('leadfield', lf, 'sourcemodel', sm, 'elec', el, ...
                'headmodel', hm, 'normals', TransTools.SurfaceNormals(sm));

            % Spread over the whole sheet rather than sampled at random:
            % point spread varies with depth and with distance from the
            % electrodes, so a random draw would make these bounds depend on
            % a seed. This way a failure is reproducible by vertex number.
            n = size(sm.pos, 1);
            picks = unique(round(linspace(1, n, 42)));
        end

        function opts = solveOpts(~, model)
        %SOLVEOPTS  The settings a source cluster test uses by default.
            opts = struct('RegParam', 0.05, 'Orientation', 'normal', ...
                'Normals', model.normals);
        end

        function [peakError, dispersion] = sweep(testCase, model, picks, method)
            peakError  = zeros(numel(picks), 1);
            dispersion = zeros(numel(picks), 1);
            for k = 1:numel(picks)
                [~, info] = FieldTripFixtures.quietly(@() TransTools.PointSpreadFunction( ...
                    picks(k), model.leadfield, model.sourcemodel, model.elec, ...
                    model.headmodel, method, testCase.solveOpts(model)));
                peakError(k)  = info.PeakErrorMm;
                dispersion(k) = info.DispersionMm;
            end
        end
    end
end
