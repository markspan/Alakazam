function ok = ensureTransformation(this, transformId, ask)
%ENSURETRANSFORMATION  Make sure the transformation TRANSFORMID can be run,
%   offering to install the plugin that provides it when it is not here.
%
%   OK = ensureTransformation(THIS, TRANSFORMID) is true when TRANSFORMID can
%   be run, already or once its plugin is installed. Several of Alakazam's
%   tools became plugins of their own (AlakazamDeconvolve and the like), and
%   a workspace, a template or a node made with one still names it. When it
%   is missing, the repositories on offer (Plugins.available) are asked which
%   holds it, and the user is offered to install it from there, through the
%   usual confirmation (onInstallPlugin). When none holds it, or the list
%   cannot be had, OK is false and the caller says the step cannot be run.
%
%   ENSURETRANSFORMATION(THIS, TRANSFORMID, ASK) asks with ASK, called as
%   uiconfirm is, instead; the tests pass their own.
%
%   See also PLUGINS.AVAILABLE, PLUGINS.PROVIDEROF, ALAKAZAM.ONINSTALLPLUGIN.
    transformId = char(string(transformId));
    ok = isvarname(transformId) && exist(transformId, 'file') == 2;
    if ok || ~isvarname(transformId)
        return;
    end
    if nargin < 3
        ask = @uiconfirm;
    end
    try
        repo = Plugins.providerOf(transformId, Plugins.available());
    catch
        return;   % no list to be had: the caller says it is missing
    end
    if isempty(repo)
        return;
    end
    choice = ask(this.MainFigure, sprintf(['%s is not installed here. It is a plugin of its ' ...
        'own now, from %s:\n\n    %s\n\nWould you like to install it?'], transformId, ...
        repo.Repo, repo.Link), 'Install a plugin', 'Options', {'Install', 'Not now'}, ...
        'DefaultOption', 1, 'CancelOption', 2);
    if ~strcmp(choice, 'Install')
        return;
    end
    this.onInstallPlugin(repo.Link, repo.Repo);
    rehash;
    ok = exist(transformId, 'file') == 2;
end
