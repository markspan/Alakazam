function s = rLit(matlabText)
%RLIT  MATLABTEXT as a safe R double-quoted string literal's INNER text
%   (caller still supplies the surrounding quotes): backslashes and
%   double quotes escaped, so a bin/window label an analyst happened to
%   type with one of those characters cannot break the generated R
%   syntax.
    s = strrep(char(matlabText), '\', '\\');
    s = strrep(s, '"', '\"');
end

