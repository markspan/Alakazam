function sections = statisticalSections(blocks, ordinaryLabels, comboBins, plan)
%STATISTICALSECTIONS  Choose and build the statistical sections for a report.
%   SECTIONS = ReportSections.statisticalSections(BLOCKS, ORDINARYLABELS,
%   COMBOBINS, PLAN) returns a cell array of .qmd fragments, one per
%   (block x measure type x design) combination.
%
%   BLOCKS is a struct array of .label / .measureTypes (a window, or a
%   frequency label). ORDINARYLABELS are the plain bins, COMBOBINS the
%   difference/interaction ones with their recipe text, and PLAN is
%   reportDesignPlan's own settled account of which factors the recordings
%   actually support.
%
%   SHARED BY EVERY REPORT THAT ANALYSES MEASUREMENTS, which is the point.
%   The choice of test is a property of the DESIGN, not of what the numbers
%   happen to be measured from: one bin or two, within or between, one
%   session or several. A scalp-channel report and a source-region report
%   face exactly the same decision, so they must not each contain their own
%   copy of it -- the failure mode of two copies is not that one breaks, it
%   is that they drift and quietly answer the same question differently.
%
%   WHAT THE CHOICES ARE:
%     one bin              descriptive, or between-groups if there are groups
%     two bins, no groups  a paired t-test -- with exactly two conditions
%                          and no other factor it is the same comparison
%                          stated more simply, and it carries a Bayes factor
%                          and a Wilcoxon check an LMM section does not
%     otherwise            a linear mixed model; WHICH of the four designs
%                          (bin, bin x group, bin x session, or all three
%                          two-way) is read off PLAN inside lmmSection, not
%                          decided again here
%   plus one combination-bin section per combo bin, grouped or not.
%
%   See also LMMSECTION, PAIREDSECTION, DESCRIPTIVESECTION, BETWEENSECTION,
%   COMBOSECTION, COMBOSECTIONGROUPED, REPORTDESIGNPLAN.
    hasGroups  = ~isempty(plan.betweenFactors);
    useSession = numel(plan.withinFactors) > 1;
    useLmm     = hasGroups || useSession;

    sections = {};
    for bl = 1:numel(blocks)
        blockLabel = blocks(bl).label;
        types = blocks(bl).measureTypes;
        for ti = 1:numel(types)
            measureType = types{ti};

            if isscalar(ordinaryLabels)
                if hasGroups
                    sections{end + 1} = ReportSections.betweenSection(blockLabel, measureType, ordinaryLabels{1}); %#ok<AGROW>
                else
                    sections{end + 1} = ReportSections.descriptiveSection(blockLabel, measureType, ordinaryLabels{1}); %#ok<AGROW>
                end
            elseif numel(ordinaryLabels) == 2 && ~useLmm
                sections{end + 1} = ReportSections.pairedSection(blockLabel, measureType, ordinaryLabels{1}, ordinaryLabels{2}); %#ok<AGROW>
            elseif numel(ordinaryLabels) >= 2
                sections{end + 1} = ReportSections.lmmSection(blockLabel, measureType, ordinaryLabels, plan); %#ok<AGROW>
            end

            for cb = 1:numel(comboBins)
                if hasGroups
                    % includeVsZero: skip for latency/circular types, same
                    % reason as the no-groups path (isDescriptiveOnlyType).
                    % includeBetweenGroups: skip ONLY for circular types --
                    % unlike the "vs zero" test, an ordinary linear
                    % between-groups comparison (a latency IS on a linear
                    % scale) is perfectly valid for a latency combo bin,
                    % just not for a circular one (see isCircularType).
                    sections{end + 1} = ReportSections.comboSectionGrouped(blockLabel, measureType, ...
                        comboBins(cb).label, comboBins(cb).recipeText, ...
                        ~ReportSections.isDescriptiveOnlyType(measureType), ...
                        ~ReportSections.isCircularType(measureType)); %#ok<AGROW>
                else
                    sections{end + 1} = ReportSections.comboSection(blockLabel, measureType, ...
                        comboBins(cb).label, comboBins(cb).recipeText); %#ok<AGROW>
                end
            end
        end
    end
end
