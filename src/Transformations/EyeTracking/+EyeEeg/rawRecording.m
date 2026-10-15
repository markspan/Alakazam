function file = rawRecording(EEG)
%RAWRECORDING  The raw file a dataset was read from, or '' if nobody knows.
%   FILE = EyeEeg.rawRecording(EEG) answers from, in order:
%     EEG.etc.alz.rawFile   what Alakazam's loaders record (recordRawFile);
%                           it travels down every branch with EEG.etc
%     EEG.FileName          what loadMATFile has always set
%     EEG.filepath/.filename  EEGLAB's own, set by pop_loadset, which is
%                           what a .set cached before recordRawFile existed
%                           still carries
%   The first that names a file is returned, whether or not it still exists:
%   whether the recording moved is the caller's question, and "it was here"
%   is the most useful thing to tell a user when it is gone.
%
%   See also RECORDRAWFILE, EYEEEG.FINDEYEFILE.
    file = '';
    if isfield(EEG, 'etc') && isstruct(EEG.etc) && isfield(EEG.etc, 'alz') ...
            && isstruct(EEG.etc.alz) && isfield(EEG.etc.alz, 'rawFile')
        file = char(string(EEG.etc.alz.rawFile));
    end
    if isempty(file) && isfield(EEG, 'FileName')
        file = char(string(EEG.FileName));
    end
    if isempty(file) && isfield(EEG, 'filename') && ~isempty(EEG.filename)
        folder = '';
        if isfield(EEG, 'filepath')
            folder = char(string(EEG.filepath));
        end
        file = fullfile(folder, char(string(EEG.filename)));
    end
end
