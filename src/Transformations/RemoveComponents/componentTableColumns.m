function [colNames, colFmt, colEdit, data] = componentTableColumns(classes, probs, dipoleRv)
%COMPONENTTABLECOLUMNS  The component selector's table, built from an ICLabel
%   classification. Returns the uitable property values
%   RemoveComponentsDialog sets: COLNAMES/COLFMT/COLEDIT (1 x nCol) and DATA
%   (nComp x nCol cell).
%
%   CLASSES is ICLabel's class list (1 x C cellstr, e.g. Brain, Muscle, Eye,
%   ...), PROBS its nComp x C probability matrix, and DIPOLERV an optional
%   per-component dipole residual variance in 0..1 (NaN where no dipole could
%   be fitted). Columns are:
%
%     IC | Label | <one per class, %> | Dipole RV % | Remove
%
%   THE LABEL COLUMN IS THE VERDICT, the class ICLabel actually assigned --
%   its argmax, which is what ICLabel itself means by a component's label.
%   The per-class probabilities are kept beside it rather than replaced by it:
%   a 88% Eye and a 38%-Eye-34%-Brain both label as "Eye", and only the
%   probabilities distinguish them. But a table of seven numeric columns has
%   to be read a row at a time, taking the argmax by eye, which is precisely
%   the work the classifier already did. So: the verdict to scan and sort by,
%   the numbers to check it against.
%
%   Separated from the dialog, rather than built inline where it is used,
%   because this is the part with decisions in it (what to call an
%   unclassified component, where the verdict column sits, how a failed
%   dipole fit reads) and a uifigure callback is not somewhere those can be
%   tested.
%
%   See also REMOVECOMPONENTSDIALOG, COMPONENTSTICKED,
%   TRANSTOOLS.COMPONENTDIPOLES.
    classes = cellfun(@(c) char(string(c)), classes(:)', 'UniformOutput', false);
    nComp   = size(probs, 1);

    if nargin < 3 || isempty(dipoleRv)
        dipoleRv = nan(nComp, 1);
    end
    dipoleRv = dipoleRv(:);
    dipoleRv(end + 1:nComp) = NaN;

    % A CHAR COLUMN for Dipole RV, so that "no fit" can be said rather than
    % left blank. Measured on a 63-component decomposition, dipfit fits about
    % 57% of components and the rest fail outright. An empty cell reads as
    % missing data; it is not. A component no single dipole can be fitted to
    % at all is the strongest evidence available here that it is not one
    % cortical source, which is more than a high residual variance says.
    colNames = [{'IC'}, {'Label'}, classes, {'Dipole RV %'}, {'Remove'}];
    colFmt   = [{'numeric'}, {'char'}, repmat({'numeric'}, 1, numel(classes)), ...
                {'char'}, {'logical'}];
    colEdit  = [false, false, false(1, numel(classes)), false, true];

    % A classification need not be as wide as the class list (an older
    % ICLabel, a hand-built struct): those classes have no probability, and
    % blank says that where a 0 would claim the component was measured and
    % found not to be one.
    nReported = size(probs, 2);
    data = cell(nComp, numel(colNames));
    for c = 1:nComp
        data{c, 1} = c;
        data{c, 2} = componentLabel(classes, probs(c, :));
        for k = 1:numel(classes)
            if k <= nReported
                data{c, 2 + k} = percentCell(probs(c, k));
            else
                data{c, 2 + k} = [];
            end
        end
        if isnan(dipoleRv(c))
            data{c, end - 1} = 'no fit';
        else
            data{c, end - 1} = sprintf('%d', round(dipoleRv(c) * 100));
        end
        data{c, end} = false;
    end
end

% ----------------------------------------------------------------------- %
function label = componentLabel(classes, row)
%COMPONENTLABEL  "Eye 88%", or "unclassified" when there is no verdict to
%   report. A component whose probabilities are all NaN (or absent, on a
%   classification with fewer rows than components) has not been classified,
%   and naming whichever class happens to sort first would present the
%   argmax of nothing as a decision.
    row = double(row(:)');
    if isempty(row) || isempty(classes) || ~any(isfinite(row))
        label = 'unclassified';
        return;
    end
    % max ignores NaN of its own accord, and the all-NaN case is already
    % handled above, so no nanflag is needed (and none is passed: the
    % 'omitnan' option on max postdates the MATLAB releases this app still
    % has to run under).
    [p, top] = max(row);
    if top > numel(classes)
        label = 'unclassified';
        return;
    end
    label = sprintf('%s %d%%', classes{top}, round(p * 100));
end

function cell_ = percentCell(v)
%PERCENTCELL  A 0..1 probability as whole-number percent, or empty when
%   there is none: under a 'numeric' ColumnFormat an empty cell renders
%   blank, which is what "no value" should look like.
    if isempty(v) || ~isfinite(v)
        cell_ = [];
    else
        cell_ = round(double(v) * 100);
    end
end
