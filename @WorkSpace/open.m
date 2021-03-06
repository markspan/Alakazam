function open(this,~,~)
    allChildren = this.Tree.Root.Children;
    allChildren.delete;
    fileList = dir (strcat(this.RawDirectory, '*.vhdr'));
    for file = 1:length(fileList)
        this.loadBVAFile(this, fileList(file).name)
    end
    fileList = dir (strcat(this.RawDirectory, '*.bdf'));
    for file = 1:length(fileList)
        this.loadBDFFile(this, fileList(file).name)
    end
    fileList = dir (strcat(this.RawDirectory, '*.BLE'));
    for file = 1:length(fileList)
        %this.loadCortriumFile(this, fileList(file).name)
    end
end