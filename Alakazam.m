classdef Alakazam < handle
    %
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
            % Constructor
            [this.RootDir,~,~] = fileparts(which('Alakazam'));
            cd(this.RootDir);

            close all
            if exist('D:/TMP/tmpXDF','dir')
                rmdir('D:/TMP/tmpXDF', 's');
            end
            warning('off', 'MATLAB:ui:javacomponent:FunctionToBeRemoved');
            addpath(genpath('Transformations'), 'mlapptools');

            % create tool group
            this.ToolGroup = ToolGroup('Alakazam','AlakazamApp');

            addlistener(this.ToolGroup, 'GroupAction',@(src, event) closeCallback(this, event));
            % create plot (hg)
            this.Figures = gobjects(1,1);
            % create tab group (new mcos api)
            tabgroup = BuildTabGroupAlakazam(this);
            % add tab group to toolstrip (via tool group api)
            this.ToolGroup.addTabGroup(tabgroup);
            % select current tab (via tool group api)
            this.ToolGroup.SelectedTab = 'tabHome';
            % render app
            this.ToolGroup.setPosition(100,100,1080,720);
            this.ToolGroup.open;

            % left-to-right document layout
            MD = com.mathworks.mlservices.MatlabDesktopServices.getDesktop; %#ok<JAPIMATHWORKS>
            MD.setDocumentArrangement(this.ToolGroup.Name, MD.TILED, java.awt.Dimension(1,1));

            this.Workspace = WorkSpace(this);
            this.Workspace.open();
            % after this, the workspace Panel holds the DataTree
            this.ToolGroup.setDataBrowser(this.Workspace.Panel);
            assignin('base', 'AlakazamInst', this)
        end

        function deleteNode(this)
            disp("delete")
            set(this.treeMenu, 'Visible','off');
        end
        function expandSingle(this, src,event,f)
            node = f.CurrentObject;
            expand(node)
        end

        function expandAll(this, src,event,t)
            expand(t)
        end
        function delete(this)
            % Destructor
            if ~isempty(this.ToolGroup) && isvalid(this.ToolGroup)
                delete(this.ToolGroup);
            end
            delete(this.Figures);
        end

        function dropTargetCallback(src,data)
            disp('Dropped');
        end

        function ActionOnTransformation(this, ~, ~, userdata)
            % this function is the callback for all transformations.
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
            % this = Alakazam, tree = Alakazam.Workspace.Tree, args =
            % TreeNode that was edited: Name field has changed
            this.Workspace.EEG.id = args.Nodes.Name;
            EEG = this.Workspace.EEG;
            save(this.Workspace.EEG.File, 'EEG');

        end
        function TreeDropNode(this, tree, args)
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
                        size(NewEEGStruct.EEG.data) == size(OldEEGStruct.EEG.data) %#ok<AND2> 
                    
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
            EEGStruct = load(args.Nodes.UserData, 'EEG');
            this.Workspace.EEG  = EEGStruct.EEG;
            plotCurrent(this);
        end

        function closeCallback(this, event)
            % Callback for the close event of the tool group
            ET = event.EventData.EventType;
            if strcmp(ET, 'CLOSED')
                delete(this);
            end
        end

    end
end

