classdef AboutDependenciesTest < matlab.unittest.TestCase
%ABOUTDEPENDENCIESTEST  Unit tests for src/Support/alakazamDependencies.m
%   and the About page that renders it.
%
%   Two things are worth pinning here. First, every entry is complete: a
%   dependency listed without its licence or its source is worse than one
%   not listed at all, because it looks like credit while withholding the
%   part someone actually needs.
%
%   Second, the list agrees with dependencies.md. Those are the same facts
%   written for two readers -- the maintainer's account of where each
%   toolkit comes from, and the user-facing credit -- and nothing but a
%   test stops a toolkit being added to one and forgotten in the other.
%
%   Run with: runtests('tests/AboutDependenciesTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Support')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src')));
        end
    end

    methods (Test)
        function everyEntryIsComplete(testCase)
            deps = alakazamDependencies();
            testCase.assertNotEmpty(deps);

            for i = 1:numel(deps)
                d = deps(i);
                for field = {'name', 'version', 'licence', 'url', 'note', 'category'}
                    testCase.verifyNotEmpty(strtrim(d.(field{1})), ...
                        sprintf('"%s" has an empty %s.', d.name, field{1}));
                end
                testCase.verifyTrue(startsWith(d.url, 'https://'), ...
                    sprintf('"%s" should link somewhere reachable.', d.name));
            end
        end

        function namesAreUnique(testCase)
            names = {alakazamDependencies().name};
            testCase.verifyEqual(numel(unique(names)), numel(names));
        end

        function theRestrictiveLicenceIsStatedInFull(testCase)
        %THERESTRICTIVELICENCEISSTATEDINFULL  GEDAI is PolyForm
        %   Noncommercial, which restricts what a reader may do with their
        %   own work. An About box is exactly where somebody looks for that,
        %   so it must say so rather than abbreviate it away.
            deps = alakazamDependencies();
            gedai = deps(strcmp({deps.name}, 'GEDAI'));

            testCase.assertNotEmpty(gedai, 'GEDAI should be listed.');
            testCase.verifySubstring(gedai.licence, 'PolyForm Noncommercial');
            testCase.verifySubstring(lower(gedai.note), 'commercial');
        end

        function everyToolkitAlsoAppearsInDependenciesMd(testCase)
        %EVERYTOOLKITALSOAPPEARSINDEPENDENCIESMD  The drift check. R and
        %   Quarto are exempt: dependencies.md covers the MATLAB toolkits an
        %   installation needs, whereas these two are needed only to render
        %   a report and are documented with the reporting feature instead.
            root = fileparts(fileparts(mfilename('fullpath')));
            doc = fileread(fullfile(root, 'dependencies.md'));

            deps = alakazamDependencies();
            exempt = {'R', 'Quarto'};
            for i = 1:numel(deps)
                if any(strcmp(deps(i).name, exempt))
                    continue;
                end
                testCase.verifyTrue(contains(doc, deps(i).name), ...
                    sprintf(['"%s" is credited in the About box but missing from ' ...
                        'dependencies.md; the two lists have drifted.'], deps(i).name));
            end
        end

        % ---- the rendered page ------------------------------------------
        function theAboutPageListsEveryDependency(testCase)
            html = aboutPageHtml(alakazamVersion(), '');

            deps = alakazamDependencies();
            for i = 1:numel(deps)
                testCase.verifySubstring(html, deps(i).name);
                testCase.verifySubstring(html, deps(i).licence);
                testCase.verifySubstring(html, deps(i).url);
            end
        end

        function theAboutPageStillCarriesItsOwnDetails(testCase)
        %THEABOUTPAGESTILLCARRIESITSOWNDETAILS  The dependency section is an
        %   addition, not a replacement: version, author and licence are
        %   what someone opened this for.
            info = alakazamVersion();
            html = aboutPageHtml(info, '');

            testCase.verifySubstring(html, info.Name);
            testCase.verifySubstring(html, info.Version);
            testCase.verifySubstring(html, info.Author);
            testCase.verifySubstring(html, info.License);
        end

        function categoriesGroupTheList(testCase)
            html = aboutPageHtml(alakazamVersion(), '');

            for heading = {'Analysis toolkits', 'Bundled components', ...
                    'Data assets', 'Reporting'}
                testCase.verifySubstring(html, heading{1});
            end
        end

        function thePageSurvivesAMissingLogo(testCase)
        %THEPAGESURVIVESAMISSINGLOGO  An About box that refuses to open
        %   because its decoration is absent would be a worse failure than
        %   one without a picture -- aboutPageHtml's own stated contract.
            html = aboutPageHtml(alakazamVersion(), 'no-such-file.svg');

            testCase.verifyNotEmpty(html);
            testCase.verifySubstring(html, 'EEGLAB');
        end
    end
end
