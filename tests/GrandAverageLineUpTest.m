classdef GrandAverageLineUpTest < matlab.unittest.TestCase
%GRANDAVERAGELINEUPTEST  A grand average averages like with like: the same
%   channel, by label, at the same time, in a bin every subject has data for.
%
%   It used to pair channels by position, so two subjects holding the same
%   channels in different orders averaged Fz with Pz in silence; to accept epochs
%   of one length that start at different times; and to blank a bin without a
%   word when one subject had nothing in it.
%
%   See also GRANDAVERAGE, GRANDAVERAGETEST.
    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'src')));
        end
    end

    methods (Test)
        function channelsAreMatchedByLabelNotPosition(testCase)
            a = subject(reshape([1 2 3], 3, 1));
            b = reorder(a, [3 2 1]);
            r = GrandAverage(testCase.files({a, b}), false);
            testCase.verifyEqual(r.data(:, 1, 1), [1; 2; 3], 'AbsTol', 1e-12);
            testCase.verifyEqual({r.chanlocs.labels}, {a.chanlocs.labels});
        end

        function theErrorsAndSmesFollowTheLabels(testCase)
            a = subject(reshape([1 2 3], 3, 1));
            a.aSME = repmat([10; 20; 30], 1, 2);
            b = reorder(a, [3 2 1]);
            r = GrandAverage(testCase.files({a, b}), false);
            testCase.verifyEqual(r.aSME(:, 1), sqrt(2 * [10; 20; 30] .^ 2) / 2, 'AbsTol', 1e-12);
            testCase.verifyEqual(r.stErr(:, 1, 1), [0; 0; 0], 'AbsTol', 1e-12, ...
                'The same values on the same labels have no spread between subjects.');
        end

        function differentChannelsAreRefused(testCase)
            a = subject(reshape([1 2 3], 3, 1));
            b = a;
            b.chanlocs(2).labels = 'Oz';
            testCase.verifyError(@() GrandAverage(testCase.files({a, b}), false), 'Alakazam:GrandAverage');
        end

        function aShiftedEpochIsRefused(testCase)
            a = subject(reshape([1 2 3], 3, 1));
            b = a;
            b.times = b.times + 100;
            testCase.verifyError(@() GrandAverage(testCase.files({a, b}), false), 'Alakazam:GrandAverage');
        end

        function anEmptyBinIsRefusedByName(testCase)
            a = subject(reshape([1 2 3], 3, 1));
            b = a;
            b.data(:, :, 2) = NaN;
            files = testCase.files({a, b});
            testCase.verifyError(@() GrandAverage(files, false), 'Alakazam:GrandAverage');
            try
                GrandAverage(files, false);
            catch err
                testCase.verifySubstring(err.message, 'bin "B"');
            end
        end

        function anEmptyChannelIsSaidAndStaysBlank(testCase)
            a = subject(reshape([1 2 3], 3, 1));
            b = a;
            b.data(2, :, 1) = NaN;
            files = testCase.files({a, b});
            r = testCase.verifyWarning(@() GrandAverage(files, false), 'Alakazam:GrandAverage:emptyChannel');
            testCase.verifyTrue(all(isnan(r.data(2, :, 1))));
            testCase.verifyFalse(any(isnan(r.data(1, :, 1))));
        end

        function mapsAreMatchedByLabelToo(testCase)
            a = mapSubject();
            b = a;
            b.ersp = b.ersp(end:-1:1, :, :, :);
            b.chanlocs = b.chanlocs(end:-1:1);
            r = GrandAverage(testCase.files({a, b}), false);
            testCase.verifyEqual(r.ersp, a.ersp, 'AbsTol', 1e-12);
        end

        function aMapWithAnEmptyBinIsRefused(testCase)
            a = mapSubject();
            b = a;
            b.ersp(:, :, :, 2) = NaN;
            testCase.verifyError(@() GrandAverage(testCase.files({a, b}), false), 'Alakazam:GrandAverage');
        end

        function aBlankMapCellIsNotTheMeanOfTheOthers(testCase)
            a = mapSubject();
            b = a;
            b.ersp(1, 1, 1, 1) = NaN;
            r = GrandAverage(testCase.files({a, b}), false);
            testCase.verifyTrue(isnan(r.ersp(1, 1, 1, 1)));
            testCase.verifyFalse(isnan(r.ersp(2, 1, 1, 1)));
        end

        function mapsWithDifferentFrequenciesAreRefused(testCase)
            a = mapSubject();
            b = a;
            b.freqs = b.freqs + 1;
            testCase.verifyError(@() GrandAverage(testCase.files({a, b}), false), 'Alakazam:GrandAverage');
        end
    end

    methods
        function paths = files(testCase, subjects)
            folder = tempname();
            mkdir(folder);
            testCase.addTeardown(@() rmdir(folder, 's'));
            paths = cell(1, numel(subjects));
            for i = 1:numel(subjects)
                EEG = subjects{i};
                paths{i} = fullfile(folder, sprintf('s%d.mat', i));
                save(paths{i}, 'EEG');
            end
        end
    end
end

function EEG = subject(values)
    nPnts = 20;
    data = repmat(values, 1, nPnts, 2);
    EEG = struct('data', data, 'stErr', zeros(size(data)), 'aSME', zeros(size(values, 1), 2), ...
        'chanlocs', struct('labels', {'Fz', 'Cz', 'Pz'}), 'times', (0:nPnts - 1) * 4, 'srate', 250, ...
        'nbchan', 3, 'trials', 1, 'pnts', nPnts, 'DataFormat', "Averaged", 'id', 'x', 'setname', 'x', ...
        'bindesc', struct('index', {1, 2}, 'label', {'A', 'B'}, 'combo', {[], []}, 'n', {20, 20}), ...
        'event', struct([]), 'epoch', struct([]));
end

function EEG = reorder(EEG, order)
    EEG.data = EEG.data(order, :, :);
    EEG.stErr = EEG.stErr(order, :, :);
    EEG.aSME = EEG.aSME(order, :);
    EEG.chanlocs = EEG.chanlocs(order);
end

function EEG = mapSubject()
    ersp = reshape(1:3 * 4 * 5 * 2, 3, 4, 5, 2);
    EEG = struct('ersp', double(ersp), 'freqs', 1:4, 'times', (0:4) * 10, ...
        'chanlocs', struct('labels', {'Fz', 'Cz', 'Pz'}), 'id', 'x', 'setname', 'x', ...
        'bindesc', struct('index', {1, 2}, 'label', {'A', 'B'}), 'event', struct([]), 'epoch', struct([]));
end
