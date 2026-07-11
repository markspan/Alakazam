function rawclear(this,~,~)
    answer = questdlg('Are you sure you want to delete all your work?', ...
    	'Clear Workspace?', ...
        'Yes, delete!','Sorry, what? No!','Sorry, what? No!');
    if strcmp(answer, 'Yes, delete!')
        % gcf ignores this app's uifigure (it only tracks classic figures),
        % so it used to silently CREATE a new blank one here -- exactly the
        % stray figure window users saw, which then sat on top of/stole
        % focus from MainFigure and made the app look hung. Use the app's
        % own window instead, restored via onCleanup so the watch cursor
        % can't get stuck if rmdir/mkdir/open throws partway through.
        fig = this.Parent.MainFigure;
        fig.Pointer = 'watch';
        restorePointer = onCleanup(@() set(fig, 'Pointer', 'arrow'));
        rmdir(this.CacheDirectory, 's');
        mkdir(this.CacheDirectory);
        open(this);
    end
end
