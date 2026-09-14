function line = zeroLineStatement(includeVsZero)
%ZEROLINESTATEMENT  An R statement assigning ZERO_LINE to the ggplot
%   dashed-zero-line reference layer when a "vs zero" test actually ran
%   (matching comboSection's own unconditional geom_hline -- there is
%   always a "vs zero" test there, since it is only ever called for a
%   non-descriptive-only measure type), or to NULL otherwise -- `p + NULL`
%   is a documented ggplot2 no-op, so the plot built from COMMON_LAYERS
%   below can unconditionally include `zero_line` without needing its own
%   INCLUDEVSZERO branch.
    if includeVsZero
        line = '  zero_line <- geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50")';
    else
        line = '  zero_line <- NULL';
    end
end

