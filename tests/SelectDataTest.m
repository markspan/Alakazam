classdef SelectDataTest < matlab.unittest.TestCase
%SELECTDATATEST  Unit tests for src/Transformations/SelectData/SelectData.m.
%
%   THE BUG THIS PINS. SelectDataDialog always builds a time/points range as
%   a ROW vector ([lo.Value hi.Value]), but jsondecode has no notion of row
%   vs column and turns any JSON numeric array back into a COLUMN on Apply
%   Template (confirmed directly: jsondecode(jsonencode([883 8594])) comes
%   back 2x1) -- so a SelectData step with a time or point range, saved as a
%   template and later applied, passed pop_select a column vector, which it
%   rejects outright ("Time/point range must contain 2 columns exactly").
%
%   Exercised here via the 'points' field (sample indices, no event/epoch
%   linkage needed): 'time' and 'points' share the exact same rangeArgs
%   helper and its one (:)' fix, so a bug fixed for one is fixed for both --
%   'time' cropping was separately confirmed end to end via a real
%   pop_epoch-derived dataset (a hand-built fixture has no .event/.epoch
%   linkage back to a continuous recording, which pop_select's own 'time'
%   handling on epoched data needs and this file's fixture does not build).
%   Every test here builds its options the way a template round trip would
%   (an explicit COLUMN, not the row shape the dialog itself produces), so a
%   revert of the (:)' fix in rangeArgs fails these for the right reason.
%
%   Run with: runtests('tests/SelectDataTest.m').
%
%   See also SELECTDATADIALOG.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Transformations', 'SelectData'), ...
                     fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function aTemplateRoundTrippedPointRangeStillCropsTheData(testCase)
        %ATEMPLATEROUNDTRIPPEDPOINTRANGESTILLCROPSTHEDATA  A column-shaped
        %   range (what jsondecode actually produces, see this class' own
        %   header comment) must still work, not throw.
            EEG = testCase.completeSet(makeTestEEG('nbchan', 2, 'trials', 2, 'epochMs', [-200, 596]));
            opts = offOptions(EEG);
            opts.points = struct('mode', 'Keep', 'range', [10; 50]); % COLUMN, not row
            result = SelectData(EEG, opts);
            testCase.verifyEqual(size(result.data, 2), 40);
            testCase.verifyLessThan(size(result.data, 2), size(EEG.data, 2), ...
                'The point-range crop should have dropped some samples.');
        end

        function aRowShapedRangeStillWorksToo(testCase)
        %AROWSHAPEDRANGESTILLWORKSTOO  The dialog's own native shape (a row)
        %   must keep working -- (:)' is a no-op on a row, not a special case.
            EEG = testCase.completeSet(makeTestEEG('nbchan', 2, 'trials', 2, 'epochMs', [-200, 596]));
            opts = offOptions(EEG);
            opts.points = struct('mode', 'Keep', 'range', [10, 50]); % ROW
            result = SelectData(EEG, opts);
            testCase.verifyEqual(size(result.data, 2), 40);
        end
    end

    methods (Access = private)
        function EEG = completeSet(~, EEG)
        %COMPLETESET  The fixture laid over EEGLAB's own empty set, so
        %   pop_select finds every field it reads (.etc, chaninfo, dipfit,
        %   ...) instead of discovering them one error at a time. Same
        %   pattern as ReRefTest's/NativeExportEquivalenceTest's own
        %   completeSet.
            base = eeg_emptyset();
            f = fieldnames(EEG);
            for k = 1:numel(f)
                base.(f{k}) = EEG.(f{k});
            end
            EEG = base;
            EEG.xmin = EEG.times(1);
            EEG.xmax = EEG.times(end);
            EEG.setname = 'fixture';
        end
    end
end

function opts = offOptions(EEG)
%OFFOPTIONS  Every SelectData field switched off, matching SelectDataDialog's
%   own default shape -- a test then turns on just the one field it exercises.
    opts = struct( ...
        'channels', struct('mode', '(off)', 'labels', {{}}), ...
        'time',     struct('mode', '(off)', 'range', [0 0]), ...
        'points',   struct('mode', '(off)', 'range', [1, size(EEG.data, 2)]), ...
        'trials',   struct('mode', '(off)', 'indices', []));
end
