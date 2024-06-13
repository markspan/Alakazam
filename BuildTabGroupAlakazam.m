function tabgroup = BuildTabGroupAlakazam(app)
    % Build the TabGroup for the Alakazam app.
    %
    % This function constructs a TabGroup object for the Alakazam application.
    % It initializes two tabs: 'Alakazam' and 'Tools', each containing various UI elements.
    % The function utilizes helper functions to create the workspace and transformations sections within the tabs.
    %
    % Args:
    %     app: The main application object.
    %
    % Returns:
    %     tabgroup: A TabGroup object containing the initialized tabs.
    %
    % Author(s): Mark Span; Rong Chen
    % Copyright 2015 University of Groningen, MMSpan, GPL2

    % Import necessary MATLAB UI toolstrip components
    import matlab.ui.internal.toolstrip.*
    
    % Create the main TabGroup object
    tabgroup = TabGroup();
    
    % Create the 'Alakazam' tab
    tabHome = Tab('Alakazam');
    tabHome.Tag = 'tabHome';
    createWorkSpace(tabHome, app); % Populate the 'Alakazam' tab with workspace components
    
    % Create the 'Tools' tab
    tabTool = Tab('Tools');
    tabTool.Tag = 'tabTool';
    createTransformation(tabTool, app); % Populate the 'Tools' tab with transformation components

    % Add the tabs to the TabGroup
    tabgroup.add(tabHome);
    tabgroup.add(tabTool);
end

function createWorkSpace(tab, app)
    % Create and populate the WorkSpace section within a given tab.
    %
    % Args:
    %     tab: The tab in which to create the WorkSpace section.
    %     app: The main application object.

    import matlab.ui.internal.toolstrip.*
    
    % Define the path to the icons used in the workspace buttons
    iconpath = fullfile(matlabroot, 'toolbox', 'matlab', 'toolstrip', 'web', 'mpcdesigner_icons', filesep);
    
    % Create the WorkSpace section
    WorkSpace = Section('WorkSpace');
    WorkSpace.Tag = 'WorkSpaceSection';
    
    % Create columns for layout within the WorkSpace section
    column1 = Column();
    column2 = Column();
    
    % Create and configure the 'Open WorkSpace' button
    OpenWorkSpaceIcon = Icon([iconpath 'OpenSession.png']);
    OpenWorkSpaceButton = Button('Open WorkSpace', OpenWorkSpaceIcon);
    OpenWorkSpaceButton.Tag = 'OpenWorkSpaceButton';
    OpenWorkSpaceButton.Description = 'Open a Workspace';
    OpenWorkSpaceButton.ButtonPushedFcn = @(x, y) app.Workspace.load(); % Set the callback function
    
    % Create and configure the 'Save WorkSpace' button
    SaveWorkSpaceIcon = Icon([iconpath 'SaveSession.png']);
    SaveWorkSpaceButton = Button('Save WorkSpace', SaveWorkSpaceIcon);
    SaveWorkSpaceButton.Tag = 'SaveWorkSpaceButton';
    SaveWorkSpaceButton.Description = 'Save current WorkSpace into a session for future use';
    SaveWorkSpaceButton.ButtonPushedFcn = @(x, y) app.Workspace.save(); % Set the callback function
    
    % Create and configure the 'Edit WorkSpace' button
    EditWorkSpaceIcon = Icon([iconpath 'SaveSession.png']);
    EditWorkSpaceButton = Button('Edit WorkSpace', EditWorkSpaceIcon);
    EditWorkSpaceButton.Tag = 'EditWorkSpaceButton';
    EditWorkSpaceButton.Description = 'Edit current WorkSpace';
    EditWorkSpaceButton.ButtonPushedFcn = @(x, y) app.Workspace.edit(); % Set the callback function
    
    % Create and configure the 'Clear WorkSpace' button
    ClearWorkSpaceIcon = Icon([iconpath, '..', filesep, 'image', filesep, 'control_app_24.png']);
    ClearWorkSpaceButton = Button('Clear WorkSpace', ClearWorkSpaceIcon);
    ClearWorkSpaceButton.Tag = 'ClearWorkSpaceButton';
    ClearWorkSpaceButton.Description = 'Rawload current WorkSpace';
    ClearWorkSpaceButton.ButtonPushedFcn = @(x, y) app.Workspace.rawclear(); % Set the callback function
    
    % Add the WorkSpace section to the tab
    add(tab, WorkSpace);
    
    % Add columns to the WorkSpace section
    add(WorkSpace, column1);
    add(WorkSpace, column2);
    
    % Add buttons to the columns
    add(column1, OpenWorkSpaceButton);
    add(column1, SaveWorkSpaceButton);
    add(column2, EditWorkSpaceButton);
    add(column2, ClearWorkSpaceButton);
