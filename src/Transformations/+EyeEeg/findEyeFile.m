function [ascFile, how] = findEyeFile(EEG, varargin)
%FINDEYEFILE  The EyeLink .asc file that belongs to this recording.
%   [ASCFILE, HOW] = EyeEeg.findEyeFile(EEG) finds the eye-tracking file for
%   the recording EEG descends from (EyeEeg.rawRecording): the file with the
%   SAME BASE NAME, in the same folder, with the extension .asc. So
%   subject1myex.set (or .vhdr, .mat) is accompanied by subject1myex.asc.
%   HOW is 'found' or 'converted'.
%
%   AN .EDF IS CONVERTED ONLY WHEN IT CAN BE. EYE-EEG reads EyeLink data as
%   text, which SR Research's own edf2asc produces from the binary .edf.
%   When there is no .asc but there is an .edf, and edf2asc is on this
%   machine, it is converted automatically; otherwise the user is asked for
%   the .asc. The conversion runs on a COPY of the .edf in a temporary
%   folder, so nothing is ever written into the raw directory: raw data is
%   left exactly as it was recorded, and a rerun converts again rather than
%   finding a half-written leftover.
%
%   Options:
%     'Edf2asc'  where the converter is: '' (default) looks on the system
%                path and in SR Research's default install folders; 'none'
%                behaves as if it were absent; a path uses that executable;
%                a function handle @(edfCopy) is called instead of the
%                executable and must leave the .asc beside the copy (tests).
%
%   See also EYEEEG.RAWRECORDING, EYETRACKING.
    parsed = inputParser();
    parsed.addParameter('Edf2asc', '');
    parsed.parse(varargin{:});
    converter = parsed.Results.Edf2asc;

    raw = EyeEeg.rawRecording(EEG);
    if isempty(raw)
        throw(MException('Alakazam:EyeEeg:NoRecording', ['I cannot tell which recording ' ...
            'this dataset was read from, I''m afraid, so there is no way to find the eye-tracking ' ...
            'file that belongs to it. Datasets record their raw file when they are first read; ' ...
            'one cached before that existed may need its raw file re-read (touching the raw ' ...
            'file, so it is newer than its cache, makes the next open read it again).']));
    end
    [folder, base] = fileparts(raw);

    ascFile = existingWithExtension(folder, base, 'asc');
    if ~isempty(ascFile)
        how = 'found';
        return;
    end

    edfFile = existingWithExtension(folder, base, 'edf');
    expected = fullfile(folder, [base '.asc']);
    if isempty(edfFile)
        throw(MException('Alakazam:EyeEeg:NoEyeFile', '%s', sprintf([ ...
            'There is no eye-tracking file for this recording: I looked for %s, which is the ' ...
            'recording''s own name with .asc, and found neither it nor an .edf to convert. ' ...
            'Would you put the EyeLink .asc file beside the recording under that name?'], expected)));
    end

    if ischar(converter) || isstring(converter)
        converter = char(converter);
        if strcmpi(converter, 'none')
            converter = '';
        elseif isempty(converter)
            converter = locateEdf2asc();
        end
    end
    if isempty(converter)
        throw(MException('Alakazam:EyeEeg:NeedsAsc', '%s', sprintf([ ...
            'I found %s but no .asc beside it, and SR Research''s converter edf2asc is not on ' ...
            'this machine, so I cannot read it. Would you convert it (edf2asc comes with the ' ...
            'EyeLink Developers Kit) and put %s next to the recording? With edf2asc installed, ' ...
            'this conversion happens automatically.'], edfFile, expected)));
    end

    ascFile = convertCopy(edfFile, converter);
    how = 'converted';
end

% ======================================================================= %
function file = existingWithExtension(folder, base, extension)
%EXISTINGWITHEXTENSION  FOLDER/BASE.EXTENSION if it exists, trying both
%   cases, since EyeLink software writes .EDF and a converted file can come
%   back .ASC, and on a case-sensitive file system those are different names.
    file = '';
    for ext = {lower(extension), upper(extension)}
        candidate = fullfile(folder, [base '.' ext{1}]);
        if isfile(candidate)
            file = candidate;
            return;
        end
    end
end

function converter = locateEdf2asc()
%LOCATEEDF2ASC  edf2asc on the system path, or in SR Research's default
%   install folders, or '' when it is not on this machine.
    converter = '';
    if ispc
        [status, out] = system('where edf2asc');
    else
        [status, out] = system('command -v edf2asc');
    end
    if status == 0
        first = strtrim(strtok(out, newline));
        if isfile(first)
            converter = first;
            return;
        end
    end
    candidates = {};
    if ispc
        candidates = {'C:\Program Files (x86)\SR Research\EyeLink\bin\edf2asc.exe', ...
                      'C:\Program Files\SR Research\EyeLink\bin\edf2asc.exe'};
    end
    for k = 1:numel(candidates)
        if isfile(candidates{k})
            converter = candidates{k};
            return;
        end
    end
end

function ascFile = convertCopy(edfFile, converter)
%CONVERTCOPY  Convert a copy of the .edf in a temporary folder, so the raw
%   directory is never written to.
    work = tempname();
    mkdir(work);
    [~, base, ext] = fileparts(edfFile);
    copyFile = fullfile(work, [base ext]);
    copyfile(edfFile, copyFile);

    if isa(converter, 'function_handle')
        converter(copyFile);
        output = '';
    else
        % -y overwrites without asking, which a converter run with no one to
        % answer its prompt needs; the rest are edf2asc's defaults (samples and
        % events both), which is what EYE-EEG's parser expects.
        [status, output] = system(sprintf('"%s" -y "%s"', converter, copyFile));
        if status ~= 0 && isempty(existingWithExtension(work, base, 'asc'))
            throw(MException('Alakazam:EyeEeg:ConversionFailed', '%s', sprintf( ...
                'edf2asc could not convert %s:\n\n%s', edfFile, strtrim(output))));
        end
    end

    ascFile = existingWithExtension(work, base, 'asc');
    if isempty(ascFile)
        throw(MException('Alakazam:EyeEeg:ConversionFailed', '%s', sprintf( ...
            'Converting %s with edf2asc produced no .asc file.\n\n%s', edfFile, strtrim(output))));
    end
end
