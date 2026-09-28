classdef NaNCellsAreBlankTest < matlab.unittest.TestCase
%NANCELLSAREBLANKTEST  An image leaves a missing value blank instead of
%   drawing it in its lowest colour (manual issues M6 and M7).
%
%   An image draws NaN as the bottom of its colour scale, so a missing value
%   passed for a real minimum: a rejected trial in the ERP image for the most
%   negative voltage, a time-frequency cell whose trials were all rejected
%   for the strongest decrease, a coherence cell outside a method's band for
%   no coherence at all. showImageData makes those cells transparent, and
%   EpochView, TimeFrequencyView and CoherenceView all draw through it; each
%   is checked with one missing value among real ones.
%
%   Run with: runtests('tests/NaNCellsAreBlankTest.m').
%
%   See also SHOWIMAGEDATA, EPOCHVIEW, TIMEFREQUENCYVIEW, COHERENCEVIEW.

    properties
        Figure
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Views'), fullfile(root, 'src', 'Transformations')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (TestMethodSetup)
        function openFigure(testCase)
            try
                testCase.Figure = uifigure('Visible', 'off');
            catch ME
                testCase.assumeFail(['A uifigure could not be created here: ' ME.message]);
            end
            testCase.addTeardown(@() delete(testCase.Figure));
        end
    end

    methods (Test)
        function showImageDataMakesJustTheNaNCellsTransparent(testCase)
            img = imagesc(uiaxes(testCase.Figure), zeros(2, 2));
            showImageData(img, [1, NaN; 3, 4]);
            testCase.verifyEqual(img.CData, [1, NaN; 3, 4]);
            testCase.verifyEqual(img.AlphaData, [1, 0; 1, 1]);
            testCase.verifyEqual(char(img.AlphaDataMapping), 'none');
        end

        function aRejectedTrialInTheErpImageIsBlank(testCase)
            eeg = epoched();
            eeg.data(1, :, 2) = NaN;   % trial 2 rejected, as ArtefactDetect leaves it
            view = EpochView(testCase.newTab(), eeg);

            alpha = view.HeatImage.AlphaData;
            testCase.verifyEqual(nnz(all(alpha == 0, 2)), 1, 'One row, the rejected trial, is blank.');
            testCase.verifyEqual(nnz(alpha == 0), size(alpha, 2), 'And nothing else is.');
        end

        function aTimeFrequencyCellWithNoValueIsBlank(testCase)
            eeg = mapped('ersp');
            eeg.ersp(1, 2, 3, 1) = NaN;
            view = TimeFrequencyView(testCase.newTab(), eeg);

            testCase.verifyEqual(find(view.Images(1).AlphaData == 0), sub2ind([3, 4], 2, 3));
            testCase.verifyTrue(all(view.Images(2).AlphaData(:) == 1), 'The other bin is whole.');
        end

        function aCoherenceCellWithNoValueIsBlank(testCase)
            eeg = mapped('coherence');
            eeg.coherence(1, 2, 3, 1) = NaN;
            view = CoherenceView(testCase.newTab(), eeg);

            testCase.verifyEqual(find(view.Images(1).AlphaData == 0), sub2ind([3, 4], 2, 3));
        end
    end

    methods (Access = private)
        function tab = newTab(testCase)
            tab = uitab(uitabgroup(testCase.Figure));
        end
    end
end

% ======================================================================= %
function eeg = mapped(field)
%MAPPED  Two channels and two bins of a 3-frequency by 4-time map in FIELD
%   ('ersp' or 'coherence'), every value real and between 0 and 1.
    rng(7);
    values = rand(2, 3, 4, 2);
    eeg = struct('nbchan', 2, 'chanlocs', struct('labels', {'Cz', 'Pz'}), ...
        'bindesc', struct('label', {'A', 'B'}));
    if strcmp(field, 'ersp')
        eeg.ersp = values;
        eeg.freqs = [4, 8, 16];
        eeg.times = [0, 100, 200, 300];
    else
        eeg.coherence = values;
        eeg.cohFreqs = [4, 8, 16];
        eeg.cohTimes = [0, 100, 200, 300];
        eeg.cohRef = 'Oz';
    end
end

function EEG = epoched()
%EPOCHED  Four trials on two channels in bins A and B (EpochViewBinTest's).
    rng(4);
    times = -100:10:390;
    EEG = struct('data', randn(2, numel(times), 4), 'srate', 100, 'times', times, ...
        'pnts', numel(times), 'trials', 4, 'nbchan', 2, 'xmin', times(1) / 1000, ...
        'xmax', times(end) / 1000, 'DataFormat', 'EPOCHED', ...
        'chanlocs', struct('labels', {'Cz', 'Pz'}));
    EEG.event = struct('type', {'s', 's', 's', 's'}, 'latency', {11, 61, 111, 161}, ...
        'rating', {9, 1, 4, 7}, 'bini', {1, 2, 1, 2}, 'epoch', {1, 2, 3, 4});
    EEG.epoch = struct('event', {1, 2, 3, 4}, 'eventtype', {'s', 's', 's', 's'}, ...
        'eventlatency', {0, 0, 0, 0}, 'bini', {1, 2, 1, 2});
    EEG.bindesc = struct('index', {1, 2}, 'label', {'A', 'B'}, 'combo', {[], []}, ...
        'trials', {[1 3], [2 4]});
end
