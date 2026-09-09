function count = inlineDataUriResources(htmlFile)
%INLINEDATAURIRESOURCES  Rewrite a rendered report so the app's own viewer
%   can read it: every stylesheet and script Quarto delivered as a data:
%   URI becomes an inline <style> or <script>.
%
%   COUNT is how many were inlined. The file is rewritten in place, and
%   only when COUNT is greater than zero.
%
%   WHY THIS IS NEEDED, measured rather than assumed. uihtml does not open
%   a local file directly. MATLAB serves it from its own connector, over
%   https://127.0.0.1:<port>/static/..., and that server sends a
%   Content-Security-Policy. A probe page loaded into a real uihtml
%   reported:
%
%       inline <style>        applied
%       small data:text/css   NOT applied  (31 bytes)
%       large data:text/css   NOT applied  (1.35 MB)
%       data: <script>        did not run
%       engine                Chrome 141
%
%   So this is not an old engine and not a size limit. The policy refuses
%   data: for style-src and script-src, while allowing inline ones and
%   allowing data: images, which is why the figures appear at all.
%
%   WHAT IT COST BEFORE. Quarto self-contained output puts its whole theme
%   in one <link href="data:text/css,...">, 1.36 MB of it, so in the app
%   the reports were rendering with no Bootstrap at all. Two symptoms had
%   already been met and patched one at a time without the cause being
%   found: a callout reading "TipNothing flagged", which is the
%   .screen-reader-only rule missing, and figures drawn about four times
%   too wide, which is .img-fluid missing. Both rules live in that
%   stylesheet. Inlining it fixes those and everything else it carries.
%
%   IMAGES ARE LEFT ALONE deliberately. data: images load under the policy,
%   they are the bulk of the file, and decoding them would only re-encode
%   them again.
%
%   A BROWSER IS UNAFFECTED. An inline <style> and a linked one of the same
%   content, in the same position, cascade identically, and the file stays
%   self-contained. It also gets smaller, since percent and base64 encoding
%   are both larger than what they encode.
%
%   See also RENDERQUARTOREPORT, REPORTDOC.YAMLHEADER, REPORTVIEW.
    count = 0;
    if exist(htmlFile, 'file') ~= 2
        error('Alakazam:inlineDataUriResources:noFile', ...
            'No such file: %s', htmlFile);
    end

    html = readUtf8(htmlFile);

    % Both patterns want whitespace after the tag name, which any tag
    % carrying an href or a src has.
    [html, nCss] = inlineTags(html, '<link\s[^>]*>', 'href', 'style');
    [html, nJs]  = inlineTags(html, '<script\s[^>]*>\s*</script>', 'src', 'script');
    count = nCss + nJs;

    if count > 0
        fid = fopen(htmlFile, 'w', 'n', 'UTF-8');
        if fid < 0
            error('Alakazam:inlineDataUriResources:cannotWrite', ...
                'Could not open %s for writing.', htmlFile);
        end
        closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
        fprintf(fid, '%s', html);
    end
end

% ======================================================================= %
function text = readUtf8(file)
%READUTF8  The whole file as char, decoded as UTF-8 whatever the platform
%   default happens to be.
    fid = fopen(file, 'r', 'n', 'UTF-8');
    if fid < 0
        error('Alakazam:inlineDataUriResources:cannotRead', ...
            'Could not open %s for reading.', file);
    end
    closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
    text = fread(fid, '*char')';
end

% ======================================================================= %
function [html, count] = inlineTags(html, tagPattern, urlAttr, kind)
%INLINETAGS  Replace every TAGPATTERN whose URLATTR is a data: URI of the
%   right kind with the inline equivalent. KIND is 'style' or 'script'.
%
%   Rebuilt by slicing rather than by regexprep: the replacement text is a
%   megabyte of arbitrary CSS, and a replacement string is scanned for $1
%   and friends.
    count = 0;
    [starts, stops, tags] = regexp(html, tagPattern, 'start', 'end', 'match');
    if isempty(starts)
        return;
    end

    pieces = cell(1, 2 * numel(starts) + 1);
    nPieces = 0;
    last = 1;
    for k = 1:numel(starts)
        replacement = inlineOne(tags{k}, urlAttr, kind);
        if isempty(replacement)
            continue;   % not a data: URI of this kind, or not safe to inline
        end
        nPieces = nPieces + 1; pieces{nPieces} = html(last:starts(k) - 1);
        nPieces = nPieces + 1; pieces{nPieces} = replacement;
        last = stops(k) + 1;
        count = count + 1;
    end
    if count == 0
        return;
    end
    nPieces = nPieces + 1; pieces{nPieces} = html(last:end);
    html = [pieces{1:nPieces}];
