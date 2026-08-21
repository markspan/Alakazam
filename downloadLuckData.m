function downloadLuckData(fileIds, targetDir)
%DOWNLOADLUCKDATA  Download and extract the Luck-textbook example data
%   into Data/Luck. Anonymous: no Google account, no API key, no Google
%   Cloud project of any kind -- the data is shared as one or more zip
%   files (see "Preparing the shared files" below), and downloading an
%   already-known public file has never needed a key at all (Google only
%   gates the Drive API itself behind a key, for LISTING a folder's
%   contents -- fetching a file you already have the ID for is a plain
%   anonymous request, the same one Drive's own "Download" button makes).
%   Safe: this only ever performs a read-only GET against each file's own
%   content URL, then extracts it -- it cannot modify or delete anything
%   on Drive.
%
%   downloadLuckData() downloads FILEIDS (see below) into
%   <repo root>/Data/Luck, extracting every zip into the same folder.
%
%   downloadLuckData(fileIds, targetDir) overrides either. FILEIDS is a
%   cellstr/string array when there is more than one zip (the data was
%   too large for Drive to zip as a single file) -- a single char/string
%   is also accepted for the one-zip case.
%
%   If Data/Luck already has files in it, this is a no-op (nothing is
%   re-downloaded); delete the folder first (or pass a different
%   TARGETDIR) to force a fresh fetch.
%
%   Handles Google Drive's "can't scan this file for viruses" warning
%   page automatically -- served instead of the real content for files
%   over roughly 100 MB, which each of these zips likely is: a first
%   attempt that comes back looking like an HTML page rather than real
%   zip data is retried with the confirmation token that warning page
%   itself supplies.
%
%   ---------------------------------------------------------------------
%   Preparing the shared files (a one-time step for whoever is
%   distributing the data; no Google Cloud project, API key, or billing
%   of any kind is needed):
%
%   1. In Drive's own web UI, select the Luck folder's contents and
%      choose Download -- Drive zips it for you (splitting into several
%      zip files itself, if the selection is too large for one), using
%      your own logged-in session, not a script, so no key is needed for
%      this step either.
%   2. Upload each .zip file back to Drive.
%   3. For each one: right-click it -> Share -> "Anyone with the link" ->
%      Viewer.
%   4. For each one: right-click it -> Get link. The URL looks like
%      https://drive.google.com/file/d/THIS_PART/view?usp=sharing --
%      THIS_PART is the file ID. Put every one of them in FILEIDS below
%      (or pass them as the first argument).
%
%   See also: STARTALAKAZAM.
    if nargin < 1 || isempty(fileIds)
        fileIds = {'1OcHmGrOKdkhwyRNwd3hZ5NAogvY44c_i', '1gtRQf7SKtLhAtUBUqAkHxrE1Yqkr1Tp-'};
    end
    fileIds = cellstr(fileIds); % accepts a single char/string too, not just a cellstr/string array
    if any(startsWith(fileIds, 'PASTE_THE_'))
        throw(MException('Alakazam:downloadLuckData', [ ...
            'No file ID(s) set. See this function''s own header comment (help downloadLuckData) ' ...
            'for how to share the data as one or more zip files and find their IDs, then either ' ...
            'edit the default at the top of this file or call downloadLuckData({''ID_1'', ''ID_2'', ...}).']));
    end

    here = fileparts(mfilename('fullpath'));
    if nargin < 2 || isempty(targetDir)
        targetDir = fullfile(here, 'Data', 'Luck');
    end

    if exist(targetDir, 'dir')
        listing = dir(targetDir);
        hasContent = any(~ismember({listing.name}, {'.', '..'}));
        if hasContent
            fprintf('%s already has files in it -- nothing to do.\n', targetDir);
            fprintf('(delete it, or pass a different target directory, to force a fresh download)\n');
            return;
        end
    else
        mkdir(targetDir);
    end

    for i = 1:numel(fileIds)
        fprintf('Downloading Luck example data (%d of %d, this may take a while)...\n', i, numel(fileIds));
        zipFile = [tempname '.zip']; % tempname() with no argument resolves to the OS temp folder
        downloadFile(fileIds{i}, zipFile);

        fprintf('Extracting into %s ...\n', targetDir);
        unzip(zipFile, targetDir);
        deleteIfExists(zipFile);
    end

    fprintf('Done.\n');
end

function deleteIfExists(file)
    if exist(file, 'file')
        delete(file);
    end
end

function downloadFile(fileId, localFile)
%DOWNLOADFILE  Stream FILEID's content straight to disk via Drive's plain
%   anonymous download URL (no API key). If what comes back is Drive's
%   "can't scan this file for viruses" interstitial (an HTML page, served
%   instead of the real content for files over roughly 100 MB) rather
%   than the file itself, retry once against the bypass form that page
%   itself embeds.
    url = sprintf('https://drive.google.com/uc?export=download&id=%s', fileId);
    websave(localFile, url);

    if looksLikeConfirmPage(localFile)
        [action, params] = parseConfirmForm(localFile);
        delete(localFile);
        if isempty(action)
            % Fallback for older/simpler warning pages that skip the uuid field.
            action = 'https://drive.usercontent.google.com/download';
            params = {'id', fileId, 'export', 'download', 'confirm', 't'};
        end
        websave(localFile, action, params{:});
        if looksLikeConfirmPage(localFile)
            throw(MException('Alakazam:downloadLuckData', ...
                ['Drive kept returning its virus-scan warning page instead of the file content ' ...
                 'for id %s. Double-check that file is actually shared as "Anyone with the link".'], ...
                fileId));
        end
    end
end

function tf = looksLikeConfirmPage(localFile)
%LOOKSLIKECONFIRMPAGE  True if LOCALFILE is (almost certainly) Drive's
%   HTML warning page rather than the real download. The warning page is
%   only a few KB and starts with ordinary HTML markup; a real zip file's
%   own magic bytes ("PK..") never do, so sniffing the first few thousand
%   characters is a safe, cheap signal regardless of how large the real
%   file is expected to be -- this needs no known expected size for any
%   individual zip, useful now that there is more than one and they need
%   not be the same size.
    tf = false;
    info = dir(localFile);
    if isempty(info) || info(1).bytes > 200000 % the warning page itself is always small
        return;
    end
    fid = fopen(localFile, 'r');
    if fid < 0
        return;
    end
    head = fread(fid, 4000, '*char')';
    fclose(fid);
    tf = ~isempty(regexpi(head, '<html|Google Drive can''t scan', 'once'));
end

function [action, params] = parseConfirmForm(localFile)
%PARSECONFIRMFORM  Extract the bypass form's target URL and hidden fields
%   from Drive's virus-scan warning page, rather than guessing at a URL
%   scheme -- the real page redirects to a different host
%   (drive.usercontent.google.com) and requires a per-request "uuid"
%   field alongside the fixed "id"/"export"/"confirm" ones, none of which
%   a hand-built retry URL can know in advance.
    fid = fopen(localFile, 'r');
    text = fread(fid, Inf, '*char')';
    fclose(fid);

    action = '';
    params = {};

    formTok = regexp(text, '<form[^>]*action="([^"]+)"', 'tokens', 'once');
    if isempty(formTok)
        return;
    end
    action = formTok{1};

    inputToks = regexp(text, '<input type="hidden" name="([^"]+)" value="([^"]*)"', 'tokens');
    params = cell(1, 2 * numel(inputToks));
    for i = 1:numel(inputToks)
        params{2*i - 1} = inputToks{i}{1};
        params{2*i} = inputToks{i}{2};
    end
end
