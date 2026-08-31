function fig = MarkdownDialog(titleText, mdFile, parentFig)
%MARKDOWNDIALOG  Show a Markdown document in a scrollable window.
%   FIG = MarkdownDialog(TITLETEXT, MDFILE) renders MDFILE with pandoc and
%   displays it in a uihtml. FIG is the window, so a caller can keep the
%   handle and refocus it rather than opening a second copy.
%
%   MarkdownDialog(TITLETEXT, MDFILE, PARENTFIG) centres the window over
%   PARENTFIG and parents its dialogs to it.
%
%   PANDOC, OR NOTHING. There is no built-in fallback renderer, and that is
%   deliberate: a hand-written Markdown converter is a parser to keep
%   correct forever, in a project whose subject is EEG. When pandoc is
%   absent, FIG comes back empty and the analyst is offered the Markdown
%   file itself, which is perfectly readable and is what they would have
%   been reading anyway -- the same trade Alakazam.offerReadmeInstead makes
%   when the built help page has not been generated.
%
%   NOT MODAL. This shows reference material, and the point of a reference
%   beside an editor is reading it while you type; a window that had to be
%   dismissed first would defeat that.
%
%   See also PANDOCEXE, ALAKAZAM.OFFERREADMEINSTEAD, DEFINEBINSDIALOG.
    fig = [];
    if nargin < 3; parentFig = []; end

    if exist(mdFile, 'file') ~= 2
        throw(MException('Alakazam:MarkdownDialog:missing', ...
            'I am afraid I could not find the document at %s.', mdFile));
    end

    exe = pandocExe();
    if isempty(exe)
        offerTheFileInstead(mdFile, parentFig);
        return;
    end

    body = runPandoc(exe, mdFile);
    if isempty(body)
        offerTheFileInstead(mdFile, parentFig);
        return;
    end

    fig = uifigure('Name', titleText, 'Position', centredOn(parentFig, 780, 720));
    grid = uigridlayout(fig, [1 1], 'Padding', [0 0 0 0]);
    uihtml(grid, 'HTMLSource', page(body), ...
        'HTMLEventReceivedFcn', @(~, evt) openExternal(evt));
end

% ======================================================================= %
function html = runPandoc(exe, mdFile)
%RUNPANDOC  MDFILE through pandoc as an HTML fragment, or '' if it fails.
%
%   A fragment, not a standalone document: the caller supplies the page and
%   its stylesheet, so --standalone would fight it.
%
%   gfm because these documents are written for GitHub and use its table
%   syntax.
%
%   WRITTEN TO A FILE, NOT READ FROM STDOUT. MATLAB's system() merges the
%   child's stderr into the output it returns, so anything pandoc says on
%   the way past ends up at the top of the page as literal text. That is not
%   hypothetical: an earlier version passed --no-highlight, pandoc 3.8
%   deprecated it, and its "[WARNING] Deprecated: --no-highlight" was
%   rendered as the document's first line. Taking the HTML from --output
%   makes any future warning harmless rather than visible.
%
%   (--no-highlight is gone rather than replaced. It was there to stop
%   pandoc injecting a stylesheet that would fight this dialog's own, but a
%   fragment emits no stylesheet at all -- checked: zero occurrences of
%   <style> or sourceCode in the output either way -- so the flag was
%   guarding against something that could not happen.)
    html = '';
    outFile = [tempname() '.html'];
    cleanup = onCleanup(@() deleteIfPresent(outFile));

    try
        status = system(sprintf('"%s" --from=gfm --to=html --output="%s" "%s"', ...
            exe, outFile, mdFile));
    catch
        return;                                  % system() unavailable
    end
    if status ~= 0 || exist(outFile, 'file') ~= 2
        return;
    end
    html = fileread(outFile);
end

function deleteIfPresent(file)
    if exist(file, 'file') == 2
        delete(file);
    end
end

function openExternal(evt)
%OPENEXTERNAL  Open a link the document was clicked on, in the real browser.
%   Only http(s): a rendered document could carry any href at all, and this
%   should not be a way to ask the machine to open arbitrary local paths.
    if ~strcmp(evt.HTMLEventName, 'openUrl')
        return;
    end
    url = char(string(evt.HTMLEventData));
    if isempty(regexp(url, '^https?://', 'once'))
        return;
    end
    try
        web(url, '-browser');
    catch
        web(url);
    end
end

