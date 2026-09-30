classdef ChannelCompanionsTest < matlab.unittest.TestCase
%CHANNELCOMPANIONSTEST  The arrays an average carries beside its data (the
%   standard error, the aSME, the interpolation mask) stay in step with its
%   channels, whichever step changes them.
%
%   The reported failure: DeriveChannels on an average added a channel to
%   EEG.data and not to EEG.stErr, and the average view then failed to draw
%   the result with "Arrays have incompatible sizes", leaving a node that
%   looked unchanged from its parent. Three layers are checked here:
%   ApplyDerivations keeps the arrays itself, TransTools.invoke brings any
%   step's result in step (TransTools.AlignChannelCompanions), and the view
%   draws a node saved before either existed.
%
%   Run with: runtests('tests/ChannelCompanionsTest.m').
%
%   See also TRANSTOOLS.ALIGNCHANNELCOMPANIONS, TRANSTOOLS.APPLYDERIVATIONS,
%   TRANSTOOLS.INVOKE, AVERAGEVIEW.

    properties
        Folder   % where the stand-in transformations are written
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Views'), fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Transformations', 'DeriveChannels'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
            testCase.Folder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            writeStandIns(testCase.Folder);   % before the folder joins the path, so they are seen
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testCase.Folder));
        end
    end

    methods (Test)
        % ---- DeriveChannels -------------------------------------------------
        function derivingOnAnAverageKeepsItsErrorsInStep(testCase)
            avg = average({'C3', 'C4', 'Cz'}, 2);

            out = TransTools.invoke('DeriveChannels', avg, struct('derivations', 'let LRP = C3 - C4'));

            testCase.assertEqual(size(out.data, 1), 4);
            testCase.verifyEqual(size(out.stErr), size(out.data));
            testCase.verifyEqual(size(out.aSME), [4, 2]);
            testCase.verifyEqual(out.stErr(1:3, :, :), avg.stErr, 'The recorded channels keep theirs.');
            testCase.verifyEqual(out.aSME(1:3, :), avg.aSME);
        end

        function aDerivedChannelsErrorIsUnknownNotGuessed(testCase)
        %ADERIVEDCHANNELSERRORISUNKNOWNNOTGUESSED  The error of C3 - C4
        %   depends on how the two covary over trials, which an average no
        %   longer holds; independence would overstate it for neighbours.
            out = TransTools.invoke('DeriveChannels', average({'C3', 'C4'}, 1), ...
                struct('derivations', 'let LRP = C3 - C4'));

            testCase.verifyTrue(all(isnan(out.stErr(3, :))));
            testCase.verifyTrue(isnan(out.aSME(3)));
        end

        function reDerivingReplacesTheRowsRatherThanAddingThem(testCase)
            avg = average({'C3', 'C4', 'Cz'}, 2);
            once = TransTools.invoke('DeriveChannels', avg, struct('derivations', 'let LRP = C3 - C4'));

            twice = TransTools.invoke('DeriveChannels', once, struct('derivations', 'let LRP = C3 - Cz'));

            testCase.verifyEqual(size(twice.stErr, 1), 4);
            testCase.verifyEqual(size(twice.aSME, 1), 4);
        end

        function aDerivedChannelIsInterpolatedWhereItsSourcesWere(testCase)
            EEG = makeTestEEG('nbchan', 3, 'labels', {'C3', 'C4', 'Cz'}, 'trials', 4);
            EEG.etc.alz.interpolated = logical([0 0 0 0; 1 0 0 0; 0 0 1 0]);

            out = TransTools.invoke('DeriveChannels', EEG, ...
                struct('derivations', sprintf('let LRP = C3 - C4\nlet Mid = Cz * 2')));

            testCase.verifyEqual(out.etc.alz.interpolated(4, :), logical([1 0 0 0]));
            testCase.verifyEqual(out.etc.alz.interpolated(5, :), logical([0 0 1 0]));
        end

        % ---- the seam ---------------------------------------------------------
        function aStepThatDropsAChannelIsBroughtInStepByLabel(testCase)
        %ASTEPTHATDROPSACHANNELISBROUGHTINSTEPBYLABEL  DropSecondChannel
        %   knows nothing of stErr, like EEGLAB's pop_select; invoke keeps
        %   the rows of the channels that remain.
            avg = average({'C3', 'C4', 'Cz'}, 2);

            out = TransTools.invoke('DropSecondChannel', avg, struct());

            testCase.verifyEqual(out.stErr, avg.stErr([1 3], :, :));
            testCase.verifyEqual(out.aSME, avg.aSME([1 3], :));
        end

        function aStepThatKeepsItsOwnIsLeftAlone(testCase)
            avg = average({'C3', 'C4'}, 2);

            out = TransTools.invoke('HalveTheError', avg, struct());

            testCase.verifyEqual(out.stErr, avg.stErr / 2);
        end

        function theMaskKeepsItsTrialsOnAnAverage(testCase)
        %THEMASKKEEPSITSTRIALSONANAVERAGE  An average carries the mask of the
        %   trials it was made from, which are not its third dimension; only
        %   the rows follow the channels.
            avg = average({'C3', 'C4', 'Cz'}, 2);
            avg.etc.alz.interpolated = logical([1 0 0 0 0; 0 1 0 0 0; 0 0 1 0 0]);

            out = TransTools.invoke('DropSecondChannel', avg, struct());

            testCase.verifyEqual(out.etc.alz.interpolated, logical([1 0 0 0 0; 0 0 1 0 0]));
        end

        function anErrorOfTheWrongLengthBecomesUnknown(testCase)
            avg = average({'C3', 'C4'}, 2);
            resampled = avg;
            resampled.data = avg.data(:, 1:2:end, :);

            out = TransTools.AlignChannelCompanions(resampled, avg.chanlocs);

            testCase.verifyEqual(size(out.stErr), size(resampled.data));
            testCase.verifyTrue(all(isnan(out.stErr(:))));
            testCase.verifyEqual(out.aSME, avg.aSME, 'aSME has no samples dimension to lose.');
        end

        % ---- the view ---------------------------------------------------------
        function aNodeSavedBeforeTheFixStillDraws(testCase)
        %ANODESAVEDBEFORETHEFIXSTILLDRAWS  A DeriveChannels node already on
        %   disk has one error row fewer than channels. It must draw, with
        %   no band, rather than fail as it did.
            stale = average({'C3', 'C4', 'Cz'}, 2);
            stale.data(4, :, :) = stale.data(1, :, :) - stale.data(2, :, :);
            stale.chanlocs(4).labels = 'LRP';
            stale.nbchan = 4;

            fig = uifigure('Visible', 'off');
            testCase.addTeardown(@() delete(fig));
            view = AverageView(uitab(uitabgroup(fig)), stale);

            testCase.verifyNotEmpty(view);
        end
    end
