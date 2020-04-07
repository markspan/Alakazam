classdef Alakazam < handle
    % Brainvision analyser like program created in MATLAB
    %
    % Based On:
    % "matlab.ui.internal.desktop.showcaseMPCDesigner()" Author(s): R. Chen
    % Copyright 2015 The MathWorks, Inc.
    % C:\Program Files\MatLAB\R2018b\toolbox\matlab\toolstrip\+matlab\+ui\+internal\+desktop
    
    % Author(s): M.Span, University of Groningen,
    % dept. Experimental Psychology
    
    properties (Transient = false)
        ToolGroup
        Figures
        FDropHandler
        Workspace
        originalLnF
        asmInfo
        SplashScreen
    end
    
    methods
        
        function this = Alakazam(varargin)
            %[flist,plist] = matlab.codetools.requiredFilesAndProducts('Alakazam.m'); [flist'; {plist.Name}']
            try
                this.asmInfo = NET.addAssembly('.\AlakazamGui.dll');
            catch e
                e.message;
            end
            
            this.SplashScreen = AlakazamGui.SplashForm;
            Show(this.SplashScreen)
           
            
            this.SplashScreen.AddTitle('Alakazam', 32, 250,1)
            this.SplashScreen.AddText('Initializing All Transformations')
            Activate(this.SplashScreen)
            
            % Al
            addpath(genpath('Transformations'), 'mlapptools', genpath('../Alakazam/functions'));
            mlapptools.toggleWarnings('off');
            import javax.swing.UIManager;
            this.originalLnF = 'com.sun.java.swing.plaf.windows.WindowsLookAndFeel' ;
            %javax.swing.UIManager.getLookAndFeel;
            newLnF = 'com.jgoodies.looks.plastic.Plastic3DLookAndFeel';   %string
            javax.swing.UIManager.setLookAndFeel(newLnF);
            
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
            MD = com.mathworks.mlservices.MatlabDesktopServices.getDesktop;
            MD.setDocumentArrangement(this.ToolGroup.Name, MD.TILED, java.awt.Dimension(1,1));
            
            this.Workspace = WorkSpace(this);
            this.Workspace.open();
            % after this, the workspace Panel holds the DataTree
            this.ToolGroup.setDataBrowser(this.Workspace.Panel);
            this.FDropHandler = FiguresDropTargetHandler;
            % add callback to drop event in figure 1
            % this.FDropHandler = FiguresDropTargetHandler(this.ToolGroup);
            % addlistener(this.FDropHandler, 'VariablesBeingDropped', @(x,y) disp(y.Variables));
            % store java toolgroup so that app will stay in memory
            internal.setJavaCustomData(this.ToolGroup.Peer,this);
            this.SplashScreen.AddText('Ready.')
            pause(1);
            this.SplashScreen.Close();
            
        end
        
        function delete(this)
            if ~isempty(this.ToolGroup) && isvalid(this.ToolGroup)
                delete(this.ToolGroup);
            end
            javax.swing.UIManager.setLookAndFeel(this.originalLnF);
            delete(this.Figures);
        end
        
        function dropTargetCallback(src,data)
            disp('Dropped');
        end
        
        function ActionOnTransformation(this, ~, ~, userdata)
            % this function is the callback for all transformations.
            try
                callfnction = char(userdata);
                id = callfnction(1:end-2);
                functionCall= ['EEG=' id '(x.EEG);'];
                
                [a.EEG, used_params] = feval(id, this.Workspace.EEG);
                a.EEG.Call = functionCall;
                if (isstruct(used_params))
                    a.EEG.params = used_params;
                else
                    
                    a.EEG.params = struct( 'Param', used_params);
                end
                
                CurrentNode = this.Workspace.Tree.SelectedNodes.Name;
                % Build new FileID (Name) based on the name of the current
                % node, the used transformationID and a timestamp.
                Key = [id datestr(datetime('now'), 'yymmddHHMMSS')];
                a.EEG.File = strcat(this.Workspace.CacheDirectory, char(CurrentNode), Key, '.mat');
                a.EEG.id =  [char(CurrentNode) ' - ' id];
                %newNode = javaObjectEDT('AlakazamHelpers.EEGLABTreeNode', a.EEG.id, a.EEG.File);
                NewNode=uiextras.jTree.TreeNode('Name',a.EEG.id,'Parent',this.Workspace.Tree.SelectedNodes, 'UserData',a.EEG.File);
                if strcmpi(a.EEG.DataType, 'TIMEDOMAIN')
                    setIcon(NewNode,this.Workspace.TimeSeriesIcon);
                elseif strcmpi(a.EEG.DataType, 'FREQUENCYDOMAIN')
                    setIcon(NewNode,this.Workspace.FrequenciesIcon);
                end
                NewNode.Parent.expand();
                this.Workspace.Tree.SelectedNodes = NewNode;
                % unfold the tree.
                %this.Workspace.cbTree.expandPath(handle(this.Workspace.cbTree),tmp);
                a.EEG.data = a.EEG.data;
                EEG=a.EEG;
                save(a.EEG.File, 'EEG');
                this.Workspace.EEG=EEG;
                plotCurrent(this);
            catch ME
                warndlg(ME.message, 'Error in transformation');
                pause(1);
            end
        end
        
        function plotCurrent(this)
            f = findobj('Type', 'Figure','Tag', this.Workspace.EEG.File);
            if ~isempty(f)
                % then just show it
                this.ToolGroup.showClient(get(f, 'Name'));
            else
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
                    'Toolbar', 'figure',...
                    'DockControls','off', ...
                    'Visible','off' ...
                    );
                
                %                 dnd = handle(java.awt.dnd.DropTarget(), 'CallbackProperties');
                %                 jFrame = get(handle(this.Figures(end)), 'JavaFrame');
                %                 jAxis = jFrame.getAxisComponent;
                %                 dnd.DropCallback = @(x,y) disp(y.Variables);
                %                 jAxis.setDropTarget(dnd);
                this.FDropHandler.registerInterest(this.Figures(end));
                
                
                %this.FDropHandler.registerInterest(this.Figures(end));
                % TODO: Set Drop callback functions
                
                if strcmp(this.Workspace.EEG.DataFormat, 'EPOCHED')
                   % warndlg("Plotting Epochs not yet implemented", "Info")
 %%
                     tempEEG = this.Workspace.EEG;
                     tempEEG.data = squeeze(tempEEG.data(:,:,1));
                     if strcmp(this.Workspace.EEG.DataType, 'TIMEDOMAIN')
                        if (this.Workspace.EEG.nbchan > 1)
                            % Multichannel plot epoched
                            Tools.plotEEG2(this.Workspace.EEG.times/1000, tempEEG, 'ShowInformationList','none','ShowAxisTicks','on','YLimMode', 'fixed', 'AutoStackSignals', {this.Workspace.EEG.chanlocs.labels}, 'Parent',  this.Figures(end));
                        else
                            %Singlechannel plot epoched
                            Tools.plotEEG2(this.Workspace.EEG.times/1000,tempEEG, 'ShowInformationList','none','ShowAxisTicks','on','YLimMode', 'fixed','Parent',  this.Figures(end));
                        end
                     else
                        % Fourier Plot (Multichannel and singlechannel) epoched
                        Tools.plotFourier(tempEEG, this.Figures(end));
                    end
                    this.ToolGroup.addFigure(this.Figures(end));
                    this.Figures(end).Visible = 'on';
 %%
                else
                    if strcmp(this.Workspace.EEG.DataType, 'TIMEDOMAIN')
                        if (this.Workspace.EEG.nbchan > 1)
                            % Multichannel plot
                            Tools.plotEEG2(this.Workspace.EEG.times/1000, this.Workspace.EEG, 'ShowInformationList','none','ShowAxisTicks','on','YLimMode', 'fixed', 'AutoStackSignals', {this.Workspace.EEG.chanlocs.labels}, 'Parent',  this.Figures(end));
                        else
                            % Singlechannel Plot
                            Tools.plotEEG2(this.Workspace.EEG.times/1000,this.Workspace.EEG, 'ShowInformationList','none','ShowAxisTicks','on','YLimMode', 'fixed','Parent',  this.Figures(end));
                        end
                    else
                        %Fourier Plot (Multichannel and singlechannel)
                        Tools.plotFourier(this.Workspace.EEG, this.Figures(end));
                    end
                    this.ToolGroup.addFigure(this.Figures(end));
                    this.Figures(end).Visible = 'on';
                end
            end
        end
        
        function TreeDropNode(this, Tree, args)
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
            % this should be done recursively......
            
            x = load(NewData, 'EEG');
            Old = load(OldData, 'EEG');
            
            idx1 = strfind(Old.EEG.Call, '=');
            idx2 = strfind(Old.EEG.Call, '(');
            id = Old.EEG.Call(idx1+1:idx2-1);
            
            [a.EEG, ~] = feval(id, x.EEG, Old.EEG.params);
            
            CurrentNode = x.EEG.id;
            Key = [id datestr(datetime('now'), 'yymmddHHMMSS')];
            a.EEG.File = strcat(this.Workspace.CacheDirectory, char(CurrentNode), Key, '.mat');
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
        end
        
        function MouseClicked(this,Tree,args)
            if (args.Button == 1) % left Button
                if (args.Clicks == 2) % double click left button
                    % One way or the other: load and display the data.
                    id = Tree.SelectedNodes.Name;
                    matfilename = Tree.SelectedNodes.UserData;
                    if exist(matfilename, 'file') == 2
                        % if the file already exists:
                        a=load(matfilename, 'EEG');
                        a.EEG.id = string(id);
                        this.Workspace.EEG = a.EEG;
                    end
                    plotCurrent(this);
                end
            end
            if (args.Button == 3) % right Button
                % show Tearoff Menu!
                disp('Tear!')
            end
        end
        
        
        function SelectionChanged(this,Tree,args) %#ok<*INUSD>
            disp('Alakazam::SelectionChanged Unimplemented')
        end
        
        function closeCallback(this, event)
            ET = event.EventData.EventType;
            if strcmp(ET, 'CLOSED')
                delete(this);
            end
        end
        
    end
end

