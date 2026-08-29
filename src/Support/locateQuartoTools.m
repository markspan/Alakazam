function [rscriptExe, quartoExe, missing] = locateQuartoTools()
%LOCATEQUARTOTOOLS  Find a working Rscript and quarto executable, beyond
%   just checking PATH. R's own Windows installer does not add it to PATH
%   unless the user explicitly asks for that during install, and quarto
%   is very commonly available only through RStudio's own BUNDLED copy
%   (...\RStudio\resources\app\bin\quarto\bin\quarto.exe), which is never
%   on PATH at all -- both confirmed live on a dev machine with exactly
%   this setup (R + RStudio installed, quarto only ever used as the R
%   package, nothing on PATH). PATH is still tried first (cheapest, and
%   correct on a machine that does have both on PATH); MISSING lists
%   which of {'an R install', 'quarto'} could not be found by any
%   strategy, each with a short note on what was checked.
    missing = {};

    rscriptExe = findOnPath('Rscript');
    if isempty(rscriptExe)
        rscriptExe = findRFromRegistry();
    end
    if isempty(rscriptExe)
        rscriptExe = findRFromCommonPaths();
    end
    if isempty(rscriptExe)
        missing{end + 1} = 'R was not found (checked PATH, the Windows registry, and common install folders).';
    end

    quartoExe = findOnPath('quarto');
    if isempty(quartoExe) && ~isempty(rscriptExe)
        % Ask the R "quarto" package itself where its own quarto lives --
        % exactly what the user's own R/RStudio session already resolves
        % to, so this is tried before guessing at install folders.
        quartoExe = findQuartoFromRPackage(rscriptExe);
    end
    if isempty(quartoExe)
        quartoExe = findQuartoFromCommonPaths();
    end
    if isempty(quartoExe)
        missing{end + 1} = ['quarto was not found (checked PATH, the R "quarto" package, ' ...
            'RStudio''s bundled copy, and common install folders).'];
    end
end

function exe = findOnPath(name)
    [status, ~] = system(sprintf('%s --version', name));
    if status == 0
        exe = name;
    else
        exe = '';
    end
end

function exe = findRFromRegistry()
%FINDRFROMREGISTRY  R's official Windows installer always writes its
%   InstallPath here, regardless of PATH. MATLAB's own winqueryreg cannot
%   read this particular value (confirmed live: throws "Cannot query
%   value of type REG_NONE" even though the value is a perfectly ordinary
%   REG_SZ, readable fine by PowerShell/reg.exe) -- reg.exe plus text
%   parsing sidesteps that.
    exe = '';
    keys = { ...
        'HKEY_LOCAL_MACHINE\SOFTWARE\R-core\R64', ...
        'HKEY_LOCAL_MACHINE\SOFTWARE\R-core\R', ...
        'HKEY_CURRENT_USER\SOFTWARE\R-core\R64', ...
        'HKEY_CURRENT_USER\SOFTWARE\R-core\R'};
    for k = 1:numel(keys)
        [status, out] = system(sprintf('reg query "%s" /v InstallPath', keys{k}));
        if status ~= 0
            continue;
        end
        tok = regexp(out, 'InstallPath\s+REG_SZ\s+(.+)', 'tokens', 'once');
        if isempty(tok)
            continue;
        end
        candidate = fullfile(strtrim(tok{1}), 'bin', 'Rscript.exe');
        if exist(candidate, 'file') == 2
            exe = candidate;
            return;
        end
    end
end

function exe = findRFromCommonPaths()
%FINDRFROMCOMMONPATHS  Last resort: the default install folders the CRAN
%   Windows installer offers, globbed for whatever version is present.
    exe = '';
    roots = {'C:\Program Files\R'};
    localAppData = getenv('LOCALAPPDATA');
    if ~isempty(localAppData)
        roots{end + 1} = fullfile(localAppData, 'Programs', 'R');
    end
    for r = 1:numel(roots)
        versions = dir(fullfile(roots{r}, 'R-*'));
        for v = 1:numel(versions)
            candidate = fullfile(versions(v).folder, versions(v).name, 'bin', 'Rscript.exe');
            if exist(candidate, 'file') == 2
                exe = candidate;
                return;
            end
        end
    end
end

function exe = findQuartoFromRPackage(rscriptExe)
%FINDQUARTOFROMRPACKAGE  Ask the R "quarto" package directly where its
%   own quarto lives (quarto::quarto_path()). Fails harmlessly (empty
%   return) if the package is not installed, or cannot locate its own
%   quarto either -- either way this just falls through to
%   findQuartoFromCommonPaths.
    exe = '';
    [status, out] = system(sprintf('"%s" -e "cat(quarto::quarto_path())"', rscriptExe));
    if status ~= 0
        return;
    end
    candidate = strtrim(out);
    if ~isempty(candidate) && exist(candidate, 'file') == 2
        exe = candidate;
    end
end

function exe = findQuartoFromCommonPaths()
%FINDQUARTOFROMCOMMONPATHS  Last resort: RStudio's own bundled copy (the
%   most common way to end up with a working quarto and nothing on PATH
%   at all), then the standalone Quarto installer's default locations.
    exe = '';
    candidates = { ...
        'C:\Program Files\RStudio\resources\app\bin\quarto\bin\quarto.exe', ...
        'C:\Program Files\Quarto\bin\quarto.exe'};
    localAppData = getenv('LOCALAPPDATA');
    if ~isempty(localAppData)
        candidates{end + 1} = fullfile(localAppData, 'Programs', 'RStudio', ...
            'resources', 'app', 'bin', 'quarto', 'bin', 'quarto.exe');
        candidates{end + 1} = fullfile(localAppData, 'Programs', 'Quarto', 'bin', 'quarto.exe');
    end
    for i = 1:numel(candidates)
        if exist(candidates{i}, 'file') == 2
            exe = candidates{i};
            return;
        end
    end
end
