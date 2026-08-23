function tf = inInterval(d, iv)
%ININTERVAL  Whether signed distance D falls within interval IV, honouring
%   its own open/closed bounds.
    if iv.loOpen; loOK = d > iv.lo; else; loOK = d >= iv.lo; end
    if iv.hiOpen; hiOK = d < iv.hi; else; hiOK = d <= iv.hi; end
    tf = loOK && hiOK;
end
