function showTransformationError(this, transformId, ME)
%SHOWTRANSFORMATIONERROR  Calm, explanatory report of a failed
%   transformation, instead of MATLAB's default raw stack trace.
%   A failed transformation is almost always a data-format mismatch
%   (this dataset is not yet segmented / averaged / in the frequency
%   domain, whichever this step needs) rather than a real crash --
%   the previous handler already showed a dialog with ME.message but
%   then rethrew ME anyway, which is what dumped the full stack
%   trace to the command window on top of it. There is nothing left
%   to rethrow to: this is the top of the callback chain from the
%   ribbon, so swallowing it here (after informing the user) is the
%   right place to stop it.
    reason = ME.message;
    % Every Alakazam-authored guard clause writes 'Problem in
    % <Transform>: ...'; that prefix is redundant once the dialog's
    % own title already names the transform, so strip it for a
    % cleaner read. A plain MATLAB error (no such prefix, e.g. an
    % unguarded shape mismatch inside a transformation with no
    % explicit data-format check of its own) is shown as-is.
    prefix = sprintf('Problem in %s: ', transformId);
    if startsWith(reason, prefix)
        reason = extractAfter(reason, prefix);
    end

    message = { ...
        sprintf('I''m sorry, but %s could not run on this dataset:', transformId), ...
        '', ...
        reason};
    if ~startsWith(ME.identifier, 'Alakazam:')
        % An unguarded, "native" MATLAB error -- almost always still
        % a data-format mismatch in practice (this step expects a
        % shape the current dataset doesn't have), so add the same
        % general hint an explicit guard clause would have given.
        message{end + 1} = '';
        message{end + 1} = ['This usually means the selected dataset is not quite the ' ...
            'right kind of data for this step -- for example, it may need segmented ' ...
            '(epoched) data, an average, or frequency-domain data, and this ' ...
            'dataset is not yet in that form.'];
    end

    uialert(this.MainFigure, message, sprintf('Couldn''t run %s', transformId), ...
        'Icon', 'warning');
end
