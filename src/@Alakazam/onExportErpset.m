function onExportErpset(this)
%ONEXPORTERPSET  Context-menu callback: export the selected Averaged dataset
%   as an ERPLAB erpset (.erp). The menu item is enabled only for averaged
%   data (eligibility baked into the node at creation time -- see
%   WorkSpaceTree.optsFor's canExportErpset), so in practice EEG.DataFormat is
%   always 'Averaged' here; averagedToErpset re-checks and errors clearly if
%   not. The .erp file is a plain MAT-file holding an ERP struct, which ERPLAB
%   (pop_loaderp) and Alakazam (loadERPFile) both read back.
    node = this.Workspace.ActiveTree.SelectedNodes;
    if isempty(node)
        return; % nothing selected
    end

    EEG = this.loadNodeEEG(node.UserData, 'export this dataset as an erpset');
    if isempty(EEG)
        return;
    end
    if ~isfield(EEG, 'DataFormat') || ~strcmpi(char(string(EEG.DataFormat)), 'Averaged')
        uialert(this.MainFigure, ...
            ['Only an averaged dataset can be exported as an erpset. Run Average ' ...
             '(on segmented data) first, then export its result.'], ...
            'Not an averaged dataset');
        return;
    end

    exportsDir = this.Workspace.ExportsDirectory;
    if isempty(exportsDir) || ~isfolder(exportsDir)
        exportsDir = pwd;
    end
    [fileName, pathName] = uiputfile('*.erp', 'Export as ERPset', ...
        fullfile(exportsDir, [char(node.Name) '.erp']));
    if isequal(fileName, 0)
        return; % cancelled
    end
    targetFile = fullfile(pathName, fileName);

    this.MainFigure.Pointer = 'watch';
    restorePointer = onCleanup(@() set(this.MainFigure, 'Pointer', 'arrow'));
    try
        ERP = averagedToErpset(EEG);
        ERP.erpname  = char(node.Name);
        ERP.filename = fileName;
        ERP.filepath = pathName;
        save(targetFile, 'ERP');   % .erp is a MAT-file holding ERP
    catch err
        uialert(this.MainFigure, err.message, 'Could not export erpset');
        return;
    end

    uialert(this.MainFigure, sprintf('Exported "%s" to:\n%s', char(node.Name), targetFile), ...
        'Export complete', 'Icon', 'success');
end
