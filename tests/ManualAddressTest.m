classdef ManualAddressTest < matlab.unittest.TestCase
%MANUALADDRESSTEST  Where the ? of a step's options dialog leads: every
%   built-in transformation to its own section of Alakazam's manual on the
%   web, a GitHub repository to its Pages, and nothing to nothing.
%
%   A plugin's own manifest field and its install link are PluginsTest's,
%   which installs plugins of its own; the ? itself is DialogFieldsTest's.
%
%   Run with: runtests('tests/ManualAddressTest.m').
%
%   See also MANUALADDRESS, PLUGINS.PAGESADDRESS.

    properties (Constant)
        Root = fileparts(fileparts(mfilename('fullpath')))
        Manual = 'https://markspan.github.io/Alakazam/'
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            for p = {fullfile(ManualAddressTest.Root, 'src'), ...
                     fullfile(ManualAddressTest.Root, 'src', 'Support'), ...
                     fullfile(ManualAddressTest.Root, 'src', 'Transformations')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function everyBuiltInLeadsToItsOwnSection(testCase)
        %EVERYBUILTINLEADSTOITSOWNSECTION  #sec-tr-<id in lower case>, and
        %   that section exists in the manual's chapters, so a renamed
        %   section cannot leave a ? leading nowhere.
            manifests = dir(fullfile(ManualAddressTest.Root, 'src', 'Transformations', '*', '*.json'));
            testCase.assertGreaterThan(numel(manifests), 20);
            chapters = dir(fullfile(ManualAddressTest.Root, 'manual', 'chapters', '*.qmd'));
            text = strjoin(arrayfun(@(c) fileread(fullfile(c.folder, c.name)), chapters, ...
                'UniformOutput', false), newline);
            for m = reshape(manifests, 1, [])
                [~, id] = fileparts(m.name);
                anchor = ['sec-tr-' lower(id)];
                testCase.verifyEqual(manualAddress(id), [ManualAddressTest.Manual '#' anchor], id);
                testCase.verifyTrue(contains(text, ['{#' anchor '}']), ...
                    sprintf('The manual has no section %s for %s.', anchor, id));
            end
        end

        function aGitHubRepositoryLeadsToItsPages(testCase)
            cases = { ...
                'https://github.com/markspan/AlakazamHREvoked', 'https://markspan.github.io/AlakazamHREvoked/'; ...
                'https://github.com/MarkSpan/AlakazamASR.git', 'https://markspan.github.io/AlakazamASR/'; ...
                'https://www.github.com/me/AlakazamX/releases/tag/V0.1.0', 'https://me.github.io/AlakazamX/'; ...
                'http://github.com/me/AlakazamY?tab=readme', 'https://me.github.io/AlakazamY/'; ...
                'https://example.org/AlakazamZ.zip', ''; ...
                'C:\plugins\AlakazamZ.zip', ''; ...
                '', ''};
            for k = 1:size(cases, 1)
                testCase.verifyEqual(Plugins.pagesAddress(cases{k, 1}), cases{k, 2}, cases{k, 1});
            end
        end

        function whatIsNoTransformationHasNoManual(testCase)
            testCase.verifyEmpty(manualAddress('NoSuchTransformation'));
            testCase.verifyEmpty(manualAddress(''));
            testCase.verifyEmpty(manualAddress('3 Grand average'), 'Not a transformation''s name.');
        end

        function aQuestionMarkJoinsATitleBarInItsPlace(testCase)
        %AQUESTIONMARKJOINSATITLEBARINITSPLACE  manualButton puts a ? beside
        %   a dialog's title, in the title's own place in its grid, and the ?
        %   opens the step's manual; where there is none, the title stays as
        %   it was. A stand-in openInBrowser records the address.
            try
                fig = uifigure('Visible', 'off');
            catch err
                testCase.assumeFail(['A uifigure could not be created here: ' err.message]);
            end
            testCase.addTeardown(@() delete(fig));
            testCase.standInBrowser();
            root = uigridlayout(fig, [3 1], 'RowHeight', {40, 40, '1x'});
            title = uilabel(root, 'Text', '  Filter', 'BackgroundColor', [0.29 0.5 0.79]);
            title.Layout.Row = 2;
            plain = uilabel(root, 'Text', '  Nothing');
            plain.Layout.Row = 1;

            button = manualButton(title, 'Filter');
            testCase.assertNotEmpty(button);
            bar = title.Parent;
            testCase.verifyTrue(isa(bar, 'matlab.ui.container.GridLayout') && bar.Parent == root);
            testCase.verifyEqual(bar.Layout.Row, 2, 'In the title''s own place.');
            testCase.verifyEqual(bar.BackgroundColor, [0.29 0.5 0.79], 'In the title bar''s colour.');
            button.ButtonPushedFcn(button, []);
            testCase.verifyEqual(getappdata(groot, 'OpenedInBrowser'), ...
                {[ManualAddressTest.Manual '#sec-tr-filter']});

            testCase.verifyEmpty(manualButton(plain, 'NoSuchTransformation'));
            testCase.verifyTrue(plain.Parent == root, 'No manual, no change.');
        end

        function everyBuiltInDialogOfItsOwnOffersItsManual(testCase)
        %EVERYBUILTINDIALOGOFITSOWNOFFERSITSMANUAL  A built-in step that draws
        %   its own dialog rather than TransformOptionsDialog puts the ? in
        %   its title bar itself, for its own manual.
            for tool = {'ChannelEditor', 'DefineBins', 'EventEditor', 'Filter', 'ManualReject', ...
                    'Measure', 'Photodiode', 'ReRef', 'RemoveComponents', 'SelectData', 'SpectralMeasure'}
                source = fileread(fullfile(ManualAddressTest.Root, 'src', 'Transformations', ...
                    tool{1}, [tool{1} 'Dialog.m']));
                testCase.verifySubstring(source, sprintf('manualButton(titleBar, ''%s'');', tool{1}), tool{1});
            end
        end
    end

    methods (Access = private)
        function standInBrowser(testCase)
        %STANDINBROWSER  An openInBrowser first on the path that records the
        %   addresses it is given (appdata OpenedInBrowser), so no test opens
        %   a browser.
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            fid = fopen(fullfile(folder, 'openInBrowser.m'), 'w');
            fprintf(fid, '%s\n', 'function openInBrowser(url)', ...
                'setappdata(groot, ''OpenedInBrowser'', [getappdata(groot, ''OpenedInBrowser''), {char(url)}]);', ...
                'end');
            fclose(fid);
            testCase.addTeardown(@rehash);   % after the path is restored: no stand-in stays cached
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(folder));
            rehash;
            setappdata(groot, 'OpenedInBrowser', {});
            testCase.addTeardown(@() rmappdata(groot, 'OpenedInBrowser'));
        end
    end
end
