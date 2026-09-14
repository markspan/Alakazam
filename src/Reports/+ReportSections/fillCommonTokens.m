function text = fillCommonTokens(text, windowLabel, measureType, bin1, bin2)
%FILLCOMMONTOKENS  Substitute the tokens every section shares (WINDOW,
%   MEASURETYPE, BIN1, BIN2), each in both its _MD and _R form.
    text = ReportSections.fillToken(text, 'WINDOW', windowLabel);
    text = ReportSections.fillToken(text, 'MEASURETYPE', measureType);
    text = ReportSections.fillToken(text, 'BIN1', bin1);
    text = ReportSections.fillToken(text, 'BIN2', bin2);
end

