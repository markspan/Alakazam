classdef ColourMapPreviewTest < matlab.unittest.TestCase
%COLOURMAPPREVIEWTEST  The Settings dialog's preview of the "Colour map"
%   choice: a strip of each map, drawn by the same function the plots take
%   their map from, redrawn as the choice changes, before anything is saved.
%
%   Run with: runtests('tests/ColourMapPreviewTest.m').
%
%   See also ALAKAZAMSETTINGS, SETTINGSDIALOG, TRANSTOOLS.DIVERGINGCOLORMAP.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Dialogs'), fullfile(root, 'src', 'Transformations')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function aNamedMapIsThatMap(testCase)
            testCase.verifyEqual(TransTools.DivergingColormap('jet'), jet(64));
            testCase.verifyEqual(TransTools.DivergingColormap('hot'), hot(64));
            diverging = TransTools.DivergingColormap('diverging');
            testCase.verifyEqual(diverging(1, :), [0.13 0.35 0.75], 'Blue at the low end.');
            testCase.verifyEqual(diverging(end, :), [0.75 0.15 0.15], 'Red at the high end.');
        end

        function everyChoiceHasAStripOfItsOwnMap(testCase)
            item = ColourMapPreviewTest.colourMapSetting();
            testCase.assertNotEmpty(item.preview, 'The colour map setting carries a preview.');

            for choice = item.choices
                strip = item.preview(choice{1});
                cmap = TransTools.DivergingColormap(choice{1});
                testCase.verifyEqual(size(strip, 3), 3, choice{1});
                testCase.verifyEqual(squeeze(strip(1, :, :)), cmap, ...
                    sprintf('The %s strip runs through its map, low values on the left.', choice{1}));
            end
        end
    end

    methods (Test, TestTags = {'Slow'})
        function theStripFollowsTheChoiceBeforeItIsSaved(testCase)
            try
                probe = uifigure('Visible', 'off');
                delete(probe);
            catch ME
                testCase.assumeFail(['A uifigure could not be created here: ' ME.message]);
            end
            before = AlakazamSettings.get("graphics", "colormap", "name");
            SettingsDialog();
            fig = findall(groot, 'Type', 'figure', 'Name', 'Settings');
            closeFig = onCleanup(@() delete(fig));

            picture = findall(fig, 'Tag', 'preview:name');
            testCase.assertNumElements(picture, 1, 'The dialog shows one colour-map preview.');
            item = ColourMapPreviewTest.colourMapSetting();
            dropdowns = findall(fig, 'Type', 'uidropdown');
            dropdown = dropdowns(arrayfun(@(d) isequal(d.Items, item.choices), dropdowns));
            testCase.assertNumElements(dropdown, 1);
            testCase.verifyEqual(picture.ImageSource, item.preview(dropdown.Value));

            other = item.choices{find(~strcmp(item.choices, dropdown.Value), 1)};
            dropdown.Value = other;
            dropdown.ValueChangedFcn(dropdown, []);

            testCase.verifyEqual(picture.ImageSource, item.preview(other));
            testCase.verifyEqual(AlakazamSettings.get("graphics", "colormap", "name"), before, ...
                'Looking is not saving: the stored choice is unchanged.');
            clear closeFig
        end
    end

    methods (Static)
        function item = colourMapSetting()
            tabs = AlakazamSettings.schema();
            graphics = tabs(strcmp({tabs.name}, 'graphics'));
            section = graphics.sections(strcmp({graphics.sections.name}, 'colormap'));
            item = section.settings(strcmp({section.settings.key}, 'name'));
        end
    end
end
