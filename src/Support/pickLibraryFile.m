function [file, folder] = pickLibraryFile(kind, filter, title)
%PICKLIBRARYFILE  Choose a file to load, starting in the library.
%   [FILE, FOLDER] = pickLibraryFile(KIND, FILTER, TITLE) shows uigetfile
%   with FILTER and TITLE. The first time in a session it opens in the
%   library's folder for KIND (see libraryFolder); after that, in whichever
%   folder a file of that kind was last loaded from. FILE is 0 when the user
%   cancels, as uigetfile returns it.
%
%   ONE REMEMBERED FOLDER PER KIND. uiextras.uigetfile2 remembers a single
%   folder for every kind of file, shared with EEGLAB itself, so a template
%   loaded from the library would send the next measurement-file dialog
%   there too, and a recording opened in EEGLAB would send the template
%   dialog to the recordings. The memory lasts for the session only: a new
%   session starts in the library again, which is where the files a user has
%   not written yet are.
%
%   See also LIBRARYFOLDER.
    persistent lastFolder
    if ~isstruct(lastFolder)
        lastFolder = struct();
    end

    start = libraryFolder(kind);
    if isfield(lastFolder, kind) && isfolder(lastFolder.(kind))
        start = lastFolder.(kind);
    elseif ~isfolder(start)
        start = pwd;
    end

    % A folder with a trailing separator makes uigetfile open in it without
    % proposing a file name.
    [file, folder] = uigetfile(filter, title, [start filesep]);
    if ~isequal(file, 0)
        lastFolder.(kind) = folder;
    end
end
