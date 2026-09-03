classdef ComponentDipolesTest < matlab.unittest.TestCase
%COMPONENTDIPOLESTEST  The per-component dipole fit: its contract, mostly.
%
%   Fitting real components needs an ICA decomposition and dipfit's BEM, and
%   takes the better part of a minute, so the expensive path is one tagged
%   test and the rest pin the contract that callers depend on: a value per
%   component, in range, and never an exception. The component selector
%   opens with this result in a column, and a dialog that fails to open
%   because a dipole could not be fitted would be a bad trade for a
%   diagnostic.
%
%   Run with: runtests('tests/ComponentDipolesTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Transformations')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function aDatasetWithoutIcaReturnsNothingRatherThanThrowing(testCase)
        %ADATASETWITHOUTICARETURNSNOTHINGRATHERTHANTHROWING  RemoveComponents
        %   guarantees a decomposition before calling this, but the function
        %   is callable on its own and must not punish that.
            EEG = struct('icaweights', [], 'icachansind', []);
            rv = TransTools.ComponentDipoles(EEG);
            testCase.verifyEmpty(rv);
        end

        function anUnfittableDatasetYieldsNaNsNotAnError(testCase)
        %ANUNFITTABLEDATASETYIELDSNANSNOTANERROR  The best-effort contract.
        %   Weights with no matching channel locations cannot be fitted by
        %   anything, and the answer must still be a value per component.
            EEG = struct('icaweights', eye(4), 'icasphere', eye(4), ...
                'icawinv', eye(4), 'icachansind', 1:4, 'nbchan', 4, ...
                'chanlocs', struct('labels', {'a', 'b', 'c', 'd'}));

            rv = TransTools.ComponentDipoles(EEG);

            testCase.verifyNumElements(rv, 4);
            testCase.verifyTrue(all(isnan(rv)), ...
                'An unfittable dataset should give NaN per component, not a partial answer.');
        end

        function theResultIsOneValuePerComponent(testCase)
        %THERESULTISONEVALUEPERCOMPONENT  The selector indexes this by
        %   component number, so a short vector would silently misalign the
        %   column against the rows.
            nComp = 7;
            EEG = struct('icaweights', eye(nComp), 'icasphere', eye(nComp), ...
                'icawinv', eye(nComp), 'icachansind', 1:nComp, 'nbchan', nComp, ...
                'chanlocs', struct('labels', arrayfun(@(k) sprintf('E%d', k), ...
                    1:nComp, 'UniformOutput', false)));

            rv = TransTools.ComponentDipoles(EEG);

            testCase.verifyNumElements(rv, nComp);
            testCase.verifySize(rv, [nComp 1]);
        end
    end

    methods (Test, TestTags = {'Slow'})
        function realComponentsGetResidualVariancesInRange(testCase)
        %REALCOMPONENTSGETRESIDUALVARIANCESINRANGE  The one test that runs
        %   the actual fit, on a decomposition made here rather than on a
        %   fixture, because what is being checked is that dipfit accepts
        %   what Alakazam hands it.
            testCase.assumeNotEmpty(which('dipfitdefs'), 'dipfit is not installed.');
            testCase.assumeNotEmpty(which('pop_runica'), 'EEGLAB is not installed.');
            EEG = testCase.decomposedFixture();

            rv = TransTools.ComponentDipoles(EEG);

            testCase.verifyNumElements(rv, size(EEG.icaweights, 1));
            fitted = rv(isfinite(rv));
            testCase.assertNotEmpty(fitted, 'No component could be fitted at all.');
            testCase.verifyTrue(all(fitted >= 0 & fitted <= 1), ...
                'Residual variance must be a fraction in [0, 1].');
        end
    end

    methods (Access = private)
        function EEG = decomposedFixture(testCase)
        %DECOMPOSEDFIXTURE  A small synthetic dataset with real 10-5
        %   positions and a genuine ICA decomposition. Synthetic because the
        %   claim under test is about the interface to dipfit, not about any
        %   particular recording. Positions are filled the way Alakazam
        %   fills them (TransTools.FillChanlocs -> pop_chanedit lookup),
        %   which also keeps this test free of any FieldTrip dependency.
            keep = {'Fz', 'Cz', 'Pz', 'C3', 'C4', 'F3', 'F4', 'P3', 'P4', 'O1', 'O2', 'T7'};
            n = numel(keep);
            rng(3);

            EEG = eeg_emptyset();
            EEG.srate  = 250;
            EEG.nbchan = n;
            EEG.trials = 1;
            EEG.data   = randn(n, 250 * 20);
            EEG.pnts   = size(EEG.data, 2);
            EEG.xmin   = 0;
            EEG.xmax   = (EEG.pnts - 1) / EEG.srate;
            EEG.chanlocs = struct('labels', keep);

            EEG = TransTools.FillChanlocs(EEG, 'Alakazam:ComponentDipolesTest', ...
                TransTools.Template1005File('Alakazam:ComponentDipolesTest'));
            positioned = arrayfun(@(c) ~isempty(c.X) && ~isnan(c.X), EEG.chanlocs);
            testCase.assumeTrue(all(positioned), ...
                'The template did not position every channel this fixture uses.');

            % Wrapped for the same reason production wraps it: runica
            % leaves the RNG in legacy mode, and an unwrapped call here
            % failed fifty-two later tests in the same process.
            EEG = evalcQuiet(@() TransTools.WithRestoredRng(@() ...
                pop_runica(EEG, 'icatype', 'runica', 'extended', 1, 'verbose', 'off')));
            EEG.icachansind = 1:n;
        end
    end
end

% ======================================================================= %
function out = evalcQuiet(fn)
%EVALCQUIET  Run FN with its console narration swallowed. runica prints a
%   screenful per training block; errors still propagate through evalc.
    assert(isa(fn, 'function_handle'));   % also keeps fn visibly used
    out = [];                             % evalc hides the assignment below
    evalc('out = fn();');
end
