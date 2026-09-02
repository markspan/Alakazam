function [name, gloss] = SourceMethodName(method)
%SOURCEMETHODNAME  How an inverse method is named to the analyst.
%   [NAME, GLOSS] = SourceMethodName(METHOD) turns an internal method id
%   into the name the user sees, plus a short expansion of it.
%
%   ONE PLACE, BECAUSE THE ID AND THE NAME DISAGREE. FieldTrip's 'mne'
%   with a scaled identity noise covariance is dSPM, and every surface the
%   analyst touches says so: the dialog's dropdown, the report's method
%   table, the on-screen result summary. Printing the raw id in any one of
%   them would have that surface contradict the other two about which
%   method just ran, which is exactly the kind of disagreement a reader
%   cannot resolve from the document in front of them.
%
%   See also SOURCECLUSTERSTATS, TRANSTOOLS.INVERSESOLUTION.
    switch lower(char(string(method)))
        case 'mne'
            name  = 'dSPM';
            gloss = 'noise-normalized minimum norm';
        case 'sloreta'
            name  = 'sLORETA';
            gloss = 'standardized';
        case 'eloreta'
            name  = 'eLORETA';
            gloss = 'exact low-resolution tomography';
        otherwise
            name  = char(string(method));
            gloss = '';
    end
end
