classdef Alakazam < handle
    %
    % Based On:
    % "matlab.ui.internal.desktop.showcaseMPCDesigner()" Author(s): R. Chen
    % Copyright 2015 The MathWorks, Inc.
    % C:\Program Files\MatLAB\R2018b\toolbox\matlab\toolstrip\+matlab\+ui\+internal\+desktop

    % Author(s): M.Span, University of Groningen,
    % dept. Experimental Psychology

    properties (Transient = true)
        ToolGroup
        Figures
        Workspace
    end

    methods

        function this = Alakazam(varargin)
            addpath(pwd);
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

        function delete(this)
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

                Key = [id datestr(datetime('now'), 'yymmddHHMMSS')];
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
                'Renderer', 'painters' , ...
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
            set(this.Figures(end), 'UserData', hEEG);
            if strcmpi(this.Workspace.EEG.DataFormat, 'EPOCHED')
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

        function TreeDropNode(this, ~, args)
            % Called when a Treenode is Dropped on another Treenode.
            % I prefer a switch of "copy" and "move" here.
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
                        this.Evaluate(args.Target.UserData, args.Source.UserData, args.Target);

                        %expand(args.Target)
                        %expand(args.Source)
                        %expand(NewSourceNode)
                    otherwise
                        % Do nothing
                end
            end
        end

        function Evaluate(this, NewData, OldData, NewParentNode)
            endnode = false;

            while endnode == false

                x = load(NewData, 'EEG');
                Old = load(OldData, 'EEG');
                idx1 = strfind(Old.EEG.Call, '=');
                idx2 = strfind(Old.EEG.Call, '(');
                id = Old.EEG.Call(idx1+1:idx2-1);
    
                [a.EEG, ~] = feval(id, x.EEG, Old.EEG.params);
                %disp(["I called: " id])
                %Old.EEG.params
                CurrentNode = x.EEG.id;
                Key = [id datestr(datetime('now'), 'yymmddHHMMSS')];
                [parent.dir, parent.name] = fileparts(x.EEG.File);
                cDir = fullfile(parent.dir,parent.name);
                if ~exist(cDir, 'dir')
                    cDir = fullfile(parent.dir,parent.name);
                    mkdir(cDir);
                end
       
                a.EEG.File = strcat(parent.dir, '\',parent.name, '\' , Key, '.mat');
    
                %a.EEG.File = strcat(this.Workspace.CacheDirectory, char(CurrentNode),'\', Key, '.mat');
                a.EEG.id =  [char(CurrentNode) ' - ' id];
                a.EEG.Call = Old.EEG.Call;
                a.EEG.params = Old.EEG.params;
                % newNode = javaObjectEDT('AlakazamHelpers.EEGLABTreeNode', a.EEG.id, a.EEG.File);
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
        function MouseClicked(this,Tree,args)
            if (args.Button == 1) % left Button
                %if (args.Clicks == 2) % double click left button
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
                %end
            end
            if (args.Button == 3) % right Button
                % show Tearoff Menu!
                disp('Tear!')
            end
        end


        function SelectionChanged(this,Tree,args) %#ok<*INUSD>
            disp('Alakazam::SelectionChanged Unimplemented')
            %             n = randi(5);
            %             newToolBox = javaObjectEDT('javax.swing.JPanel',javaObjectEDT('java.awt.GroupLayout',n,n));
            %             for i = 1:(n*n)
            %                 newToolBox.add(javaObjectEDT('javax.swing.JButton', 'Center'));
            %             end
            %             this.Workspace.ChangeToolBox(newToolBox)
        end

        function closeCallback(this, event)
            ET = event.EventData.EventType;
            if strcmp(ET, 'CLOSED')
                delete(this);
            end
        end

    end
end

