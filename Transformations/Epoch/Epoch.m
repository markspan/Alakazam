function [EEG, options] = Epoch(input,opts)

if (nargin < 1)
    ME = MException('Alakazam:Epoch','Problem in Epoch: No Data Supplied');
    throw(ME);
end

if (nargin == 1)
    options = 'Init';
else
    options = opts;
end

EEG = input;

if (strcmpi(EEG.DataFormat,'CONTINUOUS'))
    
    if (ischar(options))
        if (strcmpi(options, 'Init'))
            [EEG, options] = pop_epoch(input);
        end
    else
        eval(options.Param)
    end
    
    if size(EEG.data,3) > 1
        EEG.DataFormat = 'EPOCHED';
    end
end