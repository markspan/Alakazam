function release = fieldTripRelease()
%FIELDTRIPRELEASE  The FieldTrip build Alakazam is pinned to, as the folder
%   its archive unzips into ('fieldtrip-20260924').
%
%   The one place the pin is written: ensureFieldTrip downloads
%   https://download.fieldtriptoolbox.org/<release>.zip, and it and
%   isFieldTripAvailable reattach only that build (EEGLabEnvironment.
%   findInstalled), so an older one installed beside it is not used. Move
%   it by hand when a refresh is wanted, and run the suite against it
%   (dependencies.md says what to check).
%
%   20260924 replaced 20260812 on 10 October 2026. Nothing Alakazam calls
%   changed its results between the two: ft_freqanalysis changed only its
%   FOOOF output, ft_statistics_montecarlo only when it warns about an
%   uncorrected two-sided test (Alakazam sets correcttail 'alpha'),
%   ft_inverse_dipolefit only its MEG rigid-body constraint, and
%   ft_compute_leadfield gained a coil model for MEG.
%
%   See also TRANSTOOLS.ENSUREFIELDTRIP, TRANSTOOLS.ISFIELDTRIPAVAILABLE.
    release = 'fieldtrip-20260924';
end
