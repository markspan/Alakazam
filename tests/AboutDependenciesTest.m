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

        function everyToolkitInDependenciesMdIsCredited(testCase)
        %EVERYTOOLKITINDEPENDENCIESMDISCREDITED  The drift check in the
        %   other direction. Only the one above existed, which is how Unfold
        %   and EYE-EEG came to be documented in dependencies.md and missing
        %   from the About box: a toolkit added to the document and forgotten
        %   in the credits passed every test.
            root = fileparts(fileparts(mfilename('fullpath')));
            doc = splitlines(fileread(fullfile(root, 'dependencies.md')));
            first = find(startsWith(doc, '## Core analysis toolkits'), 1);
            testCase.assertNotEmpty(first, 'dependencies.md has no core-toolkit table.');
            last = first + find(startsWith(doc(first + 1:end), '## '), 1);

            credited = {alakazamDependencies().name};
            for k = first + 1:last - 1
                cells = strsplit(doc{k}, '|');
                if numel(cells) < 3 || contains(doc{k}, '---') || strcmp(strtrim(cells{2}), 'Toolkit')
                    continue;
                end
                for name = strtrim(strsplit(cells{2}, ','))
                    testCase.verifyTrue(ismember(name{1}, credited), sprintf( ...
                        ['"%s" is in dependencies.md but not credited in the About box; ' ...
                         'the two lists have drifted.'], name{1}));
                end
            end
        end

        % ---- the papers ---------------------------------------------------
        function everyPaperIsCompleteAndCitedInTheReadme(testCase)
        %EVERYPAPERISCOMPLETEANDCITEDINTHEREADME  The About box and the
        %   README must name the same papers; a DOI is the unambiguous key.
            root = fileparts(fileparts(mfilename('fullpath')));
            readme = fileread(fullfile(root, 'README.MD'));

            refs = alakazamReferences();
            testCase.assertNotEmpty(refs);
            for i = 1:numel(refs)
                r = refs(i);
                for field = {'authors', 'title', 'source', 'doi', 'usedFor'}
                    testCase.verifyNotEmpty(strtrim(r.(field{1})), ...
                        sprintf('Reference %d has an empty %s.', i, field{1}));
                end
                testCase.verifyFalse(startsWith(r.doi, 'http'), 'A DOI is stored bare.');
                testCase.verifySubstring(readme, r.doi, sprintf( ...
                    '%s (%d) is in the About box but not in README.MD''s References.', ...
                    r.authors, r.year));
            end
        end

        function theNewMethodsHaveTheirPapers(testCase)
        %THENEWMETHODSHAVETHEIRPAPERS  RESS, Deconvolve and EyeTracking each
        %   rest on a paper a user has to be able to find.
            dois = {alakazamReferences().doi};
            for doi = {'10.1016/j.neuroimage.2016.11.036', '10.7717/peerj.7838', ...
                    '10.1167/jov.21.1.3', '10.1037/a0023885'}
                testCase.verifyTrue(ismember(doi{1}, dois), sprintf('%s is not cited.', doi{1}));
            end
        end

        function theAboutPageListsEveryPaper(testCase)
            html = aboutPageHtml(alakazamVersion(), '');

            testCase.verifySubstring(html, 'Papers to cite');
            for r = alakazamReferences()
                testCase.verifySubstring(html, ['https://doi.org/' r.doi]);
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
