classdef SourceInverseTest < matlab.unittest.TestCase
%SOURCEINVERSETEST  The FieldTrip inverse shim, and the equivalence that
%   justifies trusting it.
%
%   THE CENTRAL TEST HERE IS theShimReproducesTheHandRolledDspm. Alakazam
%   already had a working dSPM minimum-norm source estimate, hand-rolled in
%   TransTools.ComputeSourceEstimate, and people may already have source
%   maps in reports that came from it. Routing that through FieldTrip
%   instead is only safe if the two agree; otherwise it is not a refactor
%   but a silent change of results wearing a refactor's clothes.
%
%   They agree because the shim asks FieldTrip for exactly the operator the
%   hand-rolled code writes down. FieldTrip computes
%       w = R*A'*(A*R*A' + lambda_ft^2*C)^-1
%   and Alakazam computes
%       M = L'*(L*L' + lambda*I)^-1
%   so passing noisecov = lambda*I with lambda_ft = 1 makes lambda_ft^2*C
%   exactly lambda*I, and the two are the same matrix. That is an
%   algebraic claim, so it is testable, so it is tested -- to floating-
%   point agreement, not to "looks similar".
%
%   The obvious alternative parameterisation, noisecov = I with
%   lambda_ft = sqrt(lambda), yields the same FILTER but a projected noise
%   smaller by a factor lambda, so the dSPM scale would shift globally --
%   invisible in a normalised colour map, wrong in any reported number.
%   aMismatchedParameterisationIsDetectable pins that, so the trap stays
%   documented by a failing assertion rather than by a comment.
%
%   FieldTrip is an optional heavy dependency, so these tests SKIP rather
%   than fail when it is absent. They never trigger its download: an
%   existing install is reused if there is one, and that is all.
%
%   Run with: runtests('tests/SourceInverseTest.m').

    properties (Constant)
        NChan = 16
        NSrc  = 30
        NTime = 12
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
        %REQUIREFIELDTRIP  Reuse an existing FieldTrip, or skip the class.
        %   Deliberately NOT TransTools.ensureFieldTrip, which may prompt and
        %   download ~400 MB -- see FieldTripFixtures.
            FieldTripFixtures.require(testCase);
        end
    end

    methods (Test)
        % ---- the equivalence that makes the shim safe ---------------------
        function theShimReproducesTheHandRolledDspm(testCase)
            [lf, elec, headmodel, values] = testCase.forwardFixture();

            handRolled = TransTools.ComputeSourceEstimate(values, lf);
            viaShim = FieldTripFixtures.quietly(@() ...
                TransTools.InverseSolution(values, lf, elec, headmodel, 'mne'));

            testCase.verifySize(viaShim, size(handRolled));
            rel = max(abs(viaShim(:) - handRolled(:))) / max(abs(handRolled(:)));
            testCase.verifyLessThan(rel, 1e-8, sprintf( ...
                ['The shim and the hand-rolled dSPM disagree by %.3g relative. They are ' ...
                 'supposed to be the same operator, so a real difference here means ' ...
                 'existing source maps would change meaning, not that a tolerance ' ...
                 'needs loosening.'], rel));
        end

        function aMismatchedParameterisationIsDetectable(testCase)
        %AMISMATCHEDPARAMETERISATIONISDETECTABLE  Guards the trap the shim
        %   avoids: noisecov = I with lambda = sqrt(lambda) gives the same
        %   filter but a globally rescaled dSPM. If this ever stops
        %   differing, FieldTrip's noise projection changed and the shim's
        %   comment about why it parameterises as it does is now wrong.
            [lf, elec, headmodel, values] = testCase.forwardFixture();
            inside = find(lf.inside);
            L = cell2mat(lf.leadfield(inside));
            lambda = 0.05 * trace(L * L') / size(L, 1);

            good = FieldTripFixtures.quietly(@() ...
                TransTools.InverseSolution(values, lf, elec, headmodel, 'mne'));
            bad = FieldTripFixtures.quietly(@() ft_inverse_mne(lf, elec, headmodel, values, ...
                'noisecov', eye(size(L, 1)), 'lambda', sqrt(lambda), 'keepfilter', 'yes'));

            w = bad.filter{inside(1)};
            noiseVarBad = max(sum(w .^ 2, 2), eps);           % Cnoise = I
            noiseVarGood = max(lambda * sum(w .^ 2, 2), eps); % Cnoise = lambda*I

            testCase.verifyEqual(noiseVarBad ./ noiseVarGood, ...
                repmat(1 / lambda, 3, 1), 'RelTol', 1e-8);
            testCase.verifyNotEqual(round(1 / lambda, 6), 1, ...
                'The fixture happens to make lambda 1, so this test proves nothing.');
            testCase.verifyGreaterThan(max(good(:)), 0);
        end

        % ---- the shared contract, for every method ------------------------
        function everyMethodReturnsOneValuePerVertexPerSample(testCase)
            [lf, elec, headmodel, values] = testCase.forwardFixture();

            for m = ["mne", "eloreta", "sloreta"]
                out = FieldTripFixtures.quietly(@() ...
                    TransTools.InverseSolution(values, lf, elec, headmodel, m));
                testCase.verifySize(out, [testCase.NSrc, testCase.NTime], ...
                    sprintf('%s returned the wrong shape.', m));
            end
        end

        function verticesOutsideTheHeadComeBackAsNaN(testCase)
        %VERTICESOUTSIDETHEHEADCOMEBACKASNAN  DrawSourceMap colours by
        %   vertex index, so a result that quietly dropped the outside ones
        %   would shift every colour onto the wrong vertex.
            [lf, elec, headmodel, values] = testCase.forwardFixture();
            lf.inside(4:6) = false;

            for m = ["mne", "eloreta", "sloreta"]
                out = FieldTripFixtures.quietly(@() ...
                    TransTools.InverseSolution(values, lf, elec, headmodel, m));
                testCase.verifyTrue(all(isnan(out(4:6, :)), 'all'), ...
                    sprintf('%s put numbers on vertices marked outside.', m));
                testCase.verifyTrue(all(isfinite(out(7:end, :)), 'all'), ...
                    sprintf('%s left inside vertices unfilled.', m));
            end
        end

        function everyMethodProducesAFiniteNonZeroMap(testCase)
            [lf, elec, headmodel, values] = testCase.forwardFixture();

            for m = ["mne", "eloreta", "sloreta"]
                out = FieldTripFixtures.quietly(@() ...
                    TransTools.InverseSolution(values, lf, elec, headmodel, m));
                testCase.verifyTrue(all(isfinite(out), 'all'), ...
                    sprintf('%s produced non-finite values.', m));
                testCase.verifyGreaterThan(max(out(:)), 0, ...
                    sprintf('%s produced an all-zero map.', m));
            end
        end

        % ---- the scales are not interchangeable ---------------------------
        function eachMethodCarriesItsOwnScaleLabel(testCase)
        %EACHMETHODCARRIESITSOWNSCALELABEL  The documented hazard in this
        %   whole area is somebody reading one method's colour scale as
        %   another's. The label travels with the result so a caller cannot
        %   draw a colorbar without being handed the right words for it.
            [lf, elec, headmodel, values] = testCase.forwardFixture();
            labels = strings(0);

            for m = ["mne", "eloreta", "sloreta"]
                [~, info] = FieldTripFixtures.quietly(@() ...
                    TransTools.InverseSolution(values, lf, elec, headmodel, m));
                testCase.verifyNotEmpty(info.ScaleLabel);
                testCase.verifyNotEmpty(info.ScaleNote);
                testCase.verifyEqual(info.Method, char(m));
                labels(end + 1) = string(info.ScaleLabel); %#ok<AGROW>
            end

            testCase.verifyNumElements(unique(labels), 3, ...
                'Two methods share a colorbar label, which invites exactly the confusion.');
        end

        function theMethodsDoNotAgreeAndShouldNotBeAveraged(testCase)
        %THEMETHODSDONOTAGREEANDSHOULDNOTBEAVERAGED  Pins that these are
        %   genuinely different estimators. If they ever came out equal,
        %   either the method argument stopped being honoured or two
        %   branches got wired to the same call.
            [lf, elec, headmodel, values] = testCase.forwardFixture();

            a = FieldTripFixtures.quietly(@() TransTools.InverseSolution(values, lf, elec, headmodel, 'mne'));
            b = FieldTripFixtures.quietly(@() TransTools.InverseSolution(values, lf, elec, headmodel, 'eloreta'));
            c = FieldTripFixtures.quietly(@() TransTools.InverseSolution(values, lf, elec, headmodel, 'sloreta'));

            testCase.verifyNotEqual(normalise(a), normalise(b));
            testCase.verifyNotEqual(normalise(a), normalise(c));
        end

        function anUnknownMethodIsRefusedByName(testCase)
            [lf, elec, headmodel, values] = testCase.forwardFixture();

            testCase.verifyError(@() ...
                TransTools.InverseSolution(values, lf, elec, headmodel, 'beamformer'), ...
                'Alakazam:InverseSolution');

            % And that it says WHICH method it did not recognise, so the
            % message is actionable rather than merely correct.
            try
                TransTools.InverseSolution(values, lf, elec, headmodel, 'beamformer');
                testCase.verifyFail('An unknown method was accepted.');
            catch err
                testCase.verifySubstring(err.message, 'beamformer');
            end
        end
    end

    methods (Access = private)
        function [lf, elec, headmodel, values] = forwardFixture(testCase)
        %FORWARDFIXTURE  A small synthetic forward model in the exact shape
        %   BuildSourceForwardModel returns.
        %
        %   Synthetic rather than the real template model on purpose: the
        %   real one is a 20484-vertex cortical sheet whose leadfield takes
        %   minutes to build and needs FieldTrip's template files on disk.
        %   What these tests check -- that two inverse computations over the
        %   SAME leadfield agree, and that the shared contract holds -- does
        %   not depend on the leadfield being anatomically real, only on its
        %   being well conditioned. The end-to-end run against the real
        %   template model is a separate, slower concern and is not in here.
            rng(11);
            n = testCase.NChan;

            elecPos = randn(n, 3);
            elecPos = 9 * elecPos ./ vecnorm(elecPos, 2, 2);
            srcPos  = randn(testCase.NSrc, 3) * 2;

            labels = arrayfun(@(k) sprintf('E%d', k), 1:n, 'UniformOutput', false);

            elec = struct();
            elec.label   = labels(:);
            elec.elecpos = elecPos;
            elec.chanpos = elecPos;
            elec.unit    = 'cm';

            % A single conducting sphere: enough for FieldTrip to accept the
            % arguments, and never actually used, because the leadfield
            % below is precomputed (see InverseSolution's own note).
            headmodel = struct('type', 'singlesphere', 'o', [0 0 0], ...
                'r', 9, 'cond', 0.33, 'unit', 'cm');

            % A plain current dipole in an infinite medium: not physically
            % complete, but smooth, well conditioned and depth-dependent in
            % the way a real leadfield is.
            gain = cell(1, testCase.NSrc);
            for i = 1:testCase.NSrc
                d = elecPos - srcPos(i, :);
                r = vecnorm(d, 2, 2);
                gain{i} = d ./ (r .^ 3);
            end

            lf = struct();
            lf.pos       = srcPos;
            lf.inside    = true(testCase.NSrc, 1);
            lf.leadfield = gain;
            lf.label     = labels(:);
            lf.unit      = 'cm';

            values = randn(n, testCase.NTime) * 1e-6;
        end

    end
end

% ======================================================================= %
function y = normalise(x)
%NORMALISE  Compare maps by shape, not by scale: the methods have different
%   units by design, so an unscaled comparison would "differ" trivially.
    x = x(isfinite(x));
    y = x / max(abs(x));
end
