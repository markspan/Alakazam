function elcFile = Template1005File(errorId)
%TEMPLATE1005FILE  The one 10-5 electrode template every part of Alakazam
%   reads, whichever toolbox happens to be installed.
%
%   ELCFILE = Template1005File(ERRORID) returns FieldTrip's own copy when
%   FieldTrip is on the path, and dipfit's otherwise.
%
%   THE TWO COPIES ARE NUMERICALLY IDENTICAL, and that is measured rather
%   than assumed: same 346 labels in the same order, and a maximum
%   displacement of 0 mm between them (Template1005Test asserts it whenever
%   both are installed). The files differ by a few dozen bytes of header
%   whitespace and by nothing else. So which one this returns cannot change
%   a result, and the preference below is about self-consistency, not
%   about correctness.
%
%   WHY PREFER FIELDTRIP'S, AND WHY NOT REQUIRE IT. The source pipeline pairs
%   these electrodes with FieldTrip's own BEM head model and cortical sheet,
%   which FieldTrip ships and tests together for exactly the "no digitised
%   positions, no individual MRI" case; reading its own copy keeps that set
%   internally consistent without anyone having to trust a cross-toolkit
%   coordinate assumption. But FieldTrip is a ~400 MB consent-gated download
%   that many analyses never need, while dipfit ships with EEGLAB and is
%   always provisioned. Making a scalp map or filling channel locations
%   must not trigger that download, so dipfit's copy remains the fallback
%   and the positions are the same either way.
%
%   ONE ACCESSOR RATHER THAN TWO PATHS. Before this, most callers went
%   through Dipfit1005File while BuildSourceForwardModel resolved
%   FieldTrip's copy inline, and nothing checked that the two agreed. They
%   do; the point of routing everything here is that a future divergence
%   would fail a test instead of quietly producing two different sets of
%   electrode positions in one application.
%
%   See also TRANSTOOLS.DIPFIT1005FILE, TRANSTOOLS.BUILDSOURCEFORWARDMODEL.
    if nargin < 1 || isempty(errorId)
        errorId = 'Alakazam:Template1005File';
    end

    ftDefaults = which('ft_defaults');
    if ~isempty(ftDefaults)
        candidate = fullfile(fileparts(ftDefaults), 'template', 'electrode', 'standard_1005.elc');
        if exist(candidate, 'file')
            elcFile = candidate;
            return;
        end
    end

    elcFile = TransTools.Dipfit1005File(errorId);
end
