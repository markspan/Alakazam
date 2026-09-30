function formats = rawFormats()
%RAWFORMATS  Every recording format Alakazam opens, and how it reads each.
%
%   FORMATS = rawFormats() returns a struct array, one entry per format:
%     .name        what the format is called ('European Data Format')
%     .extensions  a cellstr of lower-case extensions, with the dot
%     .isFolder    true when a recording is a folder (EGI's .mff)
%     .loader      the WorkSpace method that opens it: a format of its own
%                  ('loadSETFile', ...) or the generic 'loadRawFile'
%     .readers     for loadRawFile: the readers to try, in order, each a
%                  struct with
%                    .function  the EEGLAB function called
%                    .backend   a function its toolbox provides, probed
%                               before the call ('' when the reader needs
%                               nothing beyond EEGLAB)
%                    .plugin    the EEGLAB plugin that provides the backend,
%                               installed through EEGLAB's plugin manager
%                               when it is missing ('' for none)
%                    .read      @(path) -> EEG
%     .note        what to know about the format once it is read
%     .accepts     @(path) -> logical: whether a file with the extension is
%                  this format at all. The scan skips one that is not,
%                  without a word: an EyeLink eye-tracking file is also an
%                  '.edf', and lies beside the recording it belongs to for
%                  the EyeTracking step to join, so it must not be offered
%                  as a recording of its own
%
%   WORKSpace.open scans the raw directory for each extension and hands
%   every match to its loader; the four formats Alakazam has always read
%   keep their own loaders, and every other goes through loadRawFile, which
%   tries its readers in order and caches the first success as the others
%   do. Adding a format is an entry here.
%
%   WHY SEVERAL READERS. A dedicated reader knows its format best: BIOSIG
%   for EDF, BDF and GDF, the Neuroscan and EGI plugins for theirs. EEGLAB's
%   File-IO route (pop_fileio, on FieldTrip's ft_read_header and
%   ft_read_data) reads nearly everything, and is the fall-back: it takes
%   over when the dedicated plugin cannot be installed, and for a file the
%   dedicated reader refuses (an ANT Neuro .cnt, which shares Neuroscan's
%   extension). Formats with no dedicated EEGLAB reader (Micromed, Nicolet,
%   MNE's .fif) go through File-IO alone.
%
%   NOT HERE, ON PURPOSE: '.eeg', which is BrainVision's data file (opened
%   through its .vhdr), Nihon Kohden's recording and Neuroscan's epoched
%   file at once, so a scan cannot tell which it is looking at; and '.dat',
%   which half the world uses for something. Read such a file with its own
%   reader and save it as a .set.
%
%   See also READRECORDING, WORKSPACE.LOADRAWFILE, WORKSPACE.OPEN.
    biosig = reader('pop_biosig', 'sopen', 'Biosig', @(path) pop_biosig(path));
    fileio = reader('pop_fileio', 'ft_read_data', 'Fileio', @(path) pop_fileio(path));

    formats = [ ...
        legacy('Alakazam or MATLAB session', {'.mat'}, 'loadMATFile'), ...
        legacy('BrainVision', {'.vhdr'}, 'loadBVAFile'), ...
        legacy('EEGLAB dataset', {'.set'}, 'loadSETFile'), ...
        legacy('ERPLAB erpset', {'.erp'}, 'loadERPFile'), ...
        withCheck(generic('European Data Format (EDF, EDF+)', {'.edf'}, false, [biosig, fileio], ...
            ['EDF channel labels often carry a prefix and a reference ("EEG Fp1-REF"); rename ' ...
             'them to 10-5 labels in the Channel Editor to get scalp positions.']), ...
            @(path) startsWithBytes(path, uint8('0       '))), ...
        withCheck(generic('BioSemi (BDF)', {'.bdf'}, false, [biosig, fileio], ...
            ['A BioSemi recording has no reference (it is recorded against CMS/DRL), so ' ...
             're-reference it (ReRef) before anything else; its common-mode noise is large.']), ...
            @(path) startsWithBytes(path, [uint8(255), uint8('BIOSEMI')])), ...
        generic('General Data Format (GDF)', {'.gdf'}, false, [biosig, fileio], ''), ...
        generic('Neuroscan or ANT Neuro continuous (CNT)', {'.cnt'}, false, ...
            [reader('pop_loadcnt', 'pop_loadcnt', 'neuroscanio', ...
                @(path) pop_loadcnt(path, 'dataformat', 'auto')), fileio], ...
            'Neuroscan''s reader is tried first; an ANT Neuro file, which shares the extension, falls to File-IO.'), ...
        generic('EGI Netstation (MFF)', {'.mff'}, true, ...
            [reader('pop_mffimport', 'pop_mffimport', 'mffmatlabio', @(path) pop_mffimport(path, 'code')), fileio], ...
            ['An .mff recording is a folder; it is read as one recording. Event types come from ' ...
             'each event''s code field, which is where Netstation puts the trigger.']), ...
        generic('EGI simple binary', {'.raw'}, false, ...
            [reader('pop_readegi', '', '', @(path) pop_readegi(path)), fileio], ''), ...
        generic('Lab Streaming Layer (XDF)', {'.xdf'}, false, ...
            [reader('pop_loadxdf', 'pop_loadxdf', 'xdfimport', @(path) pop_loadxdf(path, 'streamtype', 'EEG')), fileio], ...
            'The EEG stream is read; markers from the other streams become events.'), ...
        generic('Micromed (TRC)', {'.trc'}, false, fileio, ''), ...
        generic('Nicolet (.e)', {'.e'}, false, fileio, ''), ...
        generic('MNE-Python / Neuromag (FIF)', {'.fif'}, false, fileio, ...
            'Every channel in the file is read, magnetometers and gradiometers included; select the EEG with SelectData.')];
end

% ======================================================================= %
function f = legacy(name, extensions, loader)
    f = entry(name, extensions, false, loader, struct([]), '');
end

function f = generic(name, extensions, isFolder, readers, note)
    f = entry(name, extensions, isFolder, 'loadRawFile', readers, note);
end

function f = entry(name, extensions, isFolder, loader, readers, note)
    if isempty(readers)
        readers = reader('', '', '', []);
        readers(:) = [];
    end
    f = struct('name', name, 'extensions', {lower(extensions)}, 'isFolder', isFolder, ...
        'loader', loader, 'readers', readers, 'note', note, 'accepts', @(path) true);
end

function f = withCheck(f, accepts)
%WITHCHECK  A format whose files are recognised by their first bytes as
%   well as their extension.
    f.accepts = accepts;
end

function tf = startsWithBytes(path, signature)
%STARTSWITHBYTES  True when the file at PATH begins with SIGNATURE. The
%   European Data Format header opens with its version, '0' and seven
%   spaces; BioSemi's variant with byte 255 and 'BIOSEMI'. An EyeLink '.edf'
%   opens with neither.
    tf = false;
    fid = fopen(path, 'r');
    if fid < 0
        return;
    end
    closer = onCleanup(@() fclose(fid));
    head = fread(fid, numel(signature), '*uint8');
    tf = numel(head) == numel(signature) && all(head(:) == signature(:));
end

function r = reader(fn, backend, plugin, read)
    r = struct('function', fn, 'backend', backend, 'plugin', plugin, 'read', read);
end
