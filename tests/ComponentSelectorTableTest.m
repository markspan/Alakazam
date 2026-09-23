classdef ComponentSelectorTableTest < matlab.unittest.TestCase
%COMPONENTSELECTORTABLETEST  The manual ICA selector's table: the verdict it
%   shows for each component, and which components a set of ticks means.
%
%   Both are pure functions precisely so they can be tested here rather than
%   inside a uifigure callback -- and the second one matters more than it
%   looks, because the table is sortable and a selection read by row
%   position would subtract the wrong components from the data.
%
%   Run with: runtests('tests/ComponentSelectorTableTest.m').

    properties (Constant)
        % ICLabel's own class list and order.
        Classes = {'Brain', 'Muscle', 'Eye', 'Heart', 'Line Noise', ...
                   'Channel Noise', 'Other'}
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations', 'RemoveComponents')));
        end
    end

    methods (Test)
        % --- the verdict column ------------------------------------------ %
        function theLabelIsTheClassIcLabelAssignedAndItsConfidence(testCase)
        %THELABELISTHECLASSICLABELASSIGNEDANDITSCONFIDENCE  The whole point
        %   of the column: the argmax, named, so a table of components can
        %   be scanned instead of read a row at a time.
            probs = testCase.probRow('Eye', 0.88);

            [~, ~, ~, data] = componentTableColumns(testCase.Classes, probs);

            testCase.verifyEqual(data{1, 2}, 'Eye 88%');
        end

        function theLabelSitsRightAfterTheComponentNumber(testCase)
        %THELABELSITSRIGHTAFTERTHECOMPONENTNUMBER  Before the seven
        %   probability columns, not after them: it is the summary of those
        %   columns, and a verdict placed past them is a verdict nobody
        %   scrolls to.
            [colNames, colFmt, colEdit] = componentTableColumns( ...
                testCase.Classes, testCase.probRow('Brain', 0.9));

            testCase.verifyEqual(colNames(1:3), {'IC', 'Label', 'Brain'});
            testCase.verifyEqual(colFmt{2}, 'char');
            testCase.verifyFalse(colEdit(2), 'The verdict is ICLabel''s, not the user''s.');
        end

        function theProbabilitiesRemainBesideTheVerdict(testCase)
        %THEPROBABILITIESREMAINBESIDETHEVERDICT  A confident call and a
        %   near-tie label identically, and only the numbers tell them
        %   apart, so the verdict must not replace them.
            probs = [0.10 0.05 0.40 0.03 0.02 0.02 0.38];

            [colNames, ~, ~, data] = componentTableColumns(testCase.Classes, probs);

            testCase.verifyEqual(data{1, 2}, 'Eye 40%');
            eyeCol   = find(strcmp(colNames, 'Eye'));
            otherCol = find(strcmp(colNames, 'Other'));
            testCase.verifyEqual(data{1, eyeCol}, 40);
            testCase.verifyEqual(data{1, otherCol}, 38, ...
                'The runner-up is what makes this call a close one.');
        end

        function everyComponentGetsItsOwnRowAndNumber(testCase)
            probs = [testCase.probRow('Brain', 0.9); ...
                     testCase.probRow('Eye', 0.7); ...
                     testCase.probRow('Muscle', 0.6)];

            [~, ~, ~, data] = componentTableColumns(testCase.Classes, probs);

            testCase.verifySize(data, [3, numel(testCase.Classes) + 4]);
            testCase.verifyEqual([data{:, 1}], [1 2 3]);
            testCase.verifyEqual(data(:, 2)', {'Brain 90%', 'Eye 70%', 'Muscle 60%'});
        end

        function anUnclassifiedComponentSaysSoRatherThanNamingAClass(testCase)
        %ANUNCLASSIFIEDCOMPONENTSAYSSORATHERTHANNAMINGACLASS  The argmax of
        %   all-NaN is not a decision, and printing whichever class sorts
        %   first would present one as if it were.
            [~, ~, ~, data] = componentTableColumns(testCase.Classes, nan(1, 7));

            testCase.verifyEqual(data{1, 2}, 'unclassified');
        end

        function aClassificationShorterThanTheClassListLeavesTheRestBlank(testCase)
        %ACLASSIFICATIONSHORTERTHANTHECLASSLISTLEAVESTHERESTBLANK  A
        %   classification can arrive narrower than the class list (an older
        %   ICLabel, a hand-built struct). The classes it does not cover have
        %   no probability, and blank says that; a 0 would claim the
        %   component was measured and found not to be one.
            [colNames, ~, ~, data] = componentTableColumns(testCase.Classes, [0.2 0.7]);

            testCase.verifyEqual(data{1, 2}, 'Muscle 70%', ...
                'The verdict still stands over the classes that were reported.');
            testCase.verifyEqual(data{1, find(strcmp(colNames, 'Brain'))}, 20);
            testCase.verifyEmpty(data{1, find(strcmp(colNames, 'Heart'))}, ...
                'Not reported, so not 0%.');
        end

        function aComponentWithNoProbabilitiesAtAllIsUnclassified(testCase)
            [~, ~, ~, data] = componentTableColumns(testCase.Classes, zeros(1, 0));

            testCase.verifyEqual(data{1, 2}, 'unclassified');
        end

        function aMissingProbabilityRendersBlankRatherThanZero(testCase)
            row = testCase.probRow('Eye', 0.8);
            row(strcmp(testCase.Classes, 'Heart')) = NaN;

            [colNames, ~, ~, data] = componentTableColumns(testCase.Classes, row);

            testCase.verifyEqual(data{1, 2}, 'Eye 80%', ...
                'One missing class does not stop the rest making a verdict.');
            testCase.verifyEmpty(data{1, find(strcmp(colNames, 'Heart'))});
        end

        % --- the dipole column, kept working across the change ----------- %
        function aFailedDipoleFitSaysNoFitRatherThanNothing(testCase)
            probs = [testCase.probRow('Brain', 0.9); testCase.probRow('Eye', 0.8)];

            [colNames, ~, ~, data] = componentTableColumns(testCase.Classes, probs, [0.07; NaN]);

            rvCol = find(strcmp(colNames, 'Dipole RV %'));
            testCase.verifyEqual(data{1, rvCol}, '7');
            testCase.verifyEqual(data{2, rvCol}, 'no fit', ...
                'An empty cell would read as "not measured", which is not what happened.');
        end

        function theDipoleColumnIsBlankThroughoutWhenFittingWasUnavailable(testCase)
            probs = [testCase.probRow('Brain', 0.9); testCase.probRow('Eye', 0.8)];

            [colNames, ~, ~, data] = componentTableColumns(testCase.Classes, probs, []);

            rvCol = find(strcmp(colNames, 'Dipole RV %'));
            testCase.verifyEqual(data(:, rvCol)', {'no fit', 'no fit'});
        end

        function onlyTheRemoveColumnIsEditable(testCase)
        %ONLYTHEREMOVECOLUMNISEDITABLE  Everything else is a reported
        %   measurement; a table that let one be typed over would invite an
        %   edit that changes nothing but what the user believes.
            [colNames, ~, colEdit] = componentTableColumns( ...
                testCase.Classes, testCase.probRow('Brain', 0.9));

            testCase.verifyEqual(colNames{end}, 'Remove');
            testCase.verifyTrue(colEdit(end));
            testCase.verifyFalse(any(colEdit(1:end - 1)));
        end

        % --- ticks to component numbers ---------------------------------- %
        function nothingTickedRemovesNothing(testCase)
            [~, ~, ~, data] = componentTableColumns(testCase.Classes, ...
                repmat(testCase.probRow('Brain', 0.9), 4, 1));

            testCase.verifyEmpty(componentsTicked(data));
        end

        function theTickedComponentsComeBackInOrder(testCase)
            [~, ~, ~, data] = componentTableColumns(testCase.Classes, ...
                repmat(testCase.probRow('Brain', 0.9), 5, 1));
            data{4, end} = true;
            data{2, end} = true;

            testCase.verifyEqual(componentsTicked(data), [2 4]);
        end

        function aSortedTableStillRemovesTheComponentThatWasTicked(testCase)
        %ASORTEDTABLESTILLREMOVESTHECOMPONENTTHATWASTICKED  The reason the
        %   selection is read from each row's own IC cell. Sorting by Label
        %   is the main reason to sort at all, and it moves component 7 to
        %   the top; a selection read by row position would then have
        %   subtracted component 1 from the data and reported component 1 as
        %   removed, with nothing anywhere to show it was the wrong one.
            [~, ~, ~, data] = componentTableColumns(testCase.Classes, ...
                [repmat(testCase.probRow('Brain', 0.9), 6, 1); ...
                 testCase.probRow('Eye', 0.95)]);
            sorted = data([7 1:6], :);      % as sorting by Label would leave it
            sorted{1, end} = true;          % tick the eye component, now row 1

            testCase.verifyEqual(componentsTicked(sorted), 7);
        end

        function anUntouchedTickCellIsNotMistakenForATick(testCase)
        %ANUNTOUCHEDTICKCELLISNOTMISTAKENFORATICK  A uitable can hand back
        %   [] for a cell that was never edited, and [] must not count as
        %   ticked: it would remove a component the user never chose.
            [~, ~, ~, data] = componentTableColumns(testCase.Classes, ...
                repmat(testCase.probRow('Brain', 0.9), 3, 1));
            data{1, end} = [];
            data{2, end} = true;

            testCase.verifyEqual(componentsTicked(data), 2);
        end

        function emptyTableData(testCase)
            testCase.verifyEmpty(componentsTicked({}));
        end
    end

    methods (Access = private)
        function row = probRow(testCase, class, p)
        %PROBROW  One ICLabel probability row whose argmax is CLASS at P,
        %   with the remainder spread over the other classes so the row sums
        %   to 1 as a real classification does.
            n = numel(testCase.Classes);
            row = repmat((1 - p) / (n - 1), 1, n);
            row(strcmp(testCase.Classes, class)) = p;
        end
    end
end
