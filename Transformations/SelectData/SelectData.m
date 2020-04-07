function [EEG, options] = Trans_SelectData(input,opts)

if (nargin < 1)
    ME = MException('Alakazam:SelectData','Problem in SelectData: No Data Supplied');
    throw(ME);
end

if (nargin == 1)
    options = 'Init';
else
    options = opts;
end

EEG = input;

if (ischar(options))
    if (strcmpi(options, 'Init'))
        [EEG, options] = pop_select(input);
    
    end
else
    eval(options.Param)
end

