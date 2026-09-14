function lines = packageBootstrap(packages)
%PACKAGEBOOTSTRAP  Install-if-missing, then load, the R packages a report
%   needs. LINES = ReportDoc.packageBootstrap(PACKAGES) takes a cellstr of
%   package names and returns the four R lines that bring them in.
%
%   Installing on first render rather than demanding a prepared environment
%   is deliberate: the analyst opening one of these reports is an EEG
%   researcher, not necessarily an R user, and "install these ten packages
%   first" is where a report stops being read. The cost is a slow first
%   render on a fresh machine, once.
%
%   The package list is the caller's, since it is the one thing that really
%   does differ per report: the statistical report needs the modelling
%   stack (lme4, lmerTest, emmeans, effectsize, ...), while the quality and
%   cluster reports need only tidyverse and gt.
%
%   See also REPORTDOC.YAMLHEADER, REPORTDOC.APAHELPERS.
    if isempty(packages)
        throw(MException('Alakazam:ReportDoc:noPackages', ...
            'I am afraid a report needs at least one R package to load.'));
    end
    quoted = cellfun(@(p) ['"' p '"'], packages(:)', 'UniformOutput', false);

    % Wrapped at a readable width rather than emitted as one very long
    % line: this ends up in a .qmd the analyst may well open and edit.
    lines = [ ...
        wrappedVector('pkgs <- c(', quoted, ')'), ...
        {'missing <- pkgs[!pkgs %in% rownames(installed.packages())]' ...
         'if (length(missing)) install.packages(missing, repos = "https://cloud.r-project.org")' ...
         'invisible(lapply(pkgs, library, character.only = TRUE))'}];
end

% ======================================================================= %
function lines = wrappedVector(opener, items, closer)
%WRAPPEDVECTOR  OPENER + comma-separated ITEMS + CLOSER, wrapped to about
%   78 columns with continuation lines indented under the opening bracket.
    limit = 78;
    indent = repmat(' ', 1, numel(opener));

    lines = {};
    current = opener;
    for k = 1:numel(items)
        piece = items{k};
        if k < numel(items)
            piece = [piece ','];  %#ok<AGROW>
        end
        if ~strcmp(current, opener) && numel(current) + 1 + numel(piece) > limit
            lines{end + 1} = current; %#ok<AGROW>
            current = indent;
        elseif ~strcmp(current, opener)
            current = [current ' ']; %#ok<AGROW>
        end
        current = [current piece]; %#ok<AGROW>
    end
    lines{end + 1} = [current closer];
end
