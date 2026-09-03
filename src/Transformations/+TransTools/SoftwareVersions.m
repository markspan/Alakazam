function versions = SoftwareVersions()
%SOFTWAREVERSIONS  What actually produced a result: MATLAB, FieldTrip and
%   Alakazam itself.
%
%   VERSIONS has .matlab, .fieldtrip and .alakazam, each a char string, with
%   'unknown' wherever it cannot be determined.
%
%   REQUIRED BY REPORTING GUIDELINES, not decoration. COBIDAS MEEG (Pernet
%   et al., 2020) asks for the software and version behind every analysis,
%   because an inverse solution or a permutation scheme can change between
%   releases and a result is not reproducible without knowing which one ran.
%   A report that omits it cannot be checked later, including by the person
%   who produced it.
%
%   Alakazam's own version is the git commit, which is the only identifier
%   this project actually has: there is no release number to report, and a
%   commit is more precise than one anyway. Determined by asking git, and
%   reported as 'unknown' rather than guessed when the working tree is not a
%   repository (an installed copy, or a source drop).
%
%   Cached for the session: three shell-outs per report is three too many,
%   and none of these can change while MATLAB is running.
%
%   See also GENERATESOURCECLUSTERSTATSREPORT.
    persistent cached
    if ~isempty(cached)
        versions = cached;
        return;
    end

    versions = struct('matlab', 'unknown', 'fieldtrip', 'unknown', 'alakazam', 'unknown');

    try
        versions.matlab = ['MATLAB ' version('-release')];
    catch
    end

    try
        [ftVersion, ftPath] = ft_version;
        if ischar(ftVersion) && ~isempty(ftVersion)
            versions.fieldtrip = ftVersion;
        elseif ~isempty(ftPath)
            [~, folder] = fileparts(ftPath);
            versions.fieldtrip = folder;
        end
    catch
        % ft_version shells out to git inside FieldTrip's own folder and
        % fails on a downloaded zip, which is exactly how Alakazam installs
        % it. Fall back to the folder name, which carries the release date.
        try
            ftRoot = fileparts(which('ft_defaults'));
            [~, folder] = fileparts(ftRoot);
            if ~isempty(folder)
                versions.fieldtrip = folder;
            end
        catch
        end
    end

    versions.alakazam = alakazamCommit();
    cached = versions;
end

% ======================================================================= %
function commit = alakazamCommit()
%ALAKAZAMCOMMIT  The short commit this source tree is at, plus a marker when
%   it has uncommitted changes. A report generated from a dirty tree does
%   not correspond to any commit, and saying so is more useful than naming a
%   commit the code no longer matches.
    commit = 'unknown';
    here = fileparts(fileparts(fileparts(mfilename('fullpath'))));  % src/
    root = fileparts(here);
    if ~exist(fullfile(root, '.git'), 'dir')
        return;
    end
    try
        [status, out] = system(sprintf('git -C "%s" rev-parse --short HEAD', root));
        if status ~= 0
            return;
        end
        commit = strtrim(out);
        [dirtyStatus, dirtyOut] = system(sprintf('git -C "%s" status --porcelain', root));
        if dirtyStatus == 0 && ~isempty(strtrim(dirtyOut))
            commit = [commit ' (with uncommitted changes)'];
        end
    catch
        commit = 'unknown';
    end
end
