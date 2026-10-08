classdef SourceParsesTest < matlab.unittest.TestCase
%SOURCEPARSESTEST  Every MATLAB file in src and tests is valid MATLAB.
%
%   A file with a syntax error fails only when something calls it, and a
%   ribbon action that no test drives is called first by a user: an
%   unterminated character vector in onExportFieldTripScript reached a
%   release that way on 8 October 2026, its tests having driven the
%   collector it calls but never the handler itself. MATLAB's own parser
%   answers the question for every file at once: checkcode with -m2 reports
%   errors only (an unterminated string, a parse error, an unmatched end),
%   not its style advice, and reads the 800 or so files in a few seconds.
%
%   See also CHECKCODE, EXPORTANALYSISSCRIPTTEST.

    methods (Test)
        function everyFileParses(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            files = [dir(fullfile(root, 'src', '**', '*.m')); dir(fullfile(root, 'tests', '**', '*.m'))];
            testCase.assertGreaterThan(numel(files), 100, 'The source files were not found.');
            problems = {};
            for k = 1:numel(files)
                file = fullfile(files(k).folder, files(k).name);
                for issue = reshape(checkcode(file, '-m2', '-struct', '-id'), 1, [])
                    problems{end + 1} = sprintf('%s:%d %s %s', erase(file, [root filesep]), ...
                        issue.line, issue.id, issue.message); %#ok<AGROW>
                end
            end
            testCase.verifyEmpty(problems, sprintf('Not valid MATLAB:\n%s', strjoin(problems, newline)));
        end
    end
end