function offerTheFileInstead(mdFile, parentFig)
%OFFERTHEFILEINSTEAD  Open the Markdown source in the system's own handler.
%   Markdown is meant to be readable as text, so this is a smaller loss than
%   it sounds -- and the alternative, a parser of our own, is a larger cost
%   than it sounds.
    message = sprintf(['This reference is rendered with pandoc, which I could not find ' ...
        'on this machine. (Installing Quarto also provides one, and Alakazam already ' ...
        'uses Quarto for its statistical reports.)\n\nI can open the Markdown file ' ...
        'itself instead -- it reads perfectly well as text:\n\n%s'], mdFile);

    if ~confirmAction(parentFig, message, 'pandoc not found', ...
            'Open the file', 'Close', 'Icon', 'info')
        return;
    end
    try
        web(['file:///' strrep(mdFile, '\', '/')], '-browser');
    catch
        web(mdFile);
    end
end

% ======================================================================= %
function html = page(body)
%PAGE  The rendered document wrapped in its own chrome. Self-contained, like
%   every other uihtml page here: the styling is inline, so nothing has to
%   resolve a relative path once the component has loaded the string.
    html = sprintf([ ...
        '<!doctype html><html><head><meta charset="utf-8"><style>\n' ...
        'html,body{margin:0;padding:0;height:100%%;background:#fff;color:#1c2530;' ...
        'font-family:-apple-system,Segoe UI,Arial,sans-serif;font-size:14px;line-height:1.6;}\n' ...
        '#wrap{box-sizing:border-box;height:100%%;overflow-y:auto;padding:26px 34px 40px;}\n' ...
        'h1{font-size:25px;margin:0 0 14px;color:#2e5c8a;}\n' ...
        'h2{font-size:19px;margin:30px 0 8px;color:#2e5c8a;' ...
        'border-bottom:1px solid #e2e8f0;padding-bottom:4px;}\n' ...
        'h3{font-size:15.5px;margin:22px 0 6px;color:#33455c;}\n' ...
        'p{margin:0 0 12px;}\n' ...
        'a{color:#4a7fc9;}\n' ...
        'code{font-family:Consolas,SFMono-Regular,monospace;font-size:12.5px;' ...
        'background:#f2f5f9;padding:1px 4px;border-radius:2px;}\n' ...
        'pre{background:#f6f8fb;border:1px solid #e2e8f0;border-radius:3px;' ...
        'padding:11px 13px;overflow-x:auto;}\n' ...
        'pre code{background:none;padding:0;font-size:12.5px;line-height:1.5;}\n' ...
        'table{border-collapse:collapse;margin:0 0 14px;font-size:13px;}\n' ...
        'th,td{border:1px solid #dde4ec;padding:5px 9px;text-align:left;vertical-align:top;}\n' ...
        'th{background:#f2f5f9;font-weight:600;}\n' ...
        'ul,ol{margin:0 0 12px;padding-left:22px;}\n' ...
        'li{margin-bottom:4px;}\n' ...
        'blockquote{margin:0 0 12px;padding:2px 0 2px 14px;border-left:3px solid #dde4ec;' ...
        'color:#4a5768;}\n' ...
        'hr{border:none;border-top:1px solid #e2e8f0;margin:22px 0;}\n' ...
        '</style></head><body><div id="wrap">\n%s\n</div>\n' ...
        ... % EXTERNAL links only. A uihtml embeds a browser with no window
        ... % to open into, so an ordinary <a> to http(s) does nothing when
        ... % clicked and has to be handed back to MATLAB (the same bridge
        ... % the About page, the ribbon and the workspace tree use).
        ... % In-page "#anchor" links are left alone deliberately: those are
        ... % same-document navigation, they already work, and intercepting
        ... % them would break the reference''s own cross-references.
        '<script>\n' ...
        'let alzDoc;\n' ...
        'function setup(htmlComponent) {\n' ...
        '  alzDoc = htmlComponent;\n' ...
        '  document.addEventListener("click", function (e) {\n' ...
        '    const a = e.target.closest("a");\n' ...
        '    if (!a) { return; }\n' ...
        '    const href = a.getAttribute("href") || "";\n' ...
        '    if (href.startsWith("#")) { return; }\n' ...
        '    e.preventDefault();\n' ...
        '    if (alzDoc) { alzDoc.sendEventToMATLAB("openUrl", href); }\n' ...
        '  });\n' ...
        '}\n' ...
        '</script>\n' ...
        '</body></html>'], body);
end
