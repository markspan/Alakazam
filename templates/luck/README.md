# Luck chapter templates

One ready-made pipeline per chapter of Luck's *Applied ERP Data Analysis*,
named chapter-first so a file dialog lists them in the book's own order.

Apply one with **Apply template** on a raw or preprocessed node: it rebuilds
that chapter's whole chain (bins, baseline, artefact rejection, averaging,
measurement, and where the chapter uses them a filter, an ICA correction or a
derived lateral channel). Grand Average and the statistics are tab actions
rather than template steps, so a template stops at the last per-subject node.

Nothing in a template names a file, so each applies to whichever dataset the
branch you drop it on already holds. **The recordings themselves are not in
this repository** (`Data/` is gitignored): run
[`downloadLuckData.m`](../../downloadLuckData.m) in the repository root
first, then open that chapter's `.wksp`.

What each one does, what it measures on subject 1, and where its numbers were
checked against the book and against ERPLAB: see
[`Docs/luck.md`](../../Docs/luck.md#a-template-per-chapter-in-templatesluck).
