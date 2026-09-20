function key = DataKey(varargin)
%DATAKEY  A hash of the content of its arguments, for deciding that a stored
%   result was computed from exactly this data.
%
%   KEY = TransTools.DataKey(DATA, ...) returns a 40-character hex SHA-1 of
%   every argument in order: numeric and logical arrays by class, size and
%   bytes, text (char, string, cellstr) by its characters. Two calls agree if
%   and only if their arguments are identical, to the last bit.
%
%   WHY A HASH RATHER THAN SourceCache.Fingerprint. That is a handful of
%   sums, good for noticing that a stored estimate no longer belongs to the
%   data beside it, where a mistake costs a stale figure the next
%   recalculation corrects. An ICA decomposition is reused instead of
%   recomputed, and if it were reused for data it does not belong to the
%   components would be applied to the wrong recording without any sign
%   that anything was wrong. Sums cannot rule that out, and a hash of the
%   data itself can, at about a third of a second for a 76 MB epoched
%   recording (the first call in a session also starts Java, about 1.5 s).
%
%   Returns '' when a hash cannot be computed (no Java in this session), which
%   every caller treats as "no cache, compute afresh".
%
%   See also TRANSTOOLS.ICACACHE, AUTOEYEICA.
    try
        digest = java.security.MessageDigest.getInstance('SHA-1');
        for k = 1:numel(varargin)
            v = varargin{k};
            if isnumeric(v) || islogical(v)
                digest.update(uint8(sprintf('%s:%s;', class(v), mat2str(size(v)))));
                v = v(:);
                chunk = 2^22;     % elements per update, to bound the copy typecast makes
                for a = 1:chunk:numel(v)
                    digest.update(typecast(v(a:min(a + chunk - 1, numel(v))), 'uint8'));
                end
            else
                text = char(strjoin(string(v(:)).', char(1)));
                digest.update(uint8(text));
            end
            digest.update(uint8(';'));
        end
        bytes = typecast(digest.digest(), 'uint8');
        key = lower(reshape(dec2hex(bytes).', 1, []));
    catch
        key = '';
    end
end
