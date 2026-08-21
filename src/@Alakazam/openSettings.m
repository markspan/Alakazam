function openSettings(this)
%OPENSETTINGS  Open the global settings dialog (toolbar callback).
%   Applied changes refresh the open views via onSettingsChanged.
    SettingsDialog(@() this.onSettingsChanged());
end
