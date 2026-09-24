function EEG = recordRawFile(EEG, rawFile)
%RECORDRAWFILE  Note on the dataset which raw file it was read from.
%   EEG = recordRawFile(EEG, RAWFILE) sets EEG.etc.alz.rawFile to the full
%   path of the recording a loader has just read.
%
%   WHY ON THE DATASET: a transformation receives a dataset and nothing else.
%   The raw directory belongs to the workspace, which no transformation can
%   see, so a step that needs a file lying next to the recording (EyeTracking
%   finds subject1.asc beside subject1.set) had no way to know where the
%   recording was. EEG.etc travels down every branch unchanged, so recording
%   the path once, where the file is read, makes it available to every node
%   derived from it, however many steps later.
%
%   Datasets cached before this existed do not carry it; EyeEeg.rawRecording
%   falls back to EEGLAB's own .filepath/.filename for those.
%
%   See also LOADSETFILE, LOADBVAFILE, LOADMATFILE, EYEEEG.RAWRECORDING.
    if ~isfield(EEG, 'etc') || ~isstruct(EEG.etc)
        EEG.etc = struct();
    end
    if ~isfield(EEG.etc, 'alz') || ~isstruct(EEG.etc.alz)
        EEG.etc.alz = struct();
    end
    EEG.etc.alz.rawFile = char(rawFile);
end
