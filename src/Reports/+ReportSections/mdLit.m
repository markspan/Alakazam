function s = mdLit(matlabText)
%MDLIT  MATLABTEXT as safe inline Quarto/Pandoc markdown text: escapes
%   the characters markdown gives special meaning outside a code span
%   (\ * _ # [ ] ` < >), so a bin/window label an analyst happened to
%   type with one of those characters cannot corrupt the rendered
%   heading/prose around it (e.g. turn part of a label into unintended
%   italics, or be swallowed as a raw HTML tag).
    s = char(matlabText);
    special = {'\', '*', '_', '#', '[', ']', '`', '<', '>'};
    for i = 1:numel(special)
        s = strrep(s, special{i}, ['\' special{i}]);
    end
end

