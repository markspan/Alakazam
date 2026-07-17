function steps = readTemplate(~, file)
%READTEMPLATE  Parse a saved template file (see onSaveTemplate)
%   into a struct array of (transformId, params) steps, in order.
%   Throws a friendly error if FILE is missing, unreadable, or not
%   a recognisable Alakazam template.
    if exist(file, "file") ~= 2
        throw(MException('Alakazam:readTemplate', 'File not found:\n\n    %s', file));
    end
    raw = jsondecode(fileread(file));
    if ~isstruct(raw) || ~isfield(raw, 'alakazamTemplate') ...
            || ~isequal(raw.alakazamTemplate, true) || ~isfield(raw, 'steps')
        throw(MException('Alakazam:readTemplate', ...
            'This does not look like an Alakazam template file.'));
    end

    steps = struct('transformId', {}, 'params', {});
    for k = 1:numel(raw.steps)
        rawStep = raw.steps(k);
        steps(k) = struct('transformId', char(rawStep.transformId), 'params', rawStep.params);
    end
end
