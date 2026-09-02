function onRibbonAction(this, id)
%ONRIBBONACTION  AlakazamRibbon.ItemPushedFcn: dispatch a ribbon
%   button press. ID is either a fixed action string (the Home and
%   Grand Average tab buttons) or "transform:<Entry>" (a Tools tab
%   transformation button, see AlakazamRibbon.transformationGroups).
    switch id
        case 'openWorkspace'
            this.Workspace.load();
        case 'saveWorkspace'
            this.Workspace.save();
        case 'editWorkspace'
            this.Workspace.edit();
        case 'editSubjects'
            this.Workspace.editSubjects();
        case 'showDesign'
            this.onShowDesign();
        case 'clearWorkspace'
            this.Workspace.rawclear();
        case 'clearOtherAnalyses'
            this.onClearOtherAnalyses();
        case 'settings'
            this.openSettings();
        case 'help'
            this.onHelp();
        case 'about'
            this.onAbout();
        case 'grandAveragePerCell'
            this.onGrandAveragePerCell();
        case 'defineGrandAverage'
            this.onDefineGrandAverage();
        case 'clusterStats'
            this.onClusterStats();
        case 'sourceClusterStats'
            this.onSourceClusterStats();
        case 'exportGrandAverages'
            this.onExportGrandAverages();
        case 'exportMeasurements'
            this.onExportMeasurements();
        case 'exportSpectral'
            this.onExportSpectral();
        case 'analysisScript'
            this.onExportAnalysisScript();
        case 'dataQuality'
            this.onExportDataQuality();
        case 'viewTabs'
            this.setPlotsViewMode("tabs");
        case 'viewGrid'
            this.setPlotsViewMode("grid");
        case 'viewStack'
            this.setPlotsViewMode("stack");
        otherwise
            if startsWith(id, "transform:")
                this.onTransformation(extractAfter(id, "transform:"));
            end
    end
end
