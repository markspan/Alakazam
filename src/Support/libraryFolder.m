function folder = libraryFolder(kind)
%LIBRARYFOLDER  Where the library's files of one kind live.
%   FOLDER = libraryFolder(KIND) is library/KIND in the repository root, for
%   KIND 'templates', 'binscripts' or 'measures'. FOLDER = libraryFolder() is
%   library/ itself. A release package has the same layout, so the answer
%   is the same there.
%
%   Found from this file's own location, not from the current folder, which
%   the application and the tests both change: this file is in src/Support/,
%   two levels below the root.
%
%   See also PICKLIBRARYFILE.
    root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    folder = fullfile(root, 'library');
    if nargin > 0
        folder = fullfile(folder, char(kind));
    end
end
