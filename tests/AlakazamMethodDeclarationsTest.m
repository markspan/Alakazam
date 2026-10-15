classdef AlakazamMethodDeclarationsTest < matlab.unittest.TestCase
%ALAKAZAMMETHODDECLARATIONSTEST  Every method file in src/@Alakazam is
%   declared in Alakazam.m, with the same inputs.
%
%   MATLAB takes a method's signature from its declaration in the classdef,
%   not from the method's own file. A file given another input than its
%   declaration has is refused at the call, "Too many input arguments",
%   which is how Install in the plugin list failed in V0.4.5.3: the file
%   took (this, source, repo), the declaration still said (this, source),
%   and the tests had called the file through stand-ins, never through the
%   class. An undeclared file fails without a word.
%
%   Read from the files and the class's own metadata; nothing is run.
%
%   Run with: runtests('tests/AlakazamMethodDeclarationsTest.m').
%
%   See also OTHERTABTAGSTEST.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'src')));
        end
    end

    methods (Test)
        function everyMethodFileHasItsDeclaredInputs(testCase)
            list = AlakazamMethodDeclarationsTest.declared();
            classdefText = fileread(fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
                'src', '@Alakazam', 'Alakazam.m'));
            checked = 0;
            for f = AlakazamMethodDeclarationsTest.methodFiles()
                [name, inputs] = AlakazamMethodDeclarationsTest.fileSignature(f{1});
                % A declaration is a bare signature on its own line; an
                % undeclared file is still a method, public, with unknown
                % inputs, which the class's metadata shows as varargin.
                declaration = regexp(classdefText, ['^\s*(\[[^\]\n]*\]\s*=\s*|\w+\s*=\s*)?' ...
                    name '\('], 'once', 'lineanchors');
                testCase.verifyNotEmpty(declaration, sprintf( ...
                    '%s is a method file of @Alakazam but is not declared in Alakazam.m.', name));
                k = find(strcmp({list.Name}, name), 1);
                if isempty(declaration) || isempty(k)
                    continue;
                end
                testCase.verifyEqual(numel(list(k).InputNames), numel(inputs), sprintf( ...
                    ['%s takes (%s) in its file but is declared with (%s) in Alakazam.m; ' ...
                     'a call with the file''s inputs is refused.'], name, strjoin(inputs, ', '), ...
                    strjoin(list(k).InputNames, ', ')));
                checked = checked + 1;
            end
            testCase.verifyGreaterThan(checked, 50, 'Too few method files were found to check.');
        end
    end

    methods (Static, Access = private)
        function files = methodFiles()
            folder = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'src', '@Alakazam');
            listing = dir(fullfile(folder, '*.m'));
            listing = listing(~strcmp({listing.name}, 'Alakazam.m'));
            files = fullfile({listing.folder}, {listing.name});
        end

        function mine = declared()
        %DECLARED  The methods Alakazam defines, with the inputs MATLAB holds
        %   for each, which are its declaration's.
            mc = meta.class.fromName('Alakazam');
            list = mc.MethodList;
            mine = list(arrayfun(@(m) strcmp(m.DefiningClass.Name, 'Alakazam'), list));
        end

        function [name, inputs] = fileSignature(file)
        %FILESIGNATURE  The name and inputs of a file's first function line,
        %   continuation lines joined.
            text = regexprep(fileread(file), '\.\.\.[^\n]*\n\s*', ' ');
            line = regexp(text, '^\s*function\s+[^\n]*', 'match', 'once', 'lineanchors');
            line = regexprep(line, '^\s*function\s+', '');
            equals = strfind(line, '=');
            open = strfind(line, '(');
            if ~isempty(equals) && (isempty(open) || equals(1) < open(1))
                line = line(equals(1) + 1:end);     % past the outputs
            end
            open = strfind(line, '(');
            inputs = {};
            if isempty(open)
                name = strtrim(regexprep(line, '[;%].*$', ''));
                return;
            end
            name = strtrim(line(1:open(1) - 1));
            close = strfind(line, ')');
            list = strtrim(line(open(1) + 1:close(find(close > open(1), 1)) - 1));
            if ~isempty(list)
                inputs = strtrim(strsplit(list, ','));
            end
        end
    end
end
