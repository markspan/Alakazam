function [steps, unresolved] = ComboOrder(bindesc)
%COMBOORDER  The order in which a dataset's combination bins can be computed,
%   and from which bins.
%   [STEPS, UNRESOLVED] = TransTools.ComboOrder(BINDESC) reads the
%   combination bins DefineBins writes ("bin 3 = bin 1 - bin 2", stored as
%   BINDESC(b).combo, a struct array of .bin and .coeff) and returns
%     STEPS       one element per combination bin that can be computed, in an
%                 order where every bin a step uses is an ordinary bin or an
%                 earlier step: .target (its position in BINDESC), .parts
%                 (the positions of the bins it combines) and .coeffs (their
%                 coefficients, in the same order)
%     UNRESOLVED  the positions of combination bins that cannot be computed:
%                 they reference a bin that does not exist, or they are part
%                 of a cycle
%   Both are empty for a dataset without combination bins.
%
%   AN ORDER IS NEEDED because a combination may reference another (a
%   difference of differences, which is how an interaction is written), so
%   it can only be computed once that one has been. Passes repeat until
%   every combination is placed or a pass places nothing more.
%
%   REFERENCES ARE BY BIN INDEX, ERPLAB's number that DefineBins writes into
%   .combo.bin, which need not be the bin's position in BINDESC; the
%   positions are what STEPS returns, since that is what a caller indexes
%   its data with.
%
%   ONE RESOLVER FOR EVERY CALLER. Average, TimeFrequency's ComputeErsp and
%   Unfold.fitBins each used to carry their own copy of this loop. Each now
%   applies these steps to what it has: Average to its averages, standard
%   errors, SMEs and trial counts, ComputeErsp to ERSP maps, fitBins to fitted
%   waveforms. DefineBins refuses an unknown reference or a cycle when it
%   parses a script, so UNRESOLVED is only ever non-empty for a hand-built or
%   edited bindesc, and each caller says so in its own words.
%
%   See also AVERAGE, COMPUTEERSP, UNFOLD.FITBINS, DEFINEBINS.
    steps = struct('target', {}, 'parts', {}, 'coeffs', {});
    unresolved = zeros(1, 0);
    n = numel(bindesc);
    isCombo = false(1, n);
    if isfield(bindesc, 'combo')
        isCombo = ~cellfun(@isempty, {bindesc.combo});
    end
    if ~any(isCombo)
        return;
    end

    position = containers.Map('KeyType', 'double', 'ValueType', 'double');
    for b = 1:n
        position(bindesc(b).index) = b;
    end

    resolved = ~isCombo;
    progress = true;
    while progress && ~all(resolved)
        progress = false;
        for b = find(~resolved)
            combo = bindesc(b).combo;
            if ~all(isKey(position, num2cell([combo.bin])))
                continue;   % references a bin that does not exist; never resolves
            end
            parts = arrayfun(@(t) position(t.bin), combo);
            if ~all(resolved(parts))
                continue;   % a part is itself a combination not placed yet
            end
            steps(end + 1) = struct('target', b, 'parts', reshape(parts, 1, []), ...
                'coeffs', reshape([combo.coeff], 1, [])); %#ok<AGROW>
            resolved(b) = true;
            progress = true;
        end
    end
    unresolved = find(~resolved);
end