end

% ======================================================================= %
function eeg = average(labels, nBins)
%AVERAGE  An averaged dataset with a known standard error and aSME: at
%   channel C the error is C everywhere and the aSME is 10 * C.
    eeg = makeTestEEG('nbchan', numel(labels), 'labels', labels, 'trials', nBins);
    eeg.DataFormat = 'Averaged';
    eeg.trials = 1;
    eeg.bindesc = struct('label', arrayfun(@(b) sprintf('Bin %d', b), 1:nBins, 'UniformOutput', false));
    eeg.stErr = repmat((1:numel(labels))', [1, size(eeg.data, 2), nBins]);
    eeg.aSME = repmat(10 * (1:numel(labels))', 1, nBins);
    eeg.File = 'average.mat';
    eeg.id = 'Average';
end

function writeStandIns(folder)
%WRITESTANDINS  Two transformations for the seam: one that changes the
%   channels as EEGLAB's own functions do, knowing nothing of stErr, and one
%   that maintains stErr itself.
    write(folder, 'DropSecondChannel', { ...
        'function [EEG, options] = DropSecondChannel(EEG, options)'
        '    keep = setdiff(1:size(EEG.data, 1), 2);'
        '    EEG.data = EEG.data(keep, :, :);'
        '    EEG.chanlocs = EEG.chanlocs(keep);'
        '    EEG.nbchan = numel(keep);'
        'end'});
    write(folder, 'HalveTheError', { ...
        'function [EEG, options] = HalveTheError(EEG, options)'
        '    EEG.stErr = EEG.stErr / 2;'
        'end'});
end

function write(folder, name, lines)
    fid = fopen(fullfile(folder, [name '.m']), 'w');
    fprintf(fid, '%s\n', lines{:});
    fclose(fid);
end
