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
    methods (Access = private)
        function setupEEGLab(~)
            % Sets up EEGLab if it is not already available in the path.
            [this.RootDir,~,~] = fileparts(which('Alakazam'));
            cd(this.RootDir);

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
            this.ToolGroup = matlab.ui.internal.desktop.ToolGroup('Alakazam', 'AlakazamApp'); %#ok<CPROP>
            addlistener(this.ToolGroup, 'GroupAction', @(src, event) closeCallback(this, event));
            this.Figures = gobjects(1, 1);
            tabgroup = BuildTabGroupAlakazam(this);
            this.ToolGroup.addTabGroup(tabgroup);
            this.ToolGroup.SelectedTab = 'tabHome';
            this.ToolGroup.setPosition(100, 100, 1080, 720);
            this.ToolGroup.open();
            MD = com.mathworks.mlservices.MatlabDesktopServices.getDesktop; %#ok<JAPIMATHWORKS>
            MD.setDocumentArrangement(this.ToolGroup.Name, MD.TILED, java.awt.Dimension(1, 1));
        end
    end
    methods
        function this = Alakazam(varargin)
            % Constructor for the Alakazam class.
            % Initializes EEGLab, sets up directories, tool group, and workspace.

            this.setupEEGLab();
            this.setupDirectories();
            this.setupToolGroup();
            % create Workspace: this will load the data
            this.Workspace = WorkSpace(this);
            this.Workspace.open();

            % after this, the workspace Panel holds the DataTree
            this.ToolGroup.setDataBrowser(this.Workspace.Panel);
            % for debugging: create a variable holding this
            % Alakazam instance in the base MATLAB
            % workspace. When we create this instance,
            % without assignment it will be referenced only
            % by 'ans', and this is easily overwritten.
            assignin('base', 'AlakazamInst', this)
        end

        function deleteNode(this)
        % deleteNode - Display a delete message.
        %
        % Syntax: deleteNode()
        %
        % Description:
        %   This function displays a message indicating that a node is being deleted.
            disp("delete")
        end

        function expandSingle(this, src,event,f)
        % expandSingle - Expand a single node in the tree.
        %
        % Syntax: expandSingle(this, src, event, f)
        %
        % Inputs:
        %   this - Reference to the current object
        %   src - Source of the event (typically a UI component)
        %   event - Event data
        %   f - Figure or UI context containing the tree node to expand
        %
        % Description:
        %   This function expands a single node in the tree structure based on the
        %   current object context.
            node = f.CurrentObject;
            expand(node)
        end

        function expandAll(this, src,event,tree)
        % expandAll - Expand all nodes in the tree.
        %
        % Syntax: expandAll(this, src, event, tree)
        %
        % Inputs:
        %   this - Reference to the current object
        %   src - Source of the event (typically a UI component)
        %   event - Event data
        %   tree - Tree object containing the nodes to expand
        %
        % Description:
        %   This function expands all nodes in the tree structure.
            expand(tree)
        end

        function delete(this)
        % delete - Destructor for the object.
        %
        % Syntax: delete(this)
        %
        % Description:
        %   This function serves as the destructor for the object. It deletes the
        %   ToolGroup and Figures properties if they are valid.
            if ~isempty(this.ToolGroup) && isvalid(this.ToolGroup)
                delete(this.ToolGroup);
            end
            delete(this.Figures);
        end

        function dropTargetCallback(src,data)
        % dropTargetCallback - Handle drop target callback.
        %
        % Syntax: dropTargetCallback(src, data)
        %
        % Inputs:
        %   src - Source of the drop event
        %   data - Data associated with the drop event
        %
        % Description:
        %   This function handles the callback for a drop target, displaying a
        %   message indicating that an item has been dropped.
            disp('Dropped');
        end

        function ActionOnTransformation(this, ~, ~, userdata)
        % Callback for all transformations.
        % Handles the transformation action, updates the workspace, and plots the result.
            try
                cd(this.RootDir);
                f = findobj('Type', 'Figure','Tag', this.Workspace.EEG.File);
                set(f,'Pointer','watch');

                callfnction = char(userdata);
                lastdotpos = find(callfnction == '.', 1, 'last');
                id = callfnction(1:lastdotpos-1);
                functionCall= ['EEG=' id '(x.EEG);'];

                [a.EEG, used_params] = feval(id, this.Workspace.EEG);

                if ishandle(a.EEG)
                    %% the function returned a handle: this means there is
                    % no real transformation: the function returned a plot.
                    % plotFigure(this, a.EEG);
                    this.Figures(end+1) = a.EEG;
                    this.ToolGroup.addFigure(this.Figures(end));
                    this.Figures(end).Visible = 'on';
                    %set(this.Figures(end), 'Toolbar', 'none');
                    set(f,'Pointer','arrow');
                    return
                end

                a.EEG.Call = functionCall;
                if (isstruct(used_params))
                    a.EEG.params = used_params;
                else
                    a.EEG.params = struct( 'Param', used_params);
                end

                CurrentNode = this.Workspace.Tree.SelectedNodes.Name;
                % Build new FileID (Name) based on the name of the current
                % node, the used transformationID and a timestamp.
                % does the transdir for this file exist?
                [parent.dir, parent.name] = fileparts(a.EEG.File);

                cDir = fullfile(parent.dir,parent.name);
                if ~exist(cDir, 'dir')
                    cDir = fullfile(parent.dir,parent.name);
                    mkdir(cDir);
                end

                Key = [id datestr(datetime('now'), 'DDhhMMss')]; %#ok<DATST>
                a.EEG.File = strcat(parent.dir, '\',parent.name, '\' , Key, '.mat');
                a.EEG.id =  [char(CurrentNode) ' - ' id];

                NewNode=uiextras.jTree.TreeNode('Name',a.EEG.id,'Parent',this.Workspace.Tree.SelectedNodes, 'UserData',a.EEG.File);
                if strcmpi(a.EEG.DataType, 'TIMEDOMAIN')
                    setIcon(NewNode,this.Workspace.TimeSeriesIcon);
                elseif strcmpi(a.EEG.DataType, 'FREQUENCYDOMAIN')
                    setIcon(NewNode,this.Workspace.FrequenciesIcon);
                end
                NewNode.Parent.expand();
                this.Workspace.Tree.SelectedNodes = NewNode;

                EEG=a.EEG;
                save(a.EEG.File, 'EEG');
                this.Workspace.EEG=EEG;

                plotCurrent(this);
                set(f,'Pointer','arrow');

            catch ME
                set(f,'Pointer','arrow');
                warndlg(ME.message, 'Error in transformation');
                throw (ME)
                %;
            end
        end


        function plotCurrent(this)
            % Plots the current EEG data.
            % Opens a new figure or shows an existing one for the current EEG data.
            f = findobj('Type', 'Figure','Tag', this.Workspace.EEG.File);
            if ~isempty(f)
                % then just show it
                this.ToolGroup.showClient(get(f, 'Name'));
                return
            end

            % add plot as a new document
            this.Figures(end+1) = figure('NumberTitle', 'off', 'Name', this.Workspace.EEG.id,'Tag', this.Workspace.EEG.File, ...
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

            %% EPOCHED DATA PLOT
            hEEG = Tools.hEEG;
            hEEG.toHandle(this.Workspace.EEG);
            set(this.Figures(end), 'UserData', this.Workspace.EEG);
            if strcmpi(this.Workspace.EEG.DataFormat, 'EPOCHED') | strcmpi(this.Workspace.EEG.DataFormat, 'AVERAGED')
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
                this.ToolGroup.addFigure(this.Figures(end));
                this.Figures(end).Visible = 'on';
                set(this.Figures(end), 'Toolbar', 'none');
                %[tb,btns] = axtoolbar(gca,{'export','brush','datacursor','restoreview'});

            end
        end
        function NodeEdited(this, tree, args)
            % Callback for when a node is edited.
            % Updates the EEG id and saves the changes.
            this.Workspace.EEG.id = args.Nodes.Name;
            EEG = this.Workspace.EEG;
            save(this.Workspace.EEG.File, 'EEG');

        end
        function TreeDropNode(this, tree, args)
            % Handles node drop actions in the tree.
            % Performs copy or move operations based on the drop action.
            % Called when a Treenode is Dropped on another Treenode.
            % I prefer a switch of "copy" and "move" here.
            cd(this.RootDir);
            if ~isempty(args.Source.Parent.Parent) % if not a rootnode
                switch args.DropAction
                    case 'copy'
                        % No action modifier: actually moves.
                        set(args.Source,'Parent',args.Target)
                        %% Do the Evaluation of the commands here:
                        % dont forget to rename the target Node.
                        expand(args.Target)
                        expand(args.Source)
                    case 'move'
                        % control click: action modifier: actually copies.
                        %% Do the Evaluation of the commands here:
                        % dont forget to rename the target Node.
                        %NewSourceNode = copy(args.Source,args.Target);
                        this.Evaluate(args.Source.UserData, args.Target);

                        %expand(args.Target)
                        %expand(args.Source)
                        %expand(NewSourceNode)
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
                idx1 = strfind(OldEEGStruct.EEG.Call, '=');
                idx2 = strfind(OldEEGStruct.EEG.Call, '(');

                id = OldEEGStruct.EEG.Call(idx1+1:idx2-1);

                % ugly hack to plot multiple Averages over eachother
                % The dropsite is NewEEGStruct, the data that is dropped is
                % OldEEGStruct.
                if strcmpi(NewEEGStruct.EEG.DataFormat, 'AVERAGED') & ...
                        strcmpi(OldEEGStruct.EEG.DataFormat, 'AVERAGED') & ...
                        length(size(NewEEGStruct.EEG.data)) == length(size(OldEEGStruct.EEG.data)) & ...
                        size(NewEEGStruct.EEG.data) == size(OldEEGStruct.EEG.data)

                    hold off
                    f = findobj('Type', 'Figure','Tag', NewEEGStruct.EEG.File);
                    % was dropsite already plotted?
                    if ~isempty(f)
                        % then show it
                        this.ToolGroup.showClient(get(f, 'Name'));
                    else
                        % plot it.
                        this.Workspace.EEG=NewEEGStruct.EEG;
                        plotCurrent(this);
                    end
                    hold on
                    %and add the new plot
                    f = findobj('Type', 'Figure','Tag', NewEEGStruct.EEG.File);
                    Tools.plotEpochedTimeMultiAverage(OldEEGStruct.EEG, f);
                    hold off
                    endnode=true;
                else
                    % every other case: dropped a branch on a set
                    [a.EEG, ~] = feval(id, NewEEGStruct.EEG, OldEEGStruct.EEG.params);
                    CurrentNode = NewEEGStruct.EEG.id;
                    Key = [id datestr(datetime('now'), 'DDhhMMss')]; %#ok<DATST>
                    [parent.dir, parent.name] = fileparts(NewEEGStruct.EEG.File);
                    cDir = fullfile(parent.dir,parent.name);

                    if ~exist(cDir, 'dir')
                        cDir = fullfile(parent.dir,parent.name);
                        mkdir(cDir);
                    end

                    a.EEG.File = strcat(parent.dir, '\',parent.name, '\' , Key, '.mat');

                    a.EEG.id =  [char(CurrentNode) ' - ' id];
                    a.EEG.Call = OldEEGStruct.EEG.Call;
                    a.EEG.params = OldEEGStruct.EEG.params;

                    NewNode=uiextras.jTree.TreeNode('Name',a.EEG.id,'Parent',NewParentNode, 'UserData',a.EEG.File);
                    if strcmpi(a.EEG.DataType, 'TIMEDOMAIN')
                        setIcon(NewNode,this.Workspace.TimeSeriesIcon);
                    elseif strcmpi(a.EEG.DataType, 'FREQUENCYDOMAIN')
                        setIcon(NewNode,this.Workspace.FrequenciesIcon);
                    end
                    NewNode.Parent.expand();
                    this.Workspace.Tree.SelectedNodes = NewNode;

                    EEG=a.EEG;
                    save(a.EEG.File, 'EEG');
                    this.Workspace.EEG=EEG;

                    [p,n,~] = fileparts(OldData);
                    if exist([p '\' n], 'dir')
                        NewParentNode = NewNode;
                        NewData = a.EEG.File;
                        name = dir([p '\' n '\' '*.mat' ]);
                        OldData = [p '\' n '\' name.name];
                    else
                        endnode = true;
                    end
                end
            end
        end

        function MouseClicked(this,Tree,args, jmenu)
        % Handles mouse click events on the tree.
        % Differentiates between single, double, and right clicks to perform different actions.
            if (args.Button == 1) % left Button
                if (args.Clicks == 1) % single click
                    % One way or the other: load and display the data.
                    try
                        id = Tree.SelectedNodes.Name;
                    catch
                        return
                    end
                    matfilename = Tree.SelectedNodes.UserData;
                    if exist(matfilename, 'file') == 2
                        % if the file already exists:
                        a=load(matfilename, 'EEG');
                        a.EEG.id = string(id);
                        this.Workspace.EEG = a.EEG;
                    end
                    plotCurrent(this);
                elseif (args.Clicks ==2)
                    plotCurrent(this);
                    disp("DoubleClick!")
                end

            end
            if (args.Button == 3) % right Button
                % show Tearoff Menu!
                disp('Tear!')
                jmenu.show(Tree, 10,10)
            end
        end


        function SelectionChanged(this,Tree,args) %#ok<*INUSD>
            % Handles changes in tree selection.
            % Loads the selected EEG data and updates the workspace.
            EEGStruct = load(args.Nodes.UserData, 'EEG');
            this.Workspace.EEG  = EEGStruct.EEG;
            plotCurrent(this);
        end

        function closeCallback(this, event)
            % Callback for when the tool group is closed.
            % Deletes the current instance of Alakazam.
            ET = event.EventData.EventType;
            if strcmp(ET, 'CLOSED')
                delete(this);
            end
        end

    end
end