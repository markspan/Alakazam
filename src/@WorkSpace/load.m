function load(this,~,~)
%LOAD  Read a .wksp file (JSON) and open the workspace it describes.
    [this.Name, Path] = uiextras.uigetfile2('*.wksp');
    if (this.Name == 0) %% Cancel
        return;
    end

    workspace = jsondecode(fileread(fullfile(Path, this.Name)));

    % Expand any home-relative ("~/...") directories to absolute paths for this
    % machine; absolute paths (other drives, network mounts) pass through.
    this.RawDirectory     = this.fromStoredPath(workspace.RawDirectory);
    this.CacheDirectory   = this.fromStoredPath(workspace.CacheDirectory);
    this.ExportsDirectory = this.fromStoredPath(workspace.ExportsDirectory);

    % Per-transformation remembered options this workspace was last saved
    % with (see TransformSettings); absent on an older-format .wksp file,
    % which TransformSettings.loadFrom treats as "none stored".
    if isfield(workspace, 'TransformSettings')
        TransformSettings.loadFrom(workspace.TransformSettings);
    else
        TransformSettings.reset();
    end

    this.open();
end
