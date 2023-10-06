d = AlakazamInst.Workspace.EEG;
data = d.data(:);
halfway = mean([max(data), min(data)]);
dist =  abs(data - halfway);
[peaks, indices] = findpeaks(-dist,'Npeaks',176, "MinPeakDistance",950);
indices = indices(2:end);

for b = 0:7
    indices([1+(b*22)]) = nan;
end

idx = indices(~isnan(indices));
idx = idx(1:end-1)

stimevents = d.event(strcmpi({d.event.code},'Stimulus'));
idxevt = [stimevents.latency]';

difference = idx-idxevt;
dat = table(idx, idxevt, difference);