end

function info = getIndividualTransInfos(TName)
    % Retrieve individual transformation information from a JSON file.
    %
    % Args:
    %     TName: The name of the transformation.
    %
    % Returns:
    %     info: A structure containing the transformation information.

    % Convert TName to a character array
    TName = char(TName);
    
    % Locate and read the JSON file containing the transformation information
    json = dir(fullfile('Transformations', TName, [TName '.json']));
    json = fullfile(json.folder, json.name);
    jsonfile = fopen(json);
    jsonraw = fread(jsonfile, inf);
    fclose(jsonfile);
    
    % Decode the JSON file content
    info = jsondecode(char(jsonraw'));
end

function transInfo = getTransInfos()
    % Retrieve information for all transformations.
    %
    % Returns:
    %     transInfo: A structure array containing information for all transformations.

    % List directories within the 'Transformations' folder
    fL = dir(fullfile('Transformations', '.'));
    dirs = find([fL.isdir]);

    % Filter out unwanted directory names
    tF = {fL(dirs).name};
    tF = tF(~ismember(tF, {'.', '..', '+TransTools'}));

    % Import necessary MATLAB UI toolstrip components
    import matlab.ui.internal.toolstrip.*
    
    % Initialize an empty cell array to store transformation information
    transInfo = {};
    
    % Retrieve and store information for each transformation
    for Trans = tF
        transInfo{end+1} = getIndividualTransInfos(Trans{1}); %#ok<AGROW>
    end
    
    % Convert the cell array to a structure array
    transInfo = [transInfo{:}];
end

function createTransformation(tab, app)
    % Create and populate the Transformation section within a given tab.
    %
    % Args:
    %     tab: The tab in which to create the Transformation section.
    %     app: The main application object.

    import matlab.ui.internal.toolstrip.*
    
    % Retrieve transformation information
    transInfo = getTransInfos();
    
    % Identify unique sections within the transformations
    uniqueSections = unique({transInfo.Section});

    % Loop through each unique section
    for tS = uniqueSections
        % Create a new section in the tab for the current section
        section = tab.addSection(char(tS));
        column = section.addColumn();
        
        % Retrieve transformations for the current section
        SectionTransForms = transInfo(strcmp({transInfo.Section}, tS));
        uniqueCats = unique({SectionTransForms.Category});
        popup = GalleryPopup('ShowSelection', false);
        
        % Loop through each unique category within the current section
        for tC = uniqueCats
            SectionCatTransForms = SectionTransForms(strcmp({SectionTransForms.Category}, tC));
            cat = GalleryCategory(char(tC));
            popup.add(cat);
            
            % Retrieve unique transformation names within the current category
            T = unique({SectionCatTransForms.Name});
            
            % Loop through each transformation name
            for tT = T
                % Retrieve the transformation information for the current transformation name
                iTransForm = SectionCatTransForms(strcmp({SectionCatTransForms.Name}, tT));
                
                % Create a gallery item for the current transformation
                item = GalleryItem(iTransForm.Name, Icon(fullfile('Transformations', char(tT), iTransForm.Icon)));
                item.Description = iTransForm.Description;
                item.ItemPushedFcn = @(x, y, userData) app.ActionOnTransformation(x, y, iTransForm.Entry);
                cat.add(item);
            end
        end
        
        % Create a gallery and add it to the column
        gallery = Gallery(popup, 'MinColumnCount', 2, 'MaxColumnCount', 2);
        column.add(gallery);
    end
end
