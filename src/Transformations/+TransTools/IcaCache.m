function varargout = IcaCache(action, key, value)
%ICACACHE  Decompositions already computed this session, by the hash of the
%   data they were computed from (TransTools.DataKey).
%
%       value = TransTools.IcaCache('get', key)      [] when there is none
%       TransTools.IcaCache('put', key, value)
%       TransTools.IcaCache('clear')
%       n = TransTools.IcaCache('hits')              how often 'get' found one
%
%   WHAT THIS BUYS. ICA is the one step of a preprocessing chain whose cost
%   varies by an order of magnitude between recordings (13 s typically, 111 s
%   on one of ten) and whose result is not reproducible: nothing seeds it, so
%   running it twice on the same data gives different components. With this,
%   AutoEyeICA reuses a decomposition for the same data, so changing the eye
%   threshold re-prunes instead of re-decomposing, and a recalculation gives
%   the same components as the run before it.
%
%   THE COST OF THAT: running an unchanged AutoEyeICA again no longer draws a
%   fresh decomposition. To force one, set Redecompose = true in its options.
%
%   Held in memory only. Recalculate primes it from the decomposition stored on
%   the node being recalculated (see AutoEyeICA's etc.alz.eyeICA), which is
%   how a threshold edit in a later session still finds it.
%
%   Bounded, oldest first, so a long session over many recordings does not
%   keep every decomposition; each is only a few kilobytes.
%
%   See also TRANSTOOLS.DATAKEY, AUTOEYEICA, ALAKAZAM.RECALCULATETRANSFORMNODE.
    persistent entries order hits
    if isempty(entries)
        entries = containers.Map('KeyType', 'char', 'ValueType', 'any');
        order = {};
        hits = 0;
    end
    maxEntries = 32;

    switch lower(action)
        case 'get'
            varargout{1} = [];
            if ~isempty(key) && isKey(entries, key)
                varargout{1} = entries(key);
                hits = hits + 1;
            end
        case 'put'
            if isempty(key)
                return;
            end
            if ~isKey(entries, key)
                order{end + 1} = key;
            end
            entries(key) = value;
            while numel(order) > maxEntries
                remove(entries, order{1});
                order(1) = [];
            end
        case 'clear'
            entries = containers.Map('KeyType', 'char', 'ValueType', 'any');
            order = {};
            hits = 0;
        case 'hits'
            varargout{1} = hits;
        otherwise
            throw(MException('Alakazam:IcaCache', ...
                'I''m afraid IcaCache does not know the action "%s".', action));
    end
end
