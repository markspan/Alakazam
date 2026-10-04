function [source, fig] = PluginSourceDialog(parentFig, varargin)
%PLUGINSOURCEDIALOG  Ask where a plugin comes from: a zip file on this
%   computer, or a link. Returns the file or the link, or '' when cancelled.
%
%   SOURCE = PluginSourceDialog(PARENTFIG) shows the dialog and waits.
%   [~, FIG] = PluginSourceDialog(PARENTFIG, 'Wait', false) returns at once,
%   for the tests: they fill the link and press the buttons themselves, and
%   read the answer with getappdata(FIG, 'Source').
%
%   Only asks; it fetches and checks nothing. Plugins.prepare does that, and
%   the confirmation that follows says what was found.
%
%   See also PLUGINS, ALAKAZAM.ONINSTALLPLUGIN, PLUGINSDIALOG.
    p = inputParser();
    p.addParameter('Wait', true, @(x) islogical(x) || isnumeric(x));
    p.parse(varargin{:});

    accentColor = [0.290 0.498 0.788];   % AlakazamRibbon.html's .alz-tab-home (#4a7fc9)
    bgColor     = [0.9608 0.9608 0.9608];
    position = [420 300 560 250];
    if nargin >= 1 && ~isempty(parentFig) && isvalid(parentFig)
        parentPos = parentFig.Position;
        position(1) = parentPos(1) + (parentPos(3) - position(3)) / 2;
        position(2) = parentPos(2) + (parentPos(4) - position(4)) / 2;
    end

    fig = uifigure('Name', 'Install a plugin', 'Position', fitOnScreen(position), ...
        'Color', bgColor, 'Tag', 'PluginSourceDialog', 'Visible', p.Results.Wait);
    setappdata(fig, 'Source', '');
    fig.CloseRequestFcn = @(~, ~) finish('');

    outer = uigridlayout(fig, [3, 1], 'RowHeight', {40, '1x', 46}, ...
        'Padding', [0 0 0 0], 'RowSpacing', 0);
    header = uilabel(outer, 'Text', '  Install a plugin', 'FontSize', 14, ...
        'FontWeight', 'bold', 'FontColor', [1 1 1], 'BackgroundColor', accentColor, ...
        'VerticalAlignment', 'center');
    header.Layout.Row = 1;

    body = uigridlayout(outer, [3, 3], 'RowHeight', {'fit', 30, 30}, ...
        'ColumnWidth', {50, '1x', 130}, 'Padding', [16 12 16 4], 'RowSpacing', 10);
    body.Layout.Row = 2;
    intro = uilabel(body, 'WordWrap', 'on', 'Text', ['A plugin is a transformation ' ...
        'packed as a zip file. Choose the zip file, or give a link to one: a zip file ' ...
        'on the web, or a GitHub repository, release or folder. What it holds is shown ' ...
        'before anything is installed.']);
    intro.Layout.Row = 1;
    intro.Layout.Column = [1 3];

    fileButton = uibutton(body, 'Text', 'Choose a zip file...', 'Tag', 'ChooseFile', ...
        'ButtonPushedFcn', @(~, ~) chooseFile());
    fileButton.Layout.Row = 2;
    fileButton.Layout.Column = [1 2];

    linkLabel = uilabel(body, 'Text', 'Link:');
    linkLabel.Layout.Row = 3;
    linkLabel.Layout.Column = 1;
    linkField = uieditfield(body, 'text', 'Tag', 'Link', ...
        'Placeholder', 'https://github.com/owner/repository');
    linkField.Layout.Row = 3;
    linkField.Layout.Column = 2;
    linkButton = uibutton(body, 'Text', 'Install from link', 'Tag', 'UseLink', ...
        'ButtonPushedFcn', @(~, ~) useLink());
    linkButton.Layout.Row = 3;
    linkButton.Layout.Column = 3;

    buttonRow = uigridlayout(outer, [1, 2], 'ColumnWidth', {'1x', 90}, ...
        'Padding', [16 6 16 10]);
    buttonRow.Layout.Row = 3;
    cancel = uibutton(buttonRow, 'Text', 'Cancel', 'Tag', 'Cancel', ...
        'ButtonPushedFcn', @(~, ~) finish(''));
    cancel.Layout.Column = 2;

    source = '';
    if p.Results.Wait
        fig.WindowStyle = 'modal';
        uiwait(fig);
        if isvalid(fig)
            source = getappdata(fig, 'Source');
            delete(fig);
        end
    end

    function chooseFile()
        [file, folder] = uigetfile({'*.zip', 'Zip files (*.zip)'}, 'Choose a plugin');
        figure(fig);
        if ~isequal(file, 0)
            finish(fullfile(folder, file));
        end
    end

    function useLink()
        link = strtrim(linkField.Value);
        if isempty(link)
            uialert(fig, 'Give a link first, or choose a zip file.', 'No link', 'Icon', 'info');
            return;
        end
        finish(link);
    end

    function finish(answer)
        setappdata(fig, 'Source', answer);
        if p.Results.Wait
            uiresume(fig);
        end
    end
end
