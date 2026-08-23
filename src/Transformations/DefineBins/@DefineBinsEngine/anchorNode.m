function node = anchorNode(codes)
%ANCHORNODE  Build a flat-code-list 'anchor' expression node.
    node.op = 'anchor'; node.codes = codes;
end
