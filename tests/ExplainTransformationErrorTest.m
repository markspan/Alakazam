classdef ExplainTransformationErrorTest < matlab.unittest.TestCase
%EXPLAINTRANSFORMATIONERRORTEST  What the dialog says when a step, or what
%   follows it, fails (explainTransformationError).
%
%   The reported message read "DeriveChannels could not run on this dataset
%   ... the selected dataset is not quite the right kind of data", when
%   DeriveChannels had run and the view drawing its result had failed. The
%   cases below pin the distinctions that message lacked: which phase
%   failed, what became of the result, what the data was, and whether the
%   fault is likely the data's or the code's.
%
%   Run with: runtests('tests/ExplainTransformationErrorTest.m').
%
%   See also EXPLAINTRANSFORMATIONERROR, ALAKAZAM.ONTRANSFORMATION.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Support'), fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function aFailedDrawingBlamesTheViewAndSaysTheNodeIsGone(testCase)
            result = averageOf(34, 3);

            [title, message] = explainTransformationError('DeriveChannels', shapeError(), ...
                'Phase', 'draw', 'Dataset', result);
            text = strjoin(message, newline);

            testCase.verifyEqual(title, 'Couldn''t show the result of DeriveChannels');
            testCase.verifySubstring(text, 'DeriveChannels ran, but its result could not be drawn');
            testCase.verifySubstring(text, 'has not been added to the tree');
            testCase.verifySubstring(text, 'The fault is in the view');
            testCase.verifySubstring(text, 'an average, 34 channels by 3 bins of 250 samples');
            testCase.verifySubstring(text, 'Technical detail (MATLAB:sizeDimensionsMustMatch)');
            testCase.verifyFalse(contains(text, 'could not run'), 'It did run.');
        end

        function aRecalculationKeepsItsResult(testCase)
            [~, message] = explainTransformationError('Filter', shapeError(), ...
                'Phase', 'draw', 'Kept', true);

            testCase.verifySubstring(strjoin(message, newline), 'it is in the tree but cannot be shown');
        end

        function aShapeErrorInTheStepNamesTheDataItWasGiven(testCase)
            epoched = makeTestEEG('nbchan', 32, 'trials', 120);

            [title, message] = explainTransformationError('Baseline', shapeError(), 'Dataset', epoched);
            text = strjoin(message, newline);

            testCase.verifyEqual(title, 'Couldn''t run Baseline');
            testCase.verifySubstring(text, 'segmented data, 32 channels by 120 epochs');
            testCase.verifySubstring(text, 'did not fit together');
            testCase.verifyFalse(contains(text, 'view'), 'A failure inside the step is not the view''s.');
        end

        function anyOtherMatlabErrorIsCalledADefect(testCase)
            try
                noSuchFunctionAnywhere_alakazam();
            catch ME
            end

            [~, message] = explainTransformationError('Baseline', ME, 'Dataset', makeTestEEG());
            text = strjoin(message, newline);

            testCase.verifySubstring(text, 'most likely a defect in Baseline');
            testCase.verifyFalse(contains(text, 'did not fit together'));
        end

        function anOwnGuardSpeaksForItself(testCase)
            ME = MException('Alakazam:Baseline', 'Problem in Baseline: this needs segmented data.');

            [~, message] = explainTransformationError('Baseline', ME, 'Dataset', makeTestEEG());

            testCase.verifyEqual(message, ...
                {'I''m sorry, but Baseline could not run on this dataset:', '', 'this needs segmented data.'});
        end

        function noMessageUsesADash(testCase)
        %NOMESSAGEUSESADASH  The project writes no em dash, and no " -- "
        %   standing in for one, in anything a reader sees.
            cases = {{'Phase', 'run'}, {'Phase', 'save'}, {'Phase', 'draw'}, {'Phase', 'draw', 'Kept', true}};
            for c = cases
                [title, message] = explainTransformationError('Filter', shapeError(), c{1}{:}, ...
                    'Dataset', makeTestEEG());
                text = strjoin([{title}, message], newline);
                testCase.verifyFalse(contains(text, char(8212)) || contains(text, ' -- '), ...
                    strjoin(cellfun(@(v) char(string(v)), c{1}, 'UniformOutput', false), ' '));
            end
        end
    end
end

% ======================================================================= %
function ME = shapeError()
%SHAPEERROR  A real "Arrays have incompatible sizes", with a stack.
    try
        ME = []; %#ok<NASGU>
        x = ones(2, 3) + ones(3, 2); %#ok<NASGU>
    catch ME
    end
end

function eeg = averageOf(nChan, nBins)
    eeg = makeTestEEG('nbchan', nChan, 'trials', nBins, 'srate', 250, 'epochMs', [-200, 796]);
    eeg.DataFormat = 'Averaged';
    eeg.trials = 1;
end