end

% ======================================================================= %
function out = inlineOne(tag, urlAttr, kind)
%INLINEONE  The inline form of one tag, or '' to leave it alone.
    out = '';

    uri = attributeValue(tag, urlAttr);
    if isempty(uri) || ~startsWith(uri, 'data:')
        return;
    end

    [payload, mediaType, ok] = decodeDataUri(uri);
    if ~ok
        return;
    end

    switch kind
        case 'style'
            if ~contains(mediaType, 'text/css')
                return;
            end
            % A </style anywhere in the text would close the element early.
            % Escaping it is only valid inside a CSS string, so the honest
            % move is to leave the link alone; it does not happen in
            % practice, and a report that renders in a browser but not in
            % the app beats one that renders wrongly in both.
            if containsClosingTag(payload, 'style')
                return;
            end
            out = ['<style' carryAttribute(tag, 'id') '>' newline payload newline '</style>'];
        case 'script'
            if ~isScriptMediaType(mediaType)
                return;
            end
            if containsClosingTag(payload, 'script')
                return;
            end
            % type="module" changes the scoping and the deferred timing, so
            % it has to survive the move.
            out = ['<script' carryAttribute(tag, 'type') '>' newline payload newline '</script>'];
    end
end

% ======================================================================= %
function tf = isScriptMediaType(mediaType)
    tf = contains(mediaType, 'javascript') || contains(mediaType, 'text/ecmascript');
end

% ======================================================================= %
function tf = containsClosingTag(text, name)
    tf = ~isempty(regexpi(text, ['</\s*' name], 'once'));
end

% ======================================================================= %
function out = carryAttribute(tag, name)
%CARRYATTRIBUTE  ' name="value"' if TAG has that attribute, else ''.
    value = attributeValue(tag, name);
    if isempty(value)
        out = '';
    else
        out = [' ' name '="' value '"'];
    end
end

% ======================================================================= %
function value = attributeValue(tag, name)
    % A leading space, not a word boundary: \<id would also match the "id"
    % inside data-id.
    tok = regexp(tag, ['\s' name '\s*=\s*"([^"]*)"'], 'tokens', 'once');
    if isempty(tok)
        value = '';
    else
        value = tok{1};
    end
end

% ======================================================================= %
function [text, mediaType, ok] = decodeDataUri(uri)
%DECODEDATAURI  The text a data: URI carries, and the media type it claims.
    text = ''; mediaType = ''; ok = false;

    comma = find(uri == ',', 1);
    if isempty(comma)
        return;
    end
    meta = uri(6:comma - 1);          % past 'data:'
    payload = uri(comma + 1:end);

    isBase64 = endsWith(meta, ';base64');
    if isBase64
        mediaType = meta(1:end - numel(';base64'));
    else
        mediaType = meta;
    end

    try
        if isBase64
            bytes = matlab.net.base64decode(payload);
        else
            bytes = percentDecodeBytes(payload);
        end
        text = native2unicode(uint8(bytes(:))', 'UTF-8');
    catch
        return;
    end
    ok = true;
end

% ======================================================================= %
function bytes = percentDecodeBytes(str)
%PERCENTDECODEBYTES  %XX to bytes, everything else through unchanged.
%
%   NOT urldecode. That one is for form encoding, where '+' means a space,
%   and a stylesheet is full of '+' in sibling selectors ("a + b"). Turning
%   those into spaces changes what the CSS matches.
    b = uint8(str);
    idx = find(b == uint8('%'));
    idx = idx(idx + 2 <= numel(b));
    if isempty(idx)
        bytes = b;
        return;
    end

    hi = hexValue(b(idx + 1));
    lo = hexValue(b(idx + 2));
    good = hi >= 0 & lo >= 0;
    idx = idx(good);
    if isempty(idx)
        bytes = b;
        return;
    end

    b(idx) = uint8(hi(good) * 16 + lo(good));
    drop = false(size(b));
    drop([idx + 1, idx + 2]) = true;
    b(drop) = [];
    bytes = b;
end

% ======================================================================= %
function v = hexValue(c)
%HEXVALUE  0-15 for a hex digit's character code, -1 for anything else.
    c = double(c);
    v = -ones(size(c));
    m = c >= 48 & c <= 57;  v(m) = c(m) - 48;   % 0-9
    m = c >= 97 & c <= 102; v(m) = c(m) - 87;   % a-f
    m = c >= 65 & c <= 70;  v(m) = c(m) - 55;   % A-F
end
