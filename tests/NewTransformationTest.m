classdef NewTransformationTest < matlab.unittest.TestCase
%NEWTRANSFORMATIONTEST  The transformation generator (newTransformation):
%   what it writes, where, and whether what it writes works.
%
%   Each case generates into a temporary repository holding the two files
%   the generator edits (WorkSpaceTree.m and a manual chapter), so the real
%   checkout is never touched. The strongest check is the last group: the
%   generated transformation is put on the path and called, replayed and
%   refused, so a scaffold that does not run under the contract fails here
%   rather than in the hands of its first author.
%
%   Run with: runtests('tests/NewTransformationTest.m').
%
%   See also NEWTRANSFORMATION.

    properties (Access = private)
        Repo
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Support'), fullfile(root, 'src', 'IO'), ...
                     fullfile(root, 'src', 'Transformations'), fullfile(root, 'src'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (TestMethodSetup)
        function makeRepository(testCase)
        %MAKEREPOSITORY  A throwaway repository with the files the generator
        %   edits, copied from this checkout.
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.Repo = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            for d = {fullfile('src', 'Transformations'), fullfile('src', 'Icons'), ...
                     fullfile('src', 'Support'), fullfile('tests', 'fixtures'), ...
                     fullfile('manual', 'chapters')}
                mkdir(fullfile(testCase.Repo, d{1}));
            end
            % The generated test puts these on its path; the rest of what it
            % needs (TransTools, inferDataFormat) comes from this checkout.
            copyfile(fullfile(root, 'tests', 'fixtures', 'makeTestEEG.m'), ...
                fullfile(testCase.Repo, 'tests', 'fixtures'));
            copyfile(fullfile(root, 'src', 'WorkSpaceTree.m'), fullfile(testCase.Repo, 'src'));
            copyfile(fullfile(root, 'manual', 'chapters', '_07-ref-preprocessing.qmd'), ...
                fullfile(testCase.Repo, 'manual', 'chapters'));
        end
    end

    methods (Test)
        function itWritesTheThreeFilesATestAndAnIconSource(testCase)
            created = testCase.generate('MovingMean');

            folder = fullfile(testCase.Repo, 'src', 'Transformations', 'MovingMean');
            for f = {fullfile(folder, 'MovingMean.m'), fullfile(folder, 'MovingMean.json'), ...
                     fullfile(folder, 'MovingMean.png'), fullfile(testCase.Repo, 'src', 'Icons', 'MovingMean.svg'), ...
                     fullfile(testCase.Repo, 'tests', 'MovingMeanTest.m')}
                testCase.verifyTrue(isfile(f{1}), sprintf('%s was not written.', f{1}));
                testCase.verifyTrue(ismember(f{1}, created));
            end
        end

        function theManifestPutsItOnTheRibbon(testCase)
            testCase.generate('MovingMean');

            manifest = jsondecode(fileread(fullfile(testCase.Repo, 'src', 'Transformations', ...
                'MovingMean', 'MovingMean.json')));
            testCase.verifyEqual(manifest.Name, 'MovingMean');
            testCase.verifyEqual(manifest.Entry, 'MovingMean.m');
            testCase.verifyEqual(manifest.Icon, 'MovingMean.png');
            testCase.verifyEqual(manifest.Section, '1. Preprocessing');
            testCase.verifyEqual(manifest.Description, 'Smooth each channel.');
        end

        function itJoinsTheRecalculateListInOrder(testCase)
            testCase.generate('MovingMean');

            text = fileread(fullfile(testCase.Repo, 'src', 'WorkSpaceTree.m'));
            block = regexp(text, 'RecalculableTransforms\s*=\s*\{[^}]*\}', 'match', 'once');
            names = regexp(block, '''(\w+)''', 'tokens');
            names = [names{:}];
            at = find(strcmp(names, 'MovingMean'));
            testCase.assertNumElements(at, 1);
            % Between its alphabetical neighbours (the list is kept roughly
            % in order, ignoring case; the generator keeps it no worse).
            testCase.verifyEqual(sortCaseless(names(at - 1:at + 1)), names(at - 1:at + 1));
        end

        function aStepWithoutSettingsIsNotRecalculable(testCase)
            testCase.generate('NoSettings', struct('label', {}, 'name', {}, 'default', {}));

            text = fileread(fullfile(testCase.Repo, 'src', 'WorkSpaceTree.m'));
            testCase.verifyFalse(contains(text, '''NoSettings'''), ...
                'Nothing to reseed, so nothing to recalculate.');
        end

        function itAddsAManualSectionWithItsOptions(testCase)
            testCase.generate('MovingMean');

            chapter = fileread(fullfile(testCase.Repo, 'manual', 'chapters', '_07-ref-preprocessing.qmd'), ...
                'Encoding', 'UTF-8');
            testCase.verifySubstring(chapter, '## MovingMean {#sec-tr-movingmean}');
            testCase.verifySubstring(chapter, '| **Window (ms)** | 20 | The width of the moving average. |');
            testCase.verifyFalse(contains(chapter, char(8212)), 'No em dash, as ManualTest requires.');
        end

        function anExistingNameIsRefused(testCase)
            testCase.generate('MovingMean');

            testCase.verifyError(@() testCase.generate('MovingMean'), 'Alakazam:newTransformation');
        end

        function aNameThatIsNotAnIdentifierIsRefused(testCase)
            testCase.verifyError(@() testCase.generate('2Smooth'), 'MATLAB:InputParser:ArgumentFailedValidation');
        end

        % ---- the generated transformation runs --------------------------------
        function theGeneratedStepRunsAndReplays(testCase)
            testCase.generate('MovingMean');
            testCase.onPath('MovingMean');
            EEG = makeTestEEG();
            opts = struct('WindowMs', 20, 'Mode', 'fast', 'Channels', {{}});

            [first, stored] = MovingMean(EEG, opts);
            second = MovingMean(EEG, stored);

            testCase.verifyEqual(second.data, first.data);
            testCase.verifyEqual(first.etc.alz.movingMean.options, opts, 'It records what it ran with.');
        end

        function theGeneratedStepRefusesTheWrongData(testCase)
            testCase.generate('MovingMean');
            testCase.onPath('MovingMean');

            continuous = makeTestEEG('DataFormat', 'CONTINUOUS');
            testCase.verifyError(@() MovingMean(continuous, struct('WindowMs', 20)), 'Alakazam:MovingMean');
        end

        function theGeneratedTestPasses(testCase)
            testCase.generate('MovingMean');
            testCase.onPath('MovingMean');
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'tests', 'fixtures')));

            results = run(matlab.unittest.TestSuite.fromFile( ...
                fullfile(testCase.Repo, 'tests', 'MovingMeanTest.m')));

            testCase.verifyTrue(all([results.Passed]), 'The scaffold''s own tests pass as generated.');
        end
    end

    methods (Access = private)
        function created = generate(testCase, name, fields)
        %GENERATE  NAME into the scratch repository, with three fields (a
        %   number, a choice and a channel picker) unless FIELDS are given.
            if nargin < 3
                fields = struct('label', {'Window (ms)', 'Mode', 'Channels'}, ...
                    'name', {'WindowMs', 'Mode', 'Channels'}, ...
                    'default', {20, {'fast', 'slow'}, {}}, 'kind', {'', '', 'channels'}, ...
                    'help', {'The width of the moving average.', 'How.', 'The channels.'});
            end
            created = newTransformation(name, 'Section', '1. Preprocessing', ...
                'Description', 'Smooth each channel.', 'Input', 'epoched', 'Fields', fields, ...
                'Repository', testCase.Repo);
        end

        function onPath(testCase, name)
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(testCase.Repo, 'src', 'Transformations', name)));
        end
    end
end

% ======================================================================= %
function sorted = sortCaseless(names)
    [~, order] = sort(lower(names));
    sorted = names(order);
end
