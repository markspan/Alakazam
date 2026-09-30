function tf = ToolboxAvailable(spec)
%TOOLBOXAVAILABLE  True when a toolbox described by SPEC can be used now,
%   without asking anyone.
%
%   TF = TransTools.ToolboxAvailable(SPEC) is true when SPEC.Probe is on the
%   path. Otherwise it looks for the toolbox itself and attaches it when it
%   finds it: first where its entry point (SPEC.ProbeFile) already sits on
%   the path, with its helpers missing (an EEGLAB plugin folder whose plugin
%   was never initialised, say), then in an install from an earlier session
%   (addpath is session-only by design, so a toolbox installed yesterday is
%   on disk but off the path today). Nothing is downloaded and no dialog is
%   shown, so a headless caller (a test, a replay on a worker) can ask. SPEC
%   is described in TransTools.EnsureToolbox.
%
%   See also TRANSTOOLS.ENSURETOOLBOX.
    tf = ~isempty(which(spec.Probe));
    if tf
        return;
    end

    [~, entry] = fileparts(spec.ProbeFile);
    onPath = which(entry);
    if ~isempty(onPath)
        folder = fileparts(onPath);
    else
        folder = EEGLabEnvironment.findInstalled(spec.Folder, spec.ProbeFile);
    end
    if isempty(folder)
        return;
    end

    if isfield(spec, 'Subfolders') && spec.Subfolders
        addpath(genpath(folder));
    else
        addpath(folder);
    end
    tf = ~isempty(which(spec.Probe));
end
