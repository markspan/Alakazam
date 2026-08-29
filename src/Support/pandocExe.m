function exe = pandocExe()
%PANDOCEXE  The pandoc binary, or '' when there is not one to be had.
%
%   PATH first, since that is cheapest and correct on a machine that has
%   pandoc installed properly. Failing that, the copy Quarto bundles under
%   its own bin/tools -- located by asking locateQuartoTools where quarto
%   is, rather than by guessing at install folders.
%
%   THAT INDIRECTION IS THE POINT. An earlier version of this file did its
%   own two-step lookup: pandoc on PATH, then quarto on PATH and pandoc
%   beside it. It found nothing on a machine with both R and Quarto
%   installed, because RStudio bundles quarto at
%   ...\RStudio\resources\app\bin\quarto\bin and never puts it on PATH --
%   the exact case locateQuartoTools was written for, and had already
%   solved, and which renderQuartoReport had been relying on for as long as
%   it has existed. Two discoveries meant one of them was wrong.
%
%   Cached for the session: locateQuartoTools shells out several times on a
%   miss (PATH, the registry, the R quarto package), and the answer does not
%   change while the application is running. (Unlike a version string, which
%   is why alakazamVersion deliberately does NOT cache -- there the answer
%   can change under you when you tag a release with the app still open.)
%
%   See also LOCATEQUARTOTOOLS, MARKDOWNDIALOG.
    persistent cached
    if ~isempty(cached)
        exe = cached{1};
        return;
    end

    exe = onPath();
    if isempty(exe)
        exe = besideQuarto();
    end
    cached = {exe};
end

% ======================================================================= %
function exe = onPath()
%ONPATH  pandoc if the shell can find it, '' otherwise.
%   Probed by running it, the same way locateQuartoTools' own findOnPath
%   does: `where` can report a name that is not actually executable.
    exe = '';
    [status, ~] = system('pandoc --version');
    if status == 0
        exe = 'pandoc';
    end
end

function exe = besideQuarto()
%BESIDEQUARTO  Quarto's bundled pandoc, under <quarto bin>/tools.
%   The architecture-suffixed folders are for the Linux and macOS layouts,
%   where Quarto has shipped both flat and per-architecture tools folders.
    exe = '';
    [~, quarto, ~] = locateQuartoTools();
    if isempty(quarto)
        return;
    end

    % locateQuartoTools may return the bare name 'quarto' when it was found
    % on PATH, which says nothing about where it lives; resolve it first.
    if ~contains(quarto, filesep)
        quarto = resolveOnPath(quarto);
        if isempty(quarto)
            return;
        end
    end

    if ispc
        name = 'pandoc.exe';
    else
        name = 'pandoc';
    end
    binDir = fileparts(quarto);
    for candidate = { ...
            fullfile(binDir, 'tools', name), ...
            fullfile(binDir, 'tools', 'x86_64', name), ...
            fullfile(binDir, 'tools', 'aarch64', name)}
        if exist(candidate{1}, 'file') == 2
            exe = candidate{1};
            return;
        end
    end
end

function full = resolveOnPath(name)
%RESOLVEONPATH  A bare command name as a full path, or ''.
    full = '';
    if ispc
        probe = ['where ' name];
    else
        probe = ['which ' name];
    end
    try
        [status, output] = system(probe);
    catch
        return;
    end
    if status ~= 0
        return;
    end
    first = strtrim(strtok(output, newline));
    if exist(first, 'file') == 2
        full = first;
    end
end
