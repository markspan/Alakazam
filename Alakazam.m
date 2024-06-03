classdef Alakazam < handle
    % Based On:
    % "matlab.ui.internal.desktop.showcaseMPCDesigner()" Author(s): R. Chen
    % Copyright 2015 The MathWorks, Inc.
    % C:\Program Files\MatLAB\R2018b\toolbox\matlab\toolstrip\+matlab\+ui\+internal\+desktop
    % Author(s): M.Span, University of Groningen,
    % dept. Experimental Psychology

    properties (Transient = true)
        RootDir
        ToolGroup
        Figures
        Workspace
    end

    methods
        function this = Alakazam(varargin)
            % Constructor for the Alakazam class.
            % Initializes EEGLab, sets up directories, tool group, and workspace.
            this.setupEEGLab();
            this.setupDirectories();
            this.setupToolGroup();
            this.setupWorkspace();
            assignin('base', 'AlakazamInst', this)
        end

        function delete(this)
            % Destructor for the Alakazam class.
            % Cleans up the tool group and figures.
            if ~isempty(this.ToolGroup) && isvalid(this.ToolGroup)
                delete(this.ToolGroup);
            end
            delete(this.Figures);
        end

        function ActionOnTransformation(this, ~, ~, userdata)
            % Callback for all transformations.
            % Handles the transformation action, updates the workspace, and plots the result.
            try
                cd(this.RootDir);
                f = findobj('Type', 'Figure','Tag', this.Workspace.EEG.File);
                set(f,'Pointer','watch');

                callFunction = char(userdata);
                [id, functionCall] = this.parseFunctionCall(callFunction);
                [a.EEG, used_params] = feval(id, this.Workspace.EEG);

                if ishandle(a.EEG)
                    this.plotFigure(a.EEG, f);
                    return;
                end

                a.EEG.Call = functionCall;
                a.EEG.params = this.buildParamsStruct(used_params);

                CurrentNode = this.Workspace.Tree.SelectedNodes.Name;
                [a.EEG.File, a.EEG.id] = this.buildNewFileID(a.EEG.File, id, CurrentNode);

                NewNode = this.createTreeNode(a.EEG);
                this.saveEEG(a.EEG, NewNode);
                plotCurrent(this);
                set(f,'Pointer','arrow');

            catch ME
                set(f,'Pointer','arrow');
                this.handleTransformationError(ME);
            end
        end

        function plotCurrent(this)
            % Plots the current EEG data.
            % Opens a new figure or shows an existing one for the current EEG data.
            f = findobj('Type', 'Figure', 'Tag', this.Workspace.EEG.File);
            if ~isempty(f)
                this.ToolGroup.showClient(get(f, 'Name'));
                return;
            end

            this.createFigure();
            hEEG = Tools.hEEG;
            hEEG.toHandle(this.Workspace.EEG);
            set(this.Figures(end), 'UserData', this.Workspace.EEG);
            this.plotEEGData();
        end

        function NodeEdited(this, ~, args)
            % Callback for when a node is edited.
            % Updates the EEG id and saves the changes.
            this.Workspace.EEG.id = args.Nodes.Name;
            save(this.Workspace.EEG.File, 'EEG', '-struct', 'this.Workspace'); %#ok<USENS> 
        end

        function TreeDropNode(this, ~, args)
            % Handles node drop actions in the tree.
            % Performs copy or move operations based on the drop action.
            cd(this.RootDir);
            if ~isempty(args.Source.Parent.Parent)
                switch args.DropAction
                    case 'copy'
                        set(args.Source, 'Parent', args.Target);
                        expand(args.Target);
                        expand(args.Source);
                    case 'move'
                        this.Evaluate(args.Source.UserData, args.Target);
                    otherwise
                        % Do nothing
                end
            end
        end

        function Evaluate(this, OldData, NewParentNode)
            % Evaluates and processes EEG data for a given node.
            % Loads the EEG data, applies transformations, and updates the tree structure.
            endnode = false;
            NewData = NewParentNode.UserData;
            while ~endnode
                NewEEGStruct = load(NewData, 'EEG');
                OldEEGStruct = load(OldData, 'EEG');
                id = this.parseCallID(OldEEGStruct.EEG.Call);

                if this.shouldPlotAverage(NewEEGStruct, OldEEGStruct)
                    this.plotAverage(NewEEGStruct, OldEEGStruct);
                    endnode = true;
                else
                    [a.EEG, ~] = feval(id, NewEEGStruct.EEG, OldEEGStruct.EEG.params);
                    NewNode = this.createTreeNodeForEvaluation(a.EEG, NewParentNode, OldEEGStruct.EEG.Call, OldEEGStruct.EEG.params);
                    this.saveEEG(a.EEG, NewNode);

                    [p, n, ~] = fileparts(OldData);
                    if exist([p filesep n], 'dir')
                        NewParentNode = NewNode;
                        NewData = a.EEG.File;
                        name = dir([p filesep n filesep '*.mat']);
                        OldData = [p filesep n filesep name.name];
                    else
                        endnode = true;
                    end
                end
            end
        end

        function MouseClicked(this, Tree, args, jmenu)
            % Handles mouse click events on the tree.
            % Differentiates between single, double, and right clicks to perform different actions.
            if args.Button == 1 && args.Clicks == 1
                this.handleSingleClick(Tree);
            elseif args.Button == 1 && args.Clicks == 2
                this.handleDoubleClick();
            elseif args.Button == 3
                jmenu.show(Tree, 10, 10);
            end
        end

        function SelectionChanged(this, ~, args)
            % Handles changes in tree selection.
            % Loads the selected EEG data and updates the workspace.
            EEGStruct = load(args.Nodes.UserData, 'EEG');
            this.Workspace.EEG = EEGStruct.EEG;
            plotCurrent(this);
        end

        function closeCallback(this, event)
            % Callback for when the tool group is closed.
            % Deletes the current instance of Alakazam.
            if strcmp(event.EventData.EventType, 'CLOSED')
                delete(this);
            end
        end
    end

    methods (Access = private)
        function setupEEGLab(~)
            % Sets up EEGLab if it is not already available in the path.
            if isempty(which('eeglab'))
                cd("./eeglab");
                eeglab;
                savepath;
                cd("..");
            end
        end

        function setupDirectories(this)
            % Sets up the necessary directories and paths for the application.
            [this.RootDir,~,~] = fileparts(which('Alakazam'));
            cd(this.RootDir);
            close all;
            warning('off', 'MATLAB:ui:javacomponent:FunctionToBeRemoved');
            addpath(this.RootDir, '-end');
            addpath(genpath('Transformations'), 'mlapptools');
        end

        function setupToolGroup(this)
            % Sets up the tool group for the application.
            % Initializes the tool group, tab group, and figure properties.
            this.ToolGroup = ToolGroup('Alakazam', 'AlakazamApp'); %#ok<CPROP> 
            addlistener(this.ToolGroup, 'GroupAction', @(src, event) closeCallback(this, event));

            this.Figures = gobjects(1, 1);
            tabgroup = BuildTabGroupAlakazam(this);
            this.ToolGroup.addTabGroup(tabgroup);
            this.ToolGroup.SelectedTab = 'tabHome';
            this.ToolGroup.setPosition(100, 100, 1080, 720);
            this.ToolGroup.open;

            MD = com.mathworks.mlservices.MatlabDesktopServices.getDesktop; %#ok<JAPIMATHWORKS> 
            MD.setDocumentArrangement(this.ToolGroup.Name, MD.TILED, java.awt.Dimension(1, 1));
        end

        function setupWorkspace(this)
            % Sets up the workspace for the application.
            % Opens the workspace panel and sets it in the tool group.
            this.Workspace = WorkSpace(this);
            this.Workspace.open();
            this.ToolGroup.setDataBrowser(this.Workspace.Panel);
        end

        function plotFigure(this, EEG, f)
            % Plots a new figure for the EEG data.
            % Adds the new figure to the tool group and sets its properties.
            this.Figures(end+1) = EEG;
            this.ToolGroup.addFigure(this.Figures(end));
            this.Figures(end).Visible = 'on';
            set(f, 'Pointer', 'arrow');
        end

        function [id, functionCall] = parseFunctionCall(~, callFunction)
            % Parses the function call string to extract the function ID and call.
            % Returns the function ID and formatted function call string.
            lastdotpos = find(callFunction == '.', 1, 'last');
            id = callFunction(1:lastdotpos-1);
            functionCall = ['EEG=' id '(x.EEG);'];
        end

        function params = buildParamsStruct(~, used_params)
            % Builds a parameters struct from the used parameters.
            % Returns the constructed parameters struct.
            params = struct();
            for i = 1:length(used_params)
                params.(used_params{i}) = eval(used_params{i});
            end
        end

        function [file, id] = buildNewFileID(~, ~, id, CurrentNode)
            % Builds a new file ID and file path based on the current node.
            % Returns the updated file path and ID.
            file = ['eeg' filesep CurrentNode filesep id '_' char(datetime('now','Format','yyyyMMddHHmmss')) '.mat'];
            id = [CurrentNode '.' id];
        end

        function NewNode = createTreeNode(this, EEG)
            % Creates a new tree node for the given EEG data.
            % Returns the created tree node.
            NewNode = uiextras.jTree.TreeNode('Name', EEG.id, 'Parent', this.Workspace.Tree.SelectedNodes, 'UserData', EEG.File);
            setIcon(NewNode, this.Workspace.EEGIcon);
            expand(this.Workspace.Tree.SelectedNodes);
        end

        function saveEEG(~, EEG, NewNode)
            % Saves the EEG data to a file and updates the new node.
            save(EEG.File, 'EEG');
            NewNode.UserData = EEG.File;
        end

        function handleTransformationError(~, ME)
            % Handles errors that occur during the transformation process.
            % Displays an error message.
            errordlg({'Transformation failed!', ME.message}, 'Error', 'modal');
            rethrow(ME);
        end

        function createFigure(this)
            % Creates a new figure for displaying EEG data.
            % Returns the created figure.
            this.Figures(end+1) = figure('NumberTitle', 'off', ...
                'Name', this.Workspace.EEG.id,...
                'Tag', this.Workspace.EEG.File, ...
                'Color' ,[.98 .98 .98], ...
                'PaperOrientation','landscape', ...
                'PaperPosition',[.05 .05 .9 .9], ...
                'PaperPositionMode', 'auto',...
                'PaperType', 'A0', ...
                'Units', 'normalized', ...
                'MenuBar', 'none', ...
                'Toolbar', 'none',...
                'DockControls','on', ...
                'Visible','off' ...
                );
            %this.ToolGroup.addFigure(this.Figures(end));
        end

        function plotEEGData(this)
            if strcmpi(this.Workspace.EEG.DataFormat, 'EPOCHED') || strcmpi(this.Workspace.EEG.DataFormat, 'AVERAGED')
                if strcmpi(this.Workspace.EEG.DataType, 'TIMEDOMAIN')
                    if (this.Workspace.EEG.nbchan > 1)
                        if (isfield(this.Workspace.EEG, 'trials'))
                            if (this.Workspace.EEG.trials > 1)
                                % Multichannel plot epoched
                                % channels:time:trial
                                Tools.plotEpochedTimeMulti(this.Workspace.EEG, this.Figures(end));
                            elseif (this.Workspace.EEG.trials == 1)
                                % Average: we have std....
                                Tools.plotEpochedTimeMultiAverage(this.Workspace.EEG, this.Figures(end));
                            end
                        end
                    else
                        % Singlechannel plot epoched
                    end

                elseif strcmpi(this.Workspace.EEG.DataType, 'FREQUENCYDOMAIN')
                    %% Fourier Plot (Multichannel and singlechannel) epoched
                    Tools.plotFourier(this.Workspace.EEG, this.Figures(end));
                end
                this.ToolGroup.addFigure(this.Figures(end));
                this.Figures(end).Visible = 'on';
            else
                %% NOT EPOPCHED: CONTINUOUS
                if strcmpi(this.Workspace.EEG.DataType, 'TIMEDOMAIN')
                    if (this.Workspace.EEG.nbchan > 1)
                        % Multichannel plot
                        Tools.plotECG(this.Workspace.EEG.times, this.Workspace.EEG, ...
                            'ShowAxisTicks','on',...
                            'YLimMode', 'fixed', ...
                            'mmPerSec', 25,...
                            'AutoStackSignals', {this.Workspace.EEG.chanlocs.labels},...
                            'Parent',  this.Figures(end));
                    else
                        % Singlechannel Plot,
                        Tools.plotECG(this.Workspace.EEG.times, this.Workspace.EEG, 'b-',...
                            'mmPerSec', 25,...
                            'ShowAxisTicks','on',...
                            'YLimMode', 'fixed',...
                            'Parent',  this.Figures(end));
                    end
                else
                    %Fourier Plot
                    Tools.plotFourier(this.Workspace.EEG, this.Figures(end));
                end
                
                succes = this.ToolGroup.addFigure(this.Figures(end));
                if (succes)
                    this.Figures(end).Visible = 'on';
                    set(this.Figures(end), 'Toolbar', 'none');
                end
                %[tb,btns] = axtoolbar(gca,{'export','brush','datacursor','restoreview'});
            end
        end

        function id = parseCallID(~, call)
            % Parses the call string to extract the function ID.
            % Returns the extracted function ID.
            split = regexp(call, '\.','split');
            id = split{1};
        end

        function plotAverage(this, NewEEGStruct, OldEEGStruct)
            % Plots the average EEG data from two EEG structs.
            % Creates a new tree node and saves the averaged EEG data.
            a.EEG = feval('averageM', NewEEGStruct.EEG, OldEEGStruct.EEG);
            NewNode = this.createTreeNode(a.EEG);
            this.saveEEG(a.EEG, NewNode);
        end

        function NewNode = createTreeNodeForEvaluation(this, EEG, ParentNode, Call, params)
            % Creates a tree node for EEG data during evaluation.
            % Sets the icon and expands the parent node.
            NewNode = uiextras.jTree.TreeNode('Name', EEG.id, 'Parent', ParentNode, 'UserData', EEG.File);
            if strcmpi(EEG.DataType, 'TIMEDOMAIN')
                setIcon(NewNode, this.Workspace.TimeSeriesIcon);
            elseif strcmpi(EEG.DataType, 'FREQUENCYDOMAIN')
                setIcon(NewNode, this.Workspace.FrequenciesIcon);
            end
            NewNode.Parent.expand();
        end

        function shouldPlot = shouldPlotAverage(~, NewEEGStruct, OldEEGStruct)
            % Determines if the average of EEG data should be plotted.
            % Returns a boolean indicating whether to plot the average.
            shouldPlot = strcmpi(NewEEGStruct.EEG.DataType, 'TIMEDOMAIN') && strcmpi(OldEEGStruct.EEG.DataType, 'TIMEDOMAIN');
        end

        function handleSingleClick(this, Tree)
            % Handles single click events on the tree.
            % Loads and plots the selected EEG data.
            EEGStruct = load(Tree.SelectedNodes.UserData, 'EEG');
            this.Workspace.EEG = EEGStruct.EEG;
            plotCurrent(this);
        end

        function handleDoubleClick(~)
            % Handles double click events.
            % Displays a message for double click action.
            disp('Double click action');
        end
    end
end
