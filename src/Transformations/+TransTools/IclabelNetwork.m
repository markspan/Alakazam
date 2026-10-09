function network = IclabelNetwork()
%ICLABELNETWORK  The ICLabel network Alakazam classifies components with.
%   NETWORK = TransTools.IclabelNetwork() is 'default', ICLabel's own
%   recommended network (pop_iclabel offers "Default (recommended)", and
%   iclabel's help keeps 'beta' for replicating old results). One place, so
%   AutoEyeICA and RemoveComponents classify alike, and a decomposition
%   classified by another network can be recognised (TransTools.ClassifiedBy)
%   and classified again rather than reused as it was.
%
%   Until 2026-10 Alakazam called the 'beta' network; nodes made then carry
%   it in etc.ic_classification.ICLabel.version.
%
%   See also AUTOEYEICA, REMOVECOMPONENTS, TRANSTOOLS.CLASSIFIEDBY.
    network = 'default';
end
