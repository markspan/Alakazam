classdef LibraryTest < matlab.unittest.TestCase
%LIBRARYTEST  Everything in library/ can be used as it is shipped.
%
%   The library holds the files a user starts an analysis from: templates,
%   bin scripts and measurement windows. A broken one fails in a dialog, far
%   from the file that caused it, so each is read here the way the
%   application reads it. A measurement file must also say where its windows
%   come from: a window taken from a library is an a priori choice only when
%   its source is known (library/README.md gives the rules).
%
%   Complements TemplateBinScriptsTest (the bin scripts inside the
%   templates) and MeasurePresetsTest (the rows of the measurement files).
%
%   Run with: runtests('tests/LibraryTest.m').
%
%   See also LIBRARYFOLDER, PICKLIBRARYFILE.

    properties (Constant)
        Kinds = {'templates', 'binscripts', 'measures'}
        Agreements = {'matches', 'partly', 'differs', 'not compared', 'no source'}
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Transformations', 'DefineBins'), ...
                     fullfile(root, 'src', 'Transformations')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function libraryFolderFindsTheRepositoryLibrary(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.verifyEqual(libraryFolder(), fullfile(root, 'library'));
            for k = LibraryTest.Kinds
                folder = libraryFolder(k{1});
                testCase.verifyTrue(isfolder(folder), sprintf('%s is missing.', folder));
                testCase.verifyNotEmpty(libraryFiles(k{1}), sprintf('%s is empty.', folder));
            end
        end

        function everyTemplateNamesTransformationsThatExist(testCase)
        %EVERYTEMPLATENAMESTRANSFORMATIONSTHATEXIST  A step whose
        %   transformation was renamed or removed fails only when the
        %   template is applied, on the user's data.
            root = fileparts(fileparts(mfilename('fullpath')));
            files = libraryFiles('templates', '*.alztemplate');
            testCase.assertNotEmpty(files, 'No templates found.');
            for f = 1:numel(files)
                [~, name, ext] = fileparts(files{f});
                where = [name ext];
                template = jsondecode(fileread(files{f}));
                testCase.verifyTrue(isfield(template, 'alakazamTemplate') && ...
                    isequal(template.alakazamTemplate, true), ...
                    sprintf('%s is not marked as an Alakazam template.', where));
                ids = stepIds(template);
                testCase.verifyNotEmpty(ids, sprintf('%s has no steps.', where));
                for id = ids
                    entry = fullfile(root, 'src', 'Transformations', id{1}, [id{1} '.m']);
                    testCase.verifyTrue(isfile(entry), sprintf( ...
                        '%s names "%s", which is not a transformation.', where, id{1}));
                end
            end
        end

        function everyBinScriptParses(testCase)
        %EVERYBINSCRIPTPARSES  As DefineBins' Load reads it: the epoch
        %   header lines its Save writes are taken off, the rest is parsed.
            files = libraryFiles('binscripts', '*.binscript');
            testCase.assertNotEmpty(files, 'No bin scripts found.');
            for f = 1:numel(files)
                [~, name, ext] = fileparts(files{f});
                where = [name ext];
                try
                    spec = DefineBinsEngine.parseSpec(scriptBody(fileread(files{f})));
                    testCase.verifyNotEmpty(spec.bins, sprintf('%s defines no bins.', where));
                catch err
                    testCase.verifyFail(sprintf('%s does not parse: %s', where, err.message));
                end
            end
        end

        function everyMeasureFileSaysWhereItsWindowsComeFrom(testCase)
            files = libraryFiles('measures', '*.alm');
            testCase.assertNotEmpty(files, 'No measurement files found.');
            for f = 1:numel(files)
                [~, name, ext] = fileparts(files{f});
                where = [name ext];
                raw = jsondecode(fileread(files{f}));
                hasSource = isfield(raw, 'source') && isstruct(raw.source);
                testCase.verifyTrue(hasSource, sprintf('%s has no source block.', where));
                if ~hasSource
                    continue;
                end
                source = raw.source;
                for field = {'reference', 'doi', 'agreement', 'note'}
                    testCase.verifyTrue(isfield(source, field{1}), ...
                        sprintf('%s: the source has no "%s".', where, field{1}));
                end
                if ~all(isfield(source, {'reference', 'agreement', 'note'}))
                    continue;
                end
                agreement = char(string(source.agreement));
                testCase.verifyTrue(any(strcmp(agreement, LibraryTest.Agreements)), sprintf( ...
                    '%s: "%s" is not one of: %s.', where, agreement, ...
                    strjoin(LibraryTest.Agreements, ', ')));
                testCase.verifyNotEmpty(strtrim(char(string(source.note))), ...
                    sprintf('%s: the source says nothing about how the file compares.', where));
                if ~strcmp(agreement, 'no source')
                    testCase.verifyNotEmpty(strtrim(char(string(source.reference))), sprintf( ...
                        '%s: "%s" needs the reference it was compared with.', where, agreement));
                end
            end
        end

        function theReadmeListsEveryFile(testCase)
        %THEREADMELISTSEVERYFILE  A file nobody can find in the index is a
        %   file nobody uses.
            readme = fileread(fullfile(libraryFolder(), 'README.md'));
            for k = LibraryTest.Kinds
                files = libraryFiles(k{1});
                for f = 1:numel(files)
                    [~, name, ext] = fileparts(files{f});
                    if strcmpi([name ext], 'README.md')
                        continue;
                    end
                    testCase.verifySubstring(readme, [name ext], sprintf( ...
                        'library/README.md does not list %s.', [name ext]));
                end
            end
        end
    end
end

% ======================================================================= %
function files = libraryFiles(kind, pattern)
%LIBRARYFILES  Full paths of the files of one kind, subfolders included.
    if nargin < 2
        pattern = '*.*';
    end
    listing = dir(fullfile(libraryFolder(kind), '**', pattern));
    listing = listing(~[listing.isdir]);
    files = arrayfun(@(d) fullfile(d.folder, d.name), listing, 'UniformOutput', false);
    files = reshape(files, 1, []);
end

function ids = stepIds(template)
%STEPIDS  The transformation of every step; older templates call them nodes.
    if isfield(template, 'steps')
        steps = template.steps;
    else
        steps = template.nodes;
    end
    if isstruct(steps)
        steps = num2cell(steps);
    end
    ids = reshape(cellfun(@(s) char(string(s.transformId)), steps, 'UniformOutput', false), 1, []);
end

function script = scriptBody(text)
%SCRIPTBODY  A saved bin script without the epoch header lines DefineBins'
%   Save writes above it, as its Load (readScriptFile) takes them off.
    lines = splitlines(text);
    isHeader = ~cellfun(@isempty, regexp(lines, '^%\s*epoch_st(art|op)_ms:', 'once'));
    script = strjoin(lines(~isHeader), newline);
end
