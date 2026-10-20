function [iv, k] = scanRtWindow(T, k, binIndex)
%SCANRTWINDOW  'rt within (lo,hi] ms' right after a bin's expression.
%
%   Each bound is either a plain number of milliseconds or a bound relative
%   to the bin's own reaction times (see scanRtBound):
%
%       rt within (200,500] ms
%       rt within (150, mean + 2.5 sd] ms
%       rt within [mean - 2.5 sd, mean + 2.5 sd] ms
%
%   IV has the fields of an ordinary window (lo, hi, loOpen, hiOpen, unit)
%   plus loSd and hiSd. A plain bound has its value in lo/hi and NaN in
%   loSd/hiSd; a relative bound has NaN in lo/hi and its multiplier of the
%   standard deviation in loSd/hiSd (0 for a bare 'mean'). resolveRtWindow
%   turns a relative window into a plain one, per recording and per bin.
%
%   This is a scanner of its own rather than scanInterval, which the epoch
%   directive and the relation windows share: only a reaction time has a
%   distribution to be relative to, so only here may a bound be anything
%   but a number.
    t = DefineBinsEngine.tokAt(T, k);
    if ~(t.kind == "kw" && t.val == "within")
        DefineBinsEngine.throwParseError(t.pos, sprintf([ ...
            'bin %g: I''m afraid ''rt'' on its own is not quite enough -- it needs ' ...
            '''within (lo,hi] ms'' right after it to say what reaction-time range to ' ...
            'keep, for example rt within (200,500] ms.'], binIndex));
    end
    k = k + 1;

    o = DefineBinsEngine.tokAt(T, k);
    if ~(o.kind == "punc" && (o.val == "(" || o.val == "["))
        DefineBinsEngine.throwParseError(o.pos, sprintf([ ...
            'bin %g: a reaction-time window needs to start with ''('' (exclusive ' ...
            'bound) or ''['' (inclusive bound), like rt within (200,1200] ms -- I ' ...
            'wasn''t able to find either one here.'], binIndex));
    end
    loOpen = (o.val == "(");
    [lo, k] = DefineBinsEngine.scanRtBound(T, k + 1, binIndex);

    c = DefineBinsEngine.tokAt(T, k);
    if ~(c.kind == "punc" && c.val == ",")
        DefineBinsEngine.throwParseError(c.pos, sprintf([ ...
            'bin %g: a reaction-time window needs a comma between its low and high ' ...
            'bound, for example rt within (150, mean + 2.5 sd] ms -- I''m afraid I ' ...
            'found the low bound, but no comma after it.'], binIndex));
    end
    [hi, k] = DefineBinsEngine.scanRtBound(T, k + 1, binIndex);

    c = DefineBinsEngine.tokAt(T, k);
    if ~(c.kind == "punc" && (c.val == ")" || c.val == "]"))
        DefineBinsEngine.throwParseError(c.pos, sprintf([ ...
            'bin %g: a reaction-time window needs to end with '')'' (exclusive bound) ' ...
            'or '']'' (inclusive bound), like rt within (200,1200] ms -- I couldn''t ' ...
            'find either one here, I''m afraid.'], binIndex));
    end
    hiOpen = (c.val == ")");
    k = k + 1;

    % A reaction time is a duration in milliseconds, so unlike a within-window
    % (which may legitimately be counted in samples or in events) there is
    % nothing for the other two units to mean here. evaluateBins compares the
    % window against a millisecond value without consulting .unit, so
    % "rt within (200,500] samples" used to be accepted and then silently
    % treated as milliseconds. Refusing it is the honest answer: a misread
    % window changes which trials enter the bin, and says nothing about it in
    % the report.
    unit = 'ms';
    u = DefineBinsEngine.tokAt(T, k);
    if u.kind == "kw" && (u.val == "ms" || u.val == "samples" || u.val == "events")
        unit = char(u.val);
        k = k + 1;
    end
    if ~strcmp(unit, 'ms')
        DefineBinsEngine.throwParseError(u.pos, sprintf([ ...
            'bin %g: a reaction time is a duration, so ''rt within'' is measured in ' ...
            'milliseconds -- ''%s'' is not a unit it can use. Would you write it as ' ...
            'rt within (200,500] ms? (''samples'' and ''events'' do work on an ordinary ' ...
            'within-window, just not on this one.)'], binIndex, unit));
    end

    % An inverted window can be caught here only when both bounds are of the
    % same kind; a plain bound against a relative one depends on the data,
    % and resolveRtWindow reports it when it happens.
    loRel = ~isnan(lo.sd);
    hiRel = ~isnan(hi.sd);
    if ~loRel && ~hiRel && lo.value > hi.value
        DefineBinsEngine.throwParseError(o.pos, sprintf([ ...
            'bin %g: this reaction-time window''s low bound (%g) is greater than its ' ...
            'high bound (%g), I''m afraid, so no trial could ever fall inside it. Did ' ...
            'you perhaps mean (%g,%g]?'], binIndex, lo.value, hi.value, hi.value, lo.value));
    end
    if loRel && hiRel && lo.sd > hi.sd
        DefineBinsEngine.throwParseError(o.pos, sprintf([ ...
            'bin %g: this reaction-time window''s low bound (mean %+g sd) lies above ' ...
            'its high bound (mean %+g sd), I''m afraid, so no trial could ever fall ' ...
            'inside it. Did you perhaps mean the two the other way round?'], ...
            binIndex, lo.sd, hi.sd));
    end

    iv = struct('lo', lo.value, 'hi', hi.value, 'loOpen', loOpen, 'hiOpen', hiOpen, ...
                'unit', unit, 'loSd', lo.sd, 'hiSd', hi.sd);
end
