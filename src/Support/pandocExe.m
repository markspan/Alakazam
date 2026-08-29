function exe = pandocExe()
%PANDOCEXE  The pandoc binary, or '' when there is not one to be had.
%
%   Looked for on the PATH first, then inside a Quarto installation. Quarto
%   ships its own copy under bin/tools, and installing Quarto is the most
%   likely way pandoc arrives on an analyst's machine without them choosing
%   to install it -- this project already asks for Quarto to render the
%   statistical reports, so a machine set up for those has one.
%
%   Found by locating quarto itself and looking beside it, rather than by
%   guessing at install paths, so it works wherever it was put.
%
%   Cached for the session: this shells out twice on a miss, and the answer
%   does not change while the application is running. (Unlike a version
%   string, which is why alakazamVersion deliberately does NOT cache -- there
%   the answer can change under you when you tag a release with the app
%   still open.)
%
%   See also MARKDOWNDIALOG.
    persistent cached
    if ~isempty(cached)
        exe = cached{1};
        return;
    end

    exe = onPath('pandoc');
    if isempty(exe)
        exe = insideQuarto();
    end
    cached = {exe};
end

% ======================================================================= %
function exe = onPath(name)
%ONPATH  NAME's full path if the shell can find it, '' otherwise.
    exe = '';
    if ispc
        probe = ['where ' name];
    else
        probe = ['which ' name];
    end
    try
        [status, output] = system(probe);
    catch
        return;                                  % system() unavailable
    end
    if status ~= 0
        return;
    end
    first = strtrim(strtok(output, newline));
    if exist(first, 'file') == 2
        exe = first;
    end
end

function exe = insideQuarto()
%INSIDEQUARTO  Quarto's bundled pandoc, or ''.
    exe = '';
    quarto = onPath('quarto');
    if isempty(quarto)
        return;
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
