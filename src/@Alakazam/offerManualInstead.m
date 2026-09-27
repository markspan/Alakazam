function offerManualInstead(this)
%OFFERMANUALINSTEAD  What Help does when the help page is not there yet.
%   The in-app help page is the manual (manual/), prepared by buildHelpPage
%   and not kept in version control, so a fresh clone has none until it is
%   prepared. That is an ordinary state rather than a broken install, and
%   the Help button exists for an audience who will not go hunting for
%   documentation, so this offers to prepare it, and otherwise the manual
%   in another form, rather than just reporting the absence.
%
%   PREPARING IT IS OFFERED FIRST, AND IS THE DEFAULT. On a release it is a
%   copy of the rendered manual; on a working copy it renders the manual
%   with Quarto, which takes a couple of minutes. The alternatives, when
%   that cannot be done, are the PDF manual (manual/manual.pdf, which is
%   committed) and the README, opened in the system's own viewer.
%
%   See also ALAKAZAM.ONHELP, ALAKAZAM.BUILDHELPPAGE, BUILDHELPPAGEINTO.
    pdfFile = fullfile(this.RepoRoot, 'manual', 'manual.pdf');
    if exist(pdfFile, 'file') ~= 2
        pdfFile = '';
    end
    readmeFile = findReadme(this.RepoRoot);

    prompt = ['The in-app help (the Alakazam manual) has not been prepared in this ' ...
        'copy yet: it is made from the manual and not kept in version control.' ...
        newline newline ...
        'Alakazam can prepare it now. With a rendered manual in this copy that takes ' ...
        'a moment; otherwise the manual is rendered with Quarto (bundled with ' ...
        'RStudio), which takes a couple of minutes.'];
    renderHint = sprintf(['To render the manual by hand (needs Quarto):\n' ...
        '    cd "%s"\n    quarto render manual.qmd --to html\n\n' ...
        'then press Help again.'], fullfile(this.RepoRoot, 'manual'));

    options = {'Prepare it now'};
    if ~isempty(pdfFile);    options{end + 1} = 'Open the PDF manual'; end
    if ~isempty(readmeFile); options{end + 1} = 'Open README.MD'; end
    options{end + 1} = 'Close';
    selection = uiconfirm(this.MainFigure, prompt, 'Help not prepared yet', ...
        'Options', options, 'DefaultOption', 1, 'CancelOption', numel(options), ...
        'Icon', 'info');

    if strcmp(selection, 'Prepare it now')
        [restoreBusy, ~] = beginBusy(this.MainFigure, ...
            'Preparing the help page from the manual...'); %#ok<ASGLU>
        [built, message] = this.buildHelpPage();
        clear restoreBusy;   % dismiss the overlay BEFORE any dialog below
        if built
            this.onHelp();   % the page is there now, so open it
            return;
        end
        uialert(this.MainFigure, sprintf('%s\n\n%s', message, renderHint), ...
            'Could not prepare the help page', 'Icon', 'warning');
        fallbacks = options(ismember(options, {'Open the PDF manual', 'Open README.MD'}));
        if isempty(fallbacks)
            return;
        end
        selection = uiconfirm(this.MainFigure, 'Open the manual another way?', ...
            'Help not prepared yet', 'Options', [fallbacks, {'Close'}], ...
            'DefaultOption', 1, 'CancelOption', numel(fallbacks) + 1, 'Icon', 'info');
    end

    switch selection
        case 'Open the PDF manual'
            openFile(pdfFile);
        case 'Open README.MD'
            openFile(readmeFile);
    end
end

function openFile(file)
%OPENFILE  In the system's own viewer, or MATLAB's browser when none is set.
    try
        web(['file:///' strrep(file, '\', '/')], '-browser');
    catch
        web(file);
    end
end

function file = findReadme(repoRoot)
%FINDREADME  The README's actual path, whatever its case, or '' if absent.
%   git records the file as README.MD, but on Windows a working copy can
%   hold readme.MD while the index holds README.MD (core.ignorecase), and
%   only one of them opens on a case-sensitive filesystem. Listing the
%   directory costs nothing and cannot be wrong.
    file = '';
    entries = dir(fullfile(repoRoot, '*.MD'));
    entries = [entries; dir(fullfile(repoRoot, '*.md'))];
    for k = 1:numel(entries)
        if strcmpi(entries(k).name, 'readme.md')
            file = fullfile(repoRoot, entries(k).name);
            return;
        end
    end
end
