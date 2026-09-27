function [ok, message] = buildHelpPageInto(manualDir, target, findQuarto)
%BUILDHELPPAGEINTO  Put the manual, as the in-app help page, at TARGET.
%   [OK, MESSAGE] = buildHelpPageInto(MANUALDIR, TARGET) takes the HTML
%   manual from MANUALDIR (manual/manual.html), rendering it first with
%   Quarto when it is missing or older than its sources, and writes it to
%   TARGET ready for the app's viewer. MESSAGE explains a failure, for
%   showing to the user, or notes that an older copy was used.
%   FINDQUARTO, optional, is a function returning the quarto executable or
%   '' (default: locateQuartoTools), so a test can take Quarto away.
%
%   THE MANUAL IS THE HELP. The help page used to be the README rendered by
%   a Node script. The manual (manual/, Quarto) is now the documentation,
%   and the README a landing page, so Help shows the manual: one text, kept
%   up to date in one place.
%
%   A RELEASE NEEDS NO QUARTO. The release ships manual/manual.html, so on
%   an installed copy this is a copy and two small rewrites. A working copy
%   renders it, which needs Quarto (bundled with RStudio) and about two
%   minutes; a copy older than its sources is re-rendered when Quarto is
%   there, and used as it is, with a note, when it is not.
%
%   TWO REWRITES FOR THE VIEWER. uihtml is served over MATLAB's connector,
%   whose content-security policy refuses stylesheets and scripts given as
%   data: URIs, which is how Quarto's self-contained output delivers them;
%   inlineDataUriResources turns them into inline blocks, as it does for the
%   reports. And an ordinary link does nothing in a uihtml, which has no
%   window to open into, so a small script hands every link that leaves the
%   page to MATLAB (Alakazam.onHelp opens it in the real browser).
%
%   A PLAIN FUNCTION SO IT CAN BE TESTED without a running application.
%
%   See also ALAKAZAM.BUILDHELPPAGE, ALAKAZAM.ONHELP, INLINEDATAURIRESOURCES.
    ok = false;
    message = '';
    if nargin < 3 || isempty(findQuarto)
        findQuarto = @quartoFromTools;
    end

    source = fullfile(manualDir, 'manual.qmd');
    built  = fullfile(manualDir, 'manual.html');
    haveBuilt = exist(built, 'file') == 2;
    if ~haveBuilt && exist(source, 'file') ~= 2
        message = sprintf(['The manual is missing from this copy (expected %s, or ' ...
            'its source %s).'], built, source);
        return;
    end

    if ~haveBuilt || (exist(source, 'file') == 2 && isStale(built, manualDir))
        quarto = findQuarto();
        if isempty(quarto)
            if ~haveBuilt
                message = ['Building the help page renders the manual with Quarto, ' ...
                    'which was not found on this machine (it is bundled with RStudio). ' ...
                    'Quarto is not needed for anything else in Alakazam except the ' ...
                    'statistical reports.'];
                return;
            end
            message = ['The manual has changed since this copy of it was rendered, and ' ...
                'Quarto was not found to render it again, so the older copy is shown.'];
        else
            [status, output] = runIn(manualDir, ...
                sprintf('"%s" render manual.qmd --to html', quarto));
            if status ~= 0 || exist(built, 'file') ~= 2
                message = sprintf('The manual could not be rendered:\n\n%s', ...
                    lastLines(output, 12));
                return;
            end
        end
    end

    [copied, copyMessage] = copyfile(built, target, 'f');
    if ~copied
        message = sprintf('The manual was rendered but could not be copied to %s: %s', ...
            target, copyMessage);
        return;
    end
    inlineDataUriResources(target);
    addLinkBridge(target);
    ok = true;
end

% ======================================================================= %
function exe = quartoFromTools()
    [~, exe] = locateQuartoTools();
end

function tf = isStale(built, manualDir)
%ISSTALE  Whether any source of the manual is newer than its HTML.
    builtTime = dir(built).datenum;
    sources = [dir(fullfile(manualDir, '*.qmd')); dir(fullfile(manualDir, '*.bib')); ...
        dir(fullfile(manualDir, 'chapters', '*.qmd')); dir(fullfile(manualDir, 'images', '*'))];
    sources = sources(~[sources.isdir]);
    tf = any([sources.datenum] > builtTime);
end

function addLinkBridge(htmlFile)
%ADDLINKBRIDGE  Hand links that leave the page to MATLAB. uihtml calls a
%   page's setup(htmlComponent) once it is loaded; the listener sends the
%   link as an 'openUrl' event, which Alakazam.onHelp opens in the browser.
%   Links within the page (#sec-...) are left to work as they do.
    fid = fopen(htmlFile, 'r', 'n', 'UTF-8');
    html = fread(fid, '*char')';
    fclose(fid);
    if contains(html, 'alzHelpBridge')
        return;
    end
    bridge = ['<script id="alzHelpBridge">' newline ...
        'let alzHelp;' newline ...
        'function setup(htmlComponent) {' newline ...
        '  alzHelp = htmlComponent;' newline ...
        '  document.addEventListener(''click'', function (e) {' newline ...
        '    const a = e.target.closest(''a'');' newline ...
        '    if (!a) { return; }' newline ...
        '    const href = a.getAttribute(''href'') || '''';' newline ...
        '    if (href === '''' || href.startsWith(''#'')) { return; }' newline ...
        '    e.preventDefault();' newline ...
        '    if (alzHelp) { alzHelp.sendEventToMATLAB(''openUrl'', a.href); }' newline ...
        '  });' newline ...
        '}' newline ...
        '</script>' newline];
    bodyEnd = strfind(html, '</body>');
    if isempty(bodyEnd)
        html = [html bridge];
    else
        html = [html(1:bodyEnd(end) - 1) bridge html(bodyEnd(end):end)];
    end
    fid = fopen(htmlFile, 'w', 'n', 'UTF-8');
    fprintf(fid, '%s', html);
    fclose(fid);
end

function [status, output] = runIn(folder, command)
    here = pwd;
    back = onCleanup(@() cd(here));
    cd(folder);
    [status, output] = system(command);
    clear back;
end

function text = lastLines(output, n)
    lines = splitlines(strtrim(string(output)));
    text = char(strjoin(lines(max(1, end - n + 1):end), newline));
end
