function title = tabTitleFor(EEG)
%TABTITLEFOR  The title of the plot tab a dataset is drawn in.
%   TITLE = TABTITLEFOR(EEG) reads EEG.File, EEG.id and EEG.Call:
%     - a step's result, whose file is named after its transformation and
%       the time it was made ("Average051423"), is "Average (051423)": its
%       id alone ("Average") is shared by every average in the tree;
%     - a step's result renamed in the tree (its id is no longer its
%       transformation, EEG.Call) is its new name, as the tree shows it;
%     - anything else, a recording, a grand average, a report, is its
%       file's name.
%
%   It used to be only the first and last, so a renamed node's tab kept the
%   file's name even when opened afresh.
%
%   See also ALAKAZAMPLOTTER, RETITLEPLOT, ONRENAMENODE.
    [~, title] = fileparts(char(string(EEG.File)));
    id = '';
    if isfield(EEG, 'id') && ~isempty(EEG.id)
        id = char(string(EEG.id));
    end
    call = '';
    if isfield(EEG, 'Call') && ~isempty(EEG.Call)
        call = char(string(EEG.Call));
    end
    if isempty(id)
        return;
    end
    if startsWith(title, id) && ~strcmp(title, id)
        title = sprintf('%s (%s)', id, title(numel(id) + 1:end));
    elseif ~isempty(call) && ~strcmp(id, call)
        title = id;
    end
end
