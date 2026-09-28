function showImageData(img, data)
%SHOWIMAGEDATA  Draw DATA in the image IMG, with its NaN cells left blank.
%   showImageData(IMG, DATA) sets IMG's CData to DATA and makes every NaN
%   cell transparent, so it shows as a gap in the axes' own background.
%
%   AN IMAGE DRAWS NaN AS ITS LOWEST COLOUR. Left alone, a missing value
%   looks like a real minimum: a rejected trial in an ERP image like a trial
%   at the most negative voltage, a time-frequency cell whose trials were
%   all rejected like the strongest decrease, a coherence cell outside a
%   method's band like no coherence at all. EpochView fixed this for the ERP
%   image first (manual issue M6), and TimeFrequencyView and CoherenceView
%   had the same problem (M7); all three draw through here, so the rule is in
%   one place.
%
%   See also EPOCHVIEW, TIMEFREQUENCYVIEW, COHERENCEVIEW.
    img.CData = data;
    img.AlphaData = double(~isnan(data));
    img.AlphaDataMapping = 'none';
end
