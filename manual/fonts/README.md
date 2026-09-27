# Fonts for the PDF manual

The PDF manual is typeset in these fonts, which the Typst template
(`../_typst/typst-template.typ`) loads through `font-paths`, so the manual
looks the same on every machine that builds it, the release workflow
included.

| File | Font | Copyright | Version |
|---|---|---|---|
| `NotoSans-Regular.ttf`, `-Bold`, `-Italic`, `-BoldItalic` | Noto Sans | Copyright 2012 Google Inc. All Rights Reserved. | 1.06 |
| `NotoMono-Regular.ttf` | Noto Mono | Copyright 2007 Google Inc. All Rights Reserved. | 1.00 |

Both are licensed under the SIL Open Font License, Version 1.1, in
`OFL.txt`, which permits bundling them with software. The files were copied
unmodified from MATLAB R2026a
(`toolbox/shared/mlreportgen/dom/resources/fonts`), where they are the fonts
of MATLAB's own Report Generator.
