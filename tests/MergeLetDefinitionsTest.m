classdef MergeLetDefinitionsTest < matlab.unittest.TestCase
%MERGELETDEFINITIONSTEST  Loading a measure file adds to the dialog rather
%   than replacing it, and its derived channels have to merge without
%   redefining anything.
%
%   Replacing the whole dialog on Load was destructive: a table built up
%   over several minutes vanished the moment someone opened a preset to see
%   what was in it, and the let block went with it even when the loaded
%   file had none, which every shipped preset does.
%
%   Appending the let block instead is not enough on its own.
%   measureDerivations appends each derived channel to the dataset as it
%   evaluates the block, so a second definition of the same name raises
%   "already exists in this dataset" at OK time, in a message that names
%   the channel and gives no hint that a Load caused it. The merge below
%   keeps the analyst's definition and reports which of the file's were not
%   used.
%
%   Run with: runtests('tests/MergeLetDefinitionsTest.m').
%
%   See also MERGELETDEFINITIONS, MEASUREDIALOG, MEASUREDERIVATIONS.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Support')));
        end
    end

    methods (Test)
        function loadingIntoAnEmptyBlockJustTakesTheFile(testCase)
            [merged, kept] = mergeLetDefinitions('', 'let ROI = (P7 + P8) / 2');

            testCase.verifyEqual(strtrim(merged), 'let ROI = (P7 + P8) / 2');
            testCase.verifyEmpty(kept);
        end

        function aFileWithNoDefinitionsLeavesTheBlockAlone(testCase)
        %AFILEWITHNODEFINITIONSLEAVESTHEBLOCKALONE  The case that made this
        %   worth fixing: every shipped preset has no let block, and
        %   replacing wiped whatever the analyst had written.
            existing = 'let LRP = C3 - C4';
            [merged, kept] = mergeLetDefinitions(existing, '');

            testCase.verifyEqual(merged, existing);
            testCase.verifyEmpty(kept);
        end

        function bothBlocksSurviveWhenTheNamesDiffer(testCase)
            [merged, kept] = mergeLetDefinitions('let LRP = C3 - C4', ...
                'let ROI = (P7 + P8) / 2');

            testCase.verifySubstring(merged, 'let LRP = C3 - C4');
            testCase.verifySubstring(merged, 'let ROI = (P7 + P8) / 2');
            testCase.verifyEmpty(kept);
        end

        function aRepeatedNameKeepsTheExistingDefinition(testCase)
        %AREPEATEDNAMEKEEPSTHEEXISTINGDEFINITION  And says so, because the
        %   loaded windows may have been written against the other formula.
            [merged, kept] = mergeLetDefinitions('let LRP = C3 - C4', ...
                'let LRP = C4 - C3');

            testCase.verifySubstring(merged, 'let LRP = C3 - C4');
            testCase.verifyEmpty(strfind(merged, 'C4 - C3'), ...
                'The loaded definition must not be added alongside.'); %#ok<STRIFCND>
            testCase.verifyEqual(kept, {'LRP'});
        end

        function nameMatchingIgnoresCase(testCase)
        %NAMEMATCHINGIGNORESCASE  measureDerivations compares the new name
        %   against existing channel labels with strcmpi, so "lrp" and
        %   "LRP" collide there. Merging case-sensitively would let the
        %   duplicate through to fail later.
            [merged, kept] = mergeLetDefinitions('let LRP = C3 - C4', ...
                'let lrp = C4 - C3');

            testCase.verifyEqual(kept, {'lrp'});
            testCase.verifyEmpty(strfind(merged, 'C4 - C3')); %#ok<STRIFCND>
        end

        function aCommentedDefinitionBlocksNothing(testCase)
        %ACOMMENTEDDEFINITIONBLOCKSNOTHING  A commented-out line defines no
        %   channel, so it must not stop the file's real one being added.
            [merged, kept] = mergeLetDefinitions('% let ROI = (P7 + P8) / 2', ...
                'let ROI = (PO7 + PO8) / 2');

            testCase.verifySubstring(merged, 'let ROI = (PO7 + PO8) / 2');
            testCase.verifyEmpty(kept);
        end

        function aTrailingCommentDoesNotHideARealDefinition(testCase)
            [~, kept] = mergeLetDefinitions('let ROI = P7 + P8   % left ROI', ...
                'let ROI = PO7 + PO8');

            testCase.verifyEqual(kept, {'ROI'}, ...
                'The existing definition is real despite the trailing comment.');
        end

        function blankLinesAndNonLetLinesAreIgnored(testCase)
            [merged, kept] = mergeLetDefinitions(sprintf('\n\n%% a note\n'), ...
                sprintf('\nlet ROI = P7 + P8\n\n'));

            testCase.verifySubstring(merged, 'let ROI = P7 + P8');
            testCase.verifyEmpty(kept);
        end

        function everyRepeatedNameIsReportedOnce(testCase)
            existing = sprintf('let A = C3 - C4\nlet B = P7 + P8');
            loaded = sprintf('let A = Cz\nlet A = Fz\nlet B = Pz\nlet C = Oz');
            [merged, kept] = mergeLetDefinitions(existing, loaded);

            testCase.verifyEqual(sort(kept), {'A', 'B'});
            testCase.verifySubstring(merged, 'let C = Oz');
        end

        function theDialogUsesTheSharedHelper(testCase)
        %THEDIALOGUSESTHESHAREDHELPER  The logic above only protects anyone
        %   if the dialog actually calls it. Read rather than run, since
        %   MeasureDialog needs a figure.
            root = fileparts(fileparts(mfilename('fullpath')));
            src = fileread(fullfile(root, 'src', 'Transformations', 'Measure', ...
                'MeasureDialog.m'));

            testCase.verifySubstring(src, 'mergeLetDefinitions(');
            testCase.verifySubstring(src, 'table.Data = [table.Data; loadedData];');
            testCase.verifyEmpty(strfind(src, 'table.Data = loadedData;'), ...
                'Load must add to the table, not replace it.'); %#ok<STRIFCND>
        end
    end
end
