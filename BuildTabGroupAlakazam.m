function tabgroup = BuildTabGroupAlakazam(app)
    % Build the TabGroup for the Alakazam app.
    % Read the Transformations Pages to build this Group.
    % Based on the TabGroup for the MPC Designer app showcase.
    % Author(s): Rong Chen
    % Copyright 2015 The MathWorks, Inc.

    import matlab.ui.internal.toolstrip.*
    % tab group
    tabgroup = TabGroup();
    % Alakazam tab
    tabHome = Tab('Alakazam');
    tabHome.Tag = 'tabHome';
    createWorkSpace(tabHome, app);
    % Transformations tab
    tabTool = Tab('Tools');
    tabTool.Tag = 'tabTool';
    createTransformation(tabTool, app);

    tabgroup.add(tabHome);
    tabgroup.add(tabTool);
end

function createWorkSpace(tab, app)
    import matlab.ui.internal.toolstrip.*
    iconpath = [fullfile(matlabroot,'toolbox','matlab','toolstrip','web','mpcdesigner_icons') filesep];
    % create section
    WorkSpace = Section('WorkSpace');
    WorkSpace.Tag = 'WorkSpaceSection';
    % create columns
    column1 = Column();
    column2 = Column();
    % add open session push button
    OpenWorkSpaceIcon = Icon([iconpath 'OpenSession.png']);
    OpenWorkSpaceButton = Button('Open WorkSpace',OpenWorkSpaceIcon);
    OpenWorkSpaceButton.Tag = 'OpenWorkSpaceButton';
    OpenWorkSpaceButton.Description = 'Open a Workspace';
    % add save session push button
    SaveWorkSpaceIcon = Icon([iconpath 'SaveSession.png']);
    SaveWorkSpaceButton = Button('Save WorkSpace',SaveWorkSpaceIcon);
    SaveWorkSpaceButton.Tag = 'SaveWorkSpaceButton';
    SaveWorkSpaceButton.Description = 'Save current WorkSpace into a session for future use';
    % add edit session push button
    EditWorkSpaceIcon = Icon([iconpath 'SaveSession.png']);
    EditWorkSpaceButton = Button('Edit WorkSpace',EditWorkSpaceIcon);
    EditWorkSpaceButton.Tag = 'EditWorkSpaceButton';
    EditWorkSpaceButton.Description = 'Edit current WorkSpace';
    % add Clear session push button
    ClearWorkSpaceIcon = Icon([iconpath,'..',filesep,'image',filesep,'control_app_24.png']);
    ClearWorkSpaceButton = Button('Clear WorkSpace',ClearWorkSpaceIcon);
    ClearWorkSpaceButton.Tag = 'ClearWorkSpaceButton';
    ClearWorkSpaceButton.Description = 'Rawload current WorkSpace';
    
    % assemble
    add(tab,WorkSpace);
    add(WorkSpace, column1);
    add(WorkSpace, column2);
    add(column1,OpenWorkSpaceButton);
    add(column1,SaveWorkSpaceButton);
    add(column2,EditWorkSpaceButton);
    add(column2,ClearWorkSpaceButton);
    % add callback

    OpenWorkSpaceButton.ButtonPushedFcn = @(x,y) app.Workspace.load();
    SaveWorkSpaceButton.ButtonPushedFcn = @(x,y) app.Workspace.save();
    EditWorkSpaceButton.ButtonPushedFcn = @(x,y) app.Workspace.edit();
    ClearWorkSpaceButton.ButtonPushedFcn = @(x,y) app.Workspace.rawclear();
end

function info = getIndividualTransInfos(TName)
    TName = char(TName);
    json = dir(strcat(['Transformations\' TName '\'], [TName '.json']));
    json = [json.folder '\' json.name];
    jsonfile = fopen(json);
    jsonraw = fread(jsonfile, inf);
    fclose(jsonfile);
    info = jsondecode(char(jsonraw'));
end

function transInfo = getTransInfos()
    fL = dir (strcat('Transformations\', '.'));
    dirs = find(vertcat(fL.isdir));

    tF = {fL(dirs).name}; %#ok<*FNDSB>
    tF = tF(~strcmp(tF, '.'));
    tF = tF(~strcmp(tF, '..'));
    tF = tF(~strcmp(tF, '+TransTools'));

    import matlab.ui.internal.toolstrip.*
    transInfo = {};
    for Trans = tF
        transInfo{end+1} = getIndividualTransInfos(Trans); %#ok<AGROW>
    end
    transInfo=[transInfo{:}];
end

function createTransformation(tab, app)
    import matlab.ui.internal.toolstrip.*
    % Inline gallery
    transInfo = getTransInfos();
    uniqueSections = unique({transInfo.Section});

    for tS=uniqueSections
        section = tab.addSection(char(tS));
        column = section.addColumn();
        SectionTransForms = transInfo(strcmp({transInfo.Section}, tS ));
        uniqueCats = unique({SectionTransForms.Category});
        popup = GalleryPopup('ShowSelection',false);
        for tC=uniqueCats
            SectionCatTransForms = SectionTransForms(strcmp({SectionTransForms.Category}, tC ));
            cat = GalleryCategory(char(tC));
            popup.add(cat);
            T = unique({SectionCatTransForms.Name});
            for tT=T
                %app.SplashScreen.AddText("Tr: " + {SectionCatTransForms.Name})
                iTransForm = SectionCatTransForms(strcmp({SectionCatTransForms.Name}, tT ));
                item = GalleryItem(iTransForm.Name, Icon(['Transformations\' char(tT) '\' iTransForm.Icon]));
                item.Description = iTransForm.Description;
                item.ItemPushedFcn = @(x,y, userData) app.ActionOnTransformation(x,y, iTransForm.Entry);
                cat.add(item);
            end
        end
        gallery = Gallery(popup, 'MinColumnCount',2, 'MaxColumnCount',2);
        column.add(gallery);
    end
end
