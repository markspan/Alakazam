classdef AvailableElectrodeTemplatesTest < matlab.unittest.TestCase
%AVAILABLEELECTRODETEMPLATESTEST  What Channel Editor's "Look up locations"
%   can offer, now that a 10-5 lookup is no longer the only useful one.
%
%   Run against the repository's OWN src/Electrodes folder rather than a
%   synthetic double: the point of vendoring those files was that they are
%   a durable, tracked fixture, so the honest test is that THEY, as shipped,
%   enumerate and read correctly -- the same reasoning Template1005Test
%   applies to the real installed toolbox templates.
%
%   Run with: runtests('tests/AvailableElectrodeTemplatesTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations', 'ChannelEditor')));   % AvailableElectrodeTemplates lives there
        end
    end

    methods (Test)
        function standardTenFiveIsFirst(testCase)
        %STANDARDTENFIVEISFIRST  The common case keeps its old one-click
        %   behaviour: whatever else src/Electrodes grows, 10-5 stays the
        %   default selection rather than falling out of alphabetical order
        %   ("Standard 10-5" would sort after e.g. "Waveguard64...").
            templates = AvailableElectrodeTemplates();

            testCase.assertNotEmpty(templates);
            testCase.verifyEqual(templates(1).name, 'Standard 10-5');
        end

        function theVendoredWaveguardMontageIsOffered(testCase)
        %THEVENDOREDWAVEGUARDMONTAGEISOFFERED  The reason this function
        %   exists at all: an equidistant montage needs a template a 10-5
        %   lookup cannot substitute for, so it must actually appear in the
        %   list, not merely fail to crash it.
            templates = AvailableElectrodeTemplates();
            names = {templates.name};

            testCase.verifyTrue(any(contains(lower(names), 'waveguard')), ...
                sprintf('Expected a waveguard entry among: %s', strjoin(names, ', ')));
        end

        function theVendored1005CopyIsNotListedTwice(testCase)
        %THEVENDORED1005COPYISNOTLISTEDTWICE  src/Electrodes/standard_1005.elc
        %   exists ONLY as a durable backup behind Template1005File's own
        %   resolution; it must not also appear as its own confusingly-named
        %   second "1005" entry when the toolbox copy already covers it.
            templates = AvailableElectrodeTemplates();
            names = {templates.name};

            testCase.verifyEqual(sum(strcmp(names, 'Standard 10-5')), 1, ...
                sprintf('"Standard 10-5" should appear exactly once, found in: %s', ...
                strjoin(names, ', ')));
        end

        function everyNameIsUnique(testCase)
            templates = AvailableElectrodeTemplates();
            names = {templates.name};

            testCase.verifyEqual(numel(unique(names)), numel(names), ...
                'Two entries with the same name are indistinguishable in the dropdown.');
        end

        function everyListedFileActuallyExistsAndReads(testCase)
        %EVERYLISTEDFILEACTUALLYEXISTSANDREADS  The one property that
        %   matters for "Look up locations" to work at all: readlocs must
        %   not throw on any entry this function hands to the dropdown.
            testCase.assumeTrue(~isempty(which('readlocs')), ...
                'readlocs (EEGLAB) is not on the path.');
            templates = AvailableElectrodeTemplates();

            for k = 1:numel(templates)
                t = templates(k);
                testCase.verifyTrue(isfile(t.file), ...
                    sprintf('"%s" points at a file that does not exist: %s', t.name, t.file));
                locs = readlocs(t.file);
                testCase.verifyNotEmpty(locs, ...
                    sprintf('"%s" (%s) read as zero channels.', t.name, t.file));
            end
        end

        function theWaveguardEntryHasWhatItsNameImplies(testCase)
        %THEWAVEGUARDENTRYHASWHATITSNAMEIMPLIES  Not just "some file that
        %   parses" -- the actual 65-channel equidistant montage, so that
        %   looking it up in Channel Editor genuinely fills a label like
        %   "1L" that Standard 10-5 has never heard of.
            testCase.assumeTrue(~isempty(which('readlocs')), ...
                'readlocs (EEGLAB) is not on the path.');
            templates = AvailableElectrodeTemplates();
            k = find(contains(lower({templates.name}), 'waveguard'), 1);
            testCase.assertNotEmpty(k, 'No waveguard entry to check.');

            locs = readlocs(templates(k).file);
            testCase.verifyEqual(numel(locs), 65);
            testCase.verifyTrue(any(strcmp({locs.labels}, '1L')), ...
                'Expected the equidistant montage''s own "1L" label.');
        end
    end
end
