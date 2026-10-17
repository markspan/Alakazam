function openInBrowser(url)
%OPENINBROWSER  Open URL in the system's web browser; anything but an http or
%   https address is ignored. Falls back to MATLAB's own browser where the
%   system's cannot be reached.
%
%   The manuals' ? buttons, the Manual button of Install plugins and the
%   help page's outside links all open through here, so a test can stand in
%   for it and no test opens a browser.
%
%   See also MANUALADDRESS.
    url = char(string(url));
    if isempty(regexp(url, '^https?://', 'once'))
        return;
    end
    try
        web(url, '-browser');
    catch
        web(url);
    end
end
