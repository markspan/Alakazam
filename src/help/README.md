# help

The **Help** button shows the manual. Its text lives in [`manual/`](../../manual)
(Quarto), not here; this folder holds the tool that makes the manual's
pictures, and the script that makes its worked example's numbers.

## Where the help page comes from

The page the Help button opens is the rendered manual,
`manual/manual.html`, copied to `src/AlakazamHelp.html` and adapted for the
app's `uihtml` viewer by `buildHelpPageInto` (`src/Support/`): stylesheets and
scripts that Quarto delivers as `data:` URIs are inlined, since the viewer's
content-security policy refuses them, and links that leave the page are
handed to MATLAB, which opens them in the real browser.

Neither HTML file is in version control, since each embeds every figure
(the PDF, `manual/manual.pdf`, is). A release ships the rendered manual, so
there the page is a copy. On a working
copy the Help button renders the manual with Quarto (bundled with RStudio)
when it is missing or older than its sources, which takes a couple of
minutes; without Quarto it offers the PDF manual or `README.MD` instead (see
`Alakazam.offerManualInstead`). To render it by hand:

```
cd manual
quarto render manual.qmd --to html     # manual.html, what Help shows
quarto render manual.qmd --to typst    # manual.pdf
```

`DEVELOPER.md` describes the manual's sources and the PDF's design.

## capture/

Every picture in `manual/images/` is regenerated from the running
application by `captureManualImages`, from the list in `manualShots`: which
dataset, which transformation or view, and which settings each picture
shows. Nothing real is touched: each dataset is copied into a scratch
workspace of its own, and dialogs are caught by a timer, exported and
cancelled.

Run it from the repository root, with the datasets in `DATA.md` in place:

```matlab
addpath('src/help/capture');
captureManualImages();                              % all of them
captureManualImages('Only', {'filter-dialog'});     % one
captureManualImages('Datasets', {'rift'});          % one dataset's
```

A picture that is added to or dropped from the manual belongs in
`manualShots` as well; `ManualTest` fails when the two disagree.

## examples/

`reproduceN400Example` reruns chapter 20's worked example from the template
to the report: `N400.alztemplate` on Luck's ten chapter 3 recordings, then
the measurements export and the statistics report as **ERP & Report** writes
them. Every number the chapter quotes comes from that report, so when a
change moves them, which `LibraryReplayTest` reports as a failure, this is
how the chapter is brought up to date. It writes into a folder of its own
(under `tempdir` unless `'Output'` says otherwise) and touches no workspace:

```
addpath('src/help/examples'); reproduceN400Example();
```
