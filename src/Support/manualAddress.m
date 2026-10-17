function url = manualAddress(transformId)
%MANUALADDRESS  Where a transformation's manual is on the web, for its ?
%   button: the address, or '' when it has none.
%
%   URL = manualAddress(TRANSFORMID) is, in this order:
%     - what its manifest's own "Manual" field says: a web address, or an
%       anchor ("#sec-...") in Alakazam's manual;
%     - for a built-in transformation, its section in Alakazam's manual,
%       #sec-tr-<its id in lower case>, which every one of them has
%       (ManualAddressTest checks each against the manual's chapters);
%     - for a plugin, the GitHub Pages of the repository it was installed
%       from (github.com/owner/AlakazamX gives owner.github.io/AlakazamX/),
%       where the account's plugins keep their manuals.
%
%   See also OPENINBROWSER, PLUGINS.PAGESADDRESS, TRANSTOOLS.CURRENTTOOL.
    url = '';
    transformId = char(string(transformId));
    if isempty(transformId) || ~isvarname(transformId)
        return;
    end
    builtInRoot = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'Transformations');
    folder = Plugins.transformationFolder(transformId, builtInRoot);
    if isempty(folder)
        return;
    end

    alakazamManual = sprintf('https://%s.github.io/Alakazam/', Plugins.Account);
    stated = '';
    manifest = Plugins.manifest(transformId, builtInRoot);
    if isstruct(manifest) && isscalar(manifest) && isfield(manifest, 'Manual')
        stated = strtrim(char(string(manifest.Manual)));
    end
    if startsWith(stated, '#')
        url = [alakazamManual stated];
    elseif ~isempty(regexp(stated, '^https?://', 'once'))
        url = stated;
    elseif strncmpi(folder, builtInRoot, numel(builtInRoot))
        url = [alakazamManual '#sec-tr-' lower(transformId)];
    else
        installed = Plugins.installed();
        mine = installed(strcmp({installed.Name}, transformId));
        if ~isempty(mine)
            url = Plugins.pagesAddress(mine(1).Link);
        end
    end
end
