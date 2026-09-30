function [EEG, used] = readRecording(path, format)
%READRECORDING  Read a recording with the first of its format's readers
%   that can.
%
%   [EEG, USED] = readRecording(PATH, FORMAT) takes FORMAT as an entry of
%   rawFormats() (or the name or an extension of one) and returns the
%   dataset EEGLAB's reader made of the file, and the name of the reader
%   that made it. Each reader is tried in order: its backend is made
%   available first (installing the EEGLAB plugin that provides it, through
%   EEGLAB's plugin manager, as Alakazam's startup does for the plugins it
%   always needs), then it is called. The first that returns a dataset
%   wins. When none does, the error names the file, the format and what
%   each reader said, since "could not read" alone leaves nothing to act on.
%
%   The dataset is returned as the reader made it; the WorkSpace loader
%   adds what Alakazam needs (DataFormat, times, bins) as it does for every
%   format.
%
%   See also RAWFORMATS, WORKSPACE.LOADRAWFILE.
    format = resolveFormat(format, path);
    reasons = {};
    for k = 1:numel(format.readers)
        r = format.readers(k);
        problem = makeAvailable(r);
        if ~isempty(problem)
            reasons{end + 1} = sprintf('%s: %s', r.function, problem); %#ok<AGROW>
            continue;
        end
        try
            EEG = r.read(path);
        catch err
            reasons{end + 1} = sprintf('%s: %s', r.function, err.message); %#ok<AGROW>
            continue;
        end
        if isstruct(EEG) && isfield(EEG, 'data') && ~isempty(EEG.data)
            used = r.function;
            return;
        end
        reasons{end + 1} = sprintf('%s: returned no data', r.function); %#ok<AGROW>
    end

    [~, name, ext] = fileparts(path);
    throw(MException('Alakazam:readRecording', ['I''m afraid %s could not be read as %s. ' ...
        'What each reader said:\n  %s'], [name ext], format.name, strjoin(reasons, sprintf('\n  '))));
end

% ======================================================================= %
function format = resolveFormat(format, path)
%RESOLVEFORMAT  The rawFormats entry meant: given, named, or by extension.
    if isstruct(format)
        return;
    end
    formats = rawFormats();
    key = lower(char(string(format)));
    if isempty(key)
        [~, ~, key] = fileparts(path);
        key = lower(key);
    end
    match = arrayfun(@(f) strcmpi(f.name, key) || any(strcmp(f.extensions, key)), formats);
    if ~any(match)
        throw(MException('Alakazam:readRecording', ...
            'I''m afraid "%s" is not a format Alakazam reads.', key));
    end
    format = formats(find(match, 1));
end

function problem = makeAvailable(r)
%MAKEAVAILABLE  '' when the reader and its backend are on the path, after
%   installing the plugin that provides the backend if need be; otherwise
%   what is missing.
    problem = '';
    needed = {r.function, r.backend};
    needed = needed(~cellfun(@isempty, needed));
    missing = needed(cellfun(@(f) isempty(which(f)), needed));
    if isempty(missing)
        return;
    end
    if ~isempty(r.plugin) && ~isempty(which('plugin_askinstall'))
        try
            plugin_askinstall(r.plugin, missing{end}, true);
        catch
            % Reported below as missing.
        end
        missing = needed(cellfun(@(f) isempty(which(f)), needed));
    end
    if ~isempty(missing)
        if isempty(r.plugin)
            problem = sprintf('%s is not on the path', strjoin(missing, ', '));
        else
            problem = sprintf(['%s is not on the path, and the EEGLAB plugin %s that ' ...
                'provides it could not be installed'], strjoin(missing, ', '), r.plugin);
        end
    end
end
