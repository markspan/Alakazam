[] = function cb3()
tmpEEG = get(gcbf, 'userdata');

if ~isfield(tmpEEG(1).chaninfo, 'removedchans') 
        warndlg2('There are no Reference channel defined, add it using the channel location editor'); 
elseif isempty(tmpEEG(1).chaninfo.removedchans)
    warndlg2('There are no Reference channel defined, add it using the channel location editor'); 
elseif isfield(tmpEEG(1).chaninfo.removedchans, 'type')
    fidType = ismember(cellfun(@char, {  tmpEEG(1).chaninfo.removedchans.type}, 'UniformOutput', false), 'FID'); 
    if sum(fidType == 0) == 0
        warndlg2('There are no Reference channel defined, add it using the channel location editor'); 
    else 
        tmpchaninfo = tmpEEG(1).chaninfo; 
        [~, tmpval] = pop_chansel({tmpchaninfo.removedchans(~fidType).labels}, 'withindex', 'on'); 
        set(findobj(gcbf, 'tag', 'refloc'  ), 'string',tmpval); 
    end 
end
clear tmpEEG tmpchanlocs tmpval;