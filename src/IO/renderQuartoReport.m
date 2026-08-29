function [htmlFile, errorMessage] = renderQuartoReport(qmdFile)
%RENDERQUARTOREPORT  Render QMDFILE (a generateQuartoReport .qmd) to HTML
%   via the `quarto` CLI, blocking until it finishes -- matches this app's
%   existing export style (a watch cursor around the call site, no
%   progress bar; see Alakazam.onExportMeasurements), rather than
%   introducing a background/async render: there is no existing
%   non-blocking-task pattern anywhere in this codebase to build on, and a
%   report this size (a handful of statistical tests and violin plots) is
%   a matter of seconds, not minutes.
%
%   Every ```{r} chunk in the report needs R installed (quarto calls out
%   to it via knitr), so both an R and a quarto executable are located
%   (see locateQuartoTools) before attempting anything -- a specific "R
%   not found" is far more useful than quarto's own opaque failure when
%   it cannot locate an R install.
%
%   On success, HTMLFILE is the rendered .html path (quarto's own default:
%   same folder and stem as QMDFILE) and ERRORMESSAGE is ''. On failure
%   (quarto/R missing, or quarto's own render error), HTMLFILE is '' and
%   ERRORMESSAGE explains why -- never thrown, since the caller treats
%   "could not render" as a soft fallback (fall back to the file being
%   written but not shown), not a hard error.
%
%   See also GENERATEQUARTOREPORT, ALAKAZAM.ONEXPORTMEASUREMENTS,
%   ALAKAZAM.PERSISTREPORTNODE.
    htmlFile = '';

    [rscriptExe, quartoExe, missing] = locateQuartoTools();
    if ~isempty(missing)
        errorMessage = strjoin(missing, ' ');
        return;
    end

    [folder, stem] = fileparts(qmdFile);
    expectedHtml = fullfile(folder, [stem '.html']);

    % QUARTO_R tells quarto's own render subprocess exactly which R to
    % use for every ```{r} chunk -- quarto's built-in R search is
    % PATH-based too, so without this, an R this function found just fine
    % (via the registry or a common install folder, see
    % locateQuartoTools) can still make the render itself fail to find R.
    cmd = sprintf('set "QUARTO_R=%s" && "%s" render "%s" --to html', rscriptExe, quartoExe, qmdFile);
    [status, cmdout] = system(cmd);
    if status ~= 0 || exist(expectedHtml, 'file') ~= 2
        errorMessage = strtrim(cmdout);
        if isempty(errorMessage)
            errorMessage = sprintf('quarto render exited with status %d.', status);
        end
        return;
    end

    htmlFile = expectedHtml;
    errorMessage = '';
end

% NOTE: locateQuartoTools and its helpers used to live here. They moved to
% src/Support/locateQuartoTools.m when a second consumer appeared: the
% DefineBins "Syntax..." button needs pandoc, and the copy RStudio bundles
% sits inside the same quarto folder this already knows how to find. One
% discovery, two callers -- the alternative was a second, weaker lookup
% that missed exactly the RStudio case this one was written for.
