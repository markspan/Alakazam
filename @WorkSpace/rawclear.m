function rawclear(this,~,~)
    answer = questdlg('Are you sure you want to delete all your work?', ...
    	'Clear Workspace?', ...
        'Yes, delete!','Sorry, what? No!','Sorry, what? No!');
    if strcmp(answer, 'Yes, delete!')
        set(gcf,'Pointer','watch');
        rmdir(this.CacheDirectory, 's');
        mkdir(this.CacheDirectory);
        open(this);
        set(gcf,'Pointer','arrow');
    end
end
