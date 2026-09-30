function loadRawFile(this, name, format)
%LOADRAWFILE  Open a recording in any format rawFormats lists with readers
%   (EDF, BDF, GDF, CNT, MFF, XDF, ...), caching it as the other loaders do.
%
%   loadRawFile(THIS, NAME, FORMAT) reads RawDirectory/NAME with the first
%   of FORMAT's readers that can (readRecording) only when there is no cache
%   yet, or the recording is newer than it; otherwise the cache stands in, as
%   in loadSETFile. A fresh read gets what every recording gets on import:
%   EEGLAB's structure check, the raw file recorded for steps that need
%   files beside it, DataType and a DataFormat derived from the data's shape,
%   times in Alakazam's units (seconds when continuous, milliseconds when
%   epoched), and bins derived from an epoched file's own epoch events.
%
%   A recording that is a folder (EGI's .mff) is dated by the folder itself.
%
%   See also RAWFORMATS, READRECORDING, LOADSETFILE, REGISTERROOTNODE.
    [id, matfilename, rawfilename] = this.resolveCachePaths(name);
    restoreBusy = beginBusy(this.Parent.MainFigure, sprintf("Loading %s...", name)); %#ok<NASGU>

    if exist(matfilename, 'file') == 2 && rawFileDate(rawfilename) <= dir(matfilename).datenum
        EEG = eegProxyFromCacheInfo(readEegCacheInfo(matfilename));
    else
        [EEG, reader] = readRecording(rawfilename, format);
        EEG = eeg_checkset(EEG);
        EEG = recordRawFile(EEG, rawfilename);
        EEG.DataType = 'TIMEDOMAIN';
        EEG.DataFormat = inferDataFormat(EEG);
        if strcmpi(EEG.DataFormat, 'CONTINUOUS')
            EEG.times = ((1:EEG.pnts) - 1) / EEG.srate;
        elseif ~isempty(EEG.times) && max(abs(EEG.times(:))) < 10
            EEG.times = EEG.times * 1000;   % epoched times in seconds, as loadSETFile
        end
        EEG = deriveBinsFromEpochs(EEG);
        EEG.etc.alz.importedWith = struct('format', format.name, 'reader', reader);
        EEG.id = id;
        EEG.File = matfilename;
        saveEegCache(matfilename, EEG);
        if ~isempty(format.note)
            fprintf('%s (%s): %s\n', name, format.name, format.note);
        end
    end
    EEG.id = id;
    EEG.File = matfilename;
    this.EEG = EEG;
    this.registerRootNode(id, matfilename, 'raw');
end

% ======================================================================= %
function t = rawFileDate(path)
%RAWFILEDATE  When a recording was last changed, as a datenum. dir() of a
%   folder lists its contents, so a folder recording is dated by its entry
%   in its parent instead.
    if isfolder(path)
        [parent, name, ext] = fileparts(path);
        listing = dir(parent);
        t = listing(strcmp({listing.name}, [name ext])).datenum;
    else
        t = dir(path).datenum;
    end
end
