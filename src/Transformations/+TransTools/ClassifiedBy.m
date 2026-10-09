function tf = ClassifiedBy(etc, network)
%CLASSIFIEDBY  Whether an ICLabel classification was made by NETWORK.
%   TF = TransTools.ClassifiedBy(ETC, NETWORK) reads
%   ETC.ic_classification.ICLabel.version, where iclabel records the network
%   it ran; a classification without one, or without classifications at all,
%   is not NETWORK's.
%
%   See also TRANSTOOLS.ICLABELNETWORK.
    tf = false;
    if ~isstruct(etc) || ~isfield(etc, 'ic_classification') ...
            || ~isfield(etc.ic_classification, 'ICLabel')
        return;
    end
    icl = etc.ic_classification.ICLabel;
    tf = isfield(icl, 'classifications') && ~isempty(icl.classifications) ...
        && isfield(icl, 'version') && strcmpi(char(string(icl.version)), network);
end
