classdef ArtefactDetectChannelScopeTest < matlab.unittest.TestCase
%ARTEFACTDETECTCHANNELSCOPETEST  Which channels artefact detection tests,
%   and what happens to the ones it cannot repair.
%
%   THE CASE THAT PROMPTED THIS FILE. A data-quality report listed VEOG as
%   a candidate for interpolation on six subjects. It was not a GEDAI
%   artefact and not a reporting error: ArtefactDetect tested every channel
%   with no type filter, and an eye channel exceeds any threshold chosen
%   for scalp EEG on every blink, so it was flagged on a large fraction of
%   trials by construction.
%
%   Two behaviours follow, and they are separate decisions:
%
%     * Testing EOG is WANTED under 'Whole epoch', where a blink
%       condemning the trial is the classic rejection, so the default must
%       stay 'All channels'. Anything else would silently switch off blink
%       rejection for a pipeline that depends on it.
%     * Interpolating a flagged EOG is never wanted, at any scope. It has
%       no scalp position, so it is not a sample of the field a spline
%       reconstructs, and eeg_interp removed the channel from the set
%       rather than placing it, after which the caller indexed a channel
%       that was gone: "Index in position 1 exceeds array bounds". That
%       was an error, not a bad number, and interpolatingAnEogChannel...
%       below is the case that reproduces it.
%
%   Run with: runtests('tests/ArtefactDetectChannelScopeTest.m').
%
%   See also ARTEFACTDETECT, TRANSTOOLS.INTERPOLATEFLAGGEDCELLS,
%   EEGCHANNELMASK.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Transformations', 'ArtefactDetect'), ...
                     fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end

        function requireEeglab(testCase)
            testCase.assumeTrue(exist('eeg_interp', 'file') == 2, ...
                'EEGLAB is not on the path, so interpolation cannot be exercised.');
        end
    end

    methods (Test)
        function everyChannelIsTestedByDefault(testCase)
        %EVERYCHANNELISTESTEDBYDEFAULT  The default has to be unchanged, or
        %   blink rejection stops working for anyone relying on it.
            EEG = testCase.eegWithBlinkingEog();
            out = ArtefactDetect(EEG, testCase.options('This channel only'));

            flags = testCase.flaggedCells(out);
            testCase.verifyEqual(sum(flags(5, :)), 6, ...
                'The eye channel should still be tested when nothing asks otherwise.');
        end

        function scalpOnlyLeavesTheEyeChannelAlone(testCase)
            EEG = testCase.eegWithBlinkingEog();
            opts = testCase.options('This channel only');
            opts.Channels = 'Scalp EEG only';
            out = ArtefactDetect(EEG, opts);

            flags = testCase.flaggedCells(out);
            testCase.verifyEqual(nnz(flags), 0, ...
                'Nothing should have been flagged: only VEOG exceeded the threshold.');
            testCase.verifyFalse(any(isnan(out.data(5, :, 1))), ...
                'The eye channel''s own data must be left intact, not merely unflagged.');
        end

        function scalpOnlyStillFlagsABadScalpChannel(testCase)
        %SCALPONLYSTILLFLAGSABADSCALPCHANNEL  The option must narrow what is
        %   tested, not weaken the detector. Without this the previous case
        %   would pass on a build that had stopped detecting anything.
            EEG = testCase.eegWithBlinkingEog();
            EEG.data(2, 40:80, 1:3) = 300;      % Cz, genuinely bad
            opts = testCase.options('This channel only');
            opts.Channels = 'Scalp EEG only';
            out = ArtefactDetect(EEG, opts);

            flags = testCase.flaggedCells(out);
            testCase.verifyEqual(sum(flags(2, :)), 3, 'Cz should still be flagged.');
            testCase.verifyEqual(sum(flags(5, :)), 0, 'VEOG should not be.');
        end

        function anUntypedDatasetIsUnaffected(testCase)
        %ANUNTYPEDDATASETISUNAFFECTED  eegChannelMask keeps every channel
        %   whose type is blank, so asking for scalp-only on a dataset that
        %   never recorded channel types must test everything rather than
        %   silently testing nothing.
            EEG = testCase.eegWithBlinkingEog();
            [EEG.chanlocs.type] = deal('');
            opts = testCase.options('This channel only');
            opts.Channels = 'Scalp EEG only';
            out = ArtefactDetect(EEG, opts);

            flags = testCase.flaggedCells(out);
            testCase.verifyEqual(sum(flags(5, :)), 6, ...
                'With no types recorded, every channel is still tested.');
        end

        function interpolatingAnEogChannelDoesNotError(testCase)
        %INTERPOLATINGANEOGCHANNELDOESNOTERROR  The bug itself. Before the
        %   guard in InterpolateFlaggedCells this threw rather than
        %   returning anything at all.
            EEG = testCase.eegWithBlinkingEog();
            out = ArtefactDetect(EEG, testCase.options('Interpolate this channel'));

            testCase.verifyNotEmpty(out, 'The transformation returned nothing.');
            flags = testCase.flaggedCells(out);
            testCase.verifyEqual(sum(flags(5, :)), 6, ...
                ['A channel that cannot be reconstructed should be left flagged, ' ...
                 'not silently kept as if it were clean.']);
        end

        function anUnpositionedChannelIsNeverReconstructed(testCase)
        %ANUNPOSITIONEDCHANNELISNEVERRECONSTRUCTED  Directly on the helper,
        %   so the guard is pinned wherever it is called from, not only
        %   through ArtefactDetect.
            EEG = testCase.eegWithBlinkingEog();
            flags = false(5, size(EEG.data, 3));
            flags(5, 1:6) = true;               % VEOG, unpositioned
            flags(2, 1:2) = true;               % Cz, positioned

            [out, nInterpolated] = TransTools.InterpolateFlaggedCells(EEG, flags);

            testCase.verifyEqual(nInterpolated, 2, ...
                'Only the two positioned cells should have been reconstructed.');
            testCase.verifyTrue(all(isnan(out.data(5, :, 1))), ...
                'The unpositioned channel should have been left flagged.');
            testCase.verifyFalse(any(isnan(out.data(2, :, 1))), ...
                'The positioned channel should hold real numbers again.');

            mask = out.etc.alz.interpolated;
            testCase.verifyEqual(sum(mask(5, :)), 0, ...
                'A cell that was not reconstructed must not be recorded as interpolated.');
            testCase.verifyEqual(sum(mask(2, :)), 2);
        end

        function theReportedCountIsWhatWasActuallyRepaired(testCase)
        %THEREPORTEDCOUNTISWHATWASACTUALLYREPAIRED  The message used to
        %   report nnz(flags), so it claimed to have interpolated cells it
        %   had left flagged.
            EEG = testCase.eegWithBlinkingEog();
            flags = false(5, size(EEG.data, 3));
            flags(5, 1:6) = true;
            [~, nInterpolated] = TransTools.InterpolateFlaggedCells(EEG, flags);

            testCase.verifyEqual(nInterpolated, 0, ...
                'Nothing was reconstructable here, so nothing should be claimed.');
        end

        function everyChannelFlaggedInATrialIsLeftFlaggedRatherThanCrashing(testCase)
        %EVERYCHANNELFLAGGEDINATRIALISLEFTFLAGGEDRATHERTHANCRASHING  The bug
        %   itself. With no good channel left in a trial, eeg_interp's own
        %   spherical-spline maths hands MATLAB's legendre() an empty
        %   electrode-coordinate array; max() of that is [], not a scalar,
        %   so legendre's own `... || max(abs(x(:))) > 1` throws "Operands
        %   to the short-circuit AND/OR... must be convertible to logical
        %   scalars" instead of failing cleanly. Reproduced directly here
        %   (all 5 channels flagged in trial 1) before the guard existed.
            EEG = testCase.eegWithBlinkingEog();
            flags = false(5, size(EEG.data, 3));
            flags(:, 1) = true;    % every channel of trial 1
            flags(2, 2) = true;    % an ordinary, reconstructable cell elsewhere

            [out, nInterpolated] = TransTools.InterpolateFlaggedCells(EEG, flags);

            testCase.verifyEqual(nInterpolated, 1, ...
                'Only the reconstructable cell in trial 2 should count.');
            testCase.verifyTrue(all(isnan(out.data(:, :, 1)), 'all'), ...
                'A trial with nothing left to reconstruct from should be left flagged.');
            testCase.verifyFalse(any(isnan(out.data(2, :, 2))), ...
                'The ordinary cell in trial 2 should still have been interpolated.');
        end
    end

    methods (Access = private)
        function EEG = eegWithBlinkingEog(~)
        %EEGWITHBLINKINGEOG  Four positioned scalp channels well inside the
        %   threshold, and a VEOG that blinks past it on 6 of 10 trials.
        %   That is the ordinary case, not a contrived one.
            labels = {'Fz', 'Cz', 'Pz', 'Oz', 'VEOG'};
            EEG = makeTestEEG('nbchan', 5, 'labels', labels, 'trials', 10);

            base = eeg_emptyset();
            fn = fieldnames(EEG);
            for k = 1:numel(fn)
                base.(fn{k}) = EEG.(fn{k});
            end
            EEG = base;
            EEG.setname = 'fixture';
            EEG.xmin = EEG.times(1) / 1000;
            EEG.xmax = EEG.times(end) / 1000;

            EEG = TransTools.FillChanlocs(EEG, 'Alakazam:ArtefactDetectChannelScopeTest', ...
                TransTools.Template1005File('Alakazam:ArtefactDetectChannelScopeTest'));
            for c = 1:numel(EEG.chanlocs)
                if strcmp(EEG.chanlocs(c).labels, 'VEOG')
                    EEG.chanlocs(c).type = 'EOG';
                else
                    EEG.chanlocs(c).type = 'EEG';
                end
            end

            rng(3);
            EEG.data = 20 * randn(size(EEG.data));
            EEG.data(5, 40:80, 1:6) = 250;
        end

        function opts = options(~, scope)
            opts = struct('Method', {{'Absolute threshold'}}, ...
                'Minimum', -100, 'Maximum', 100, 'Threshold', 100, ...
                'Window', 200, 'Step', 50, 'TestStart', 0, 'TestStop', 0, ...
                'Scope', scope);
        end

        function flags = flaggedCells(~, EEG)
        %FLAGGEDCELLS  The NaN convention, read back the way
        %   dataQualityMetrics reads it.
            [nChan, ~, nTrials] = size(EEG.data);
            flags = false(nChan, nTrials);
            for t = 1:nTrials
                for c = 1:nChan
                    flags(c, t) = all(isnan(EEG.data(c, :, t)));
                end
            end
        end
    end
end
