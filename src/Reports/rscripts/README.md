# Report templates

The R and Quarto that Alakazam's reports are made of. A generator in
`src/Reports/` decides *which* of these go into a document and fills their
placeholders; the files themselves hold the text that reaches the report,
unchanged.

Read them with `ReportDoc.template('name')`, splice them into a section's
list of lines with `ReportDoc.lines({...})`. Both have headers explaining
themselves.

## Two kinds of file

| Extension | What it is | Checked by |
|---|---|---|
| `.R` | Pure R: a library of functions, or a whole chunk body. Valid R on its own. | `ReportTemplatesTest/everyRTemplateParsesAsR` hands each one to R's own `parse()` |
| `.Rpart` | An R *fragment*: it opens a brace its section closes, or stops mid-expression, so no parser takes it alone. | `QuartoReportRSyntaxTest`, which parses the chunks of the assembled document |
| `.qmd` | A Quarto fragment: markdown prose, ```` ```{r} ```` fences and R together, which is the natural unit for a whole section. | `QuartoReportRSyntaxTest`, as above |

The three extensions are a promise about the file, not decoration: `.R` means
"hand me to R and I will parse". Two files started as `.R` and turned out to
be fragments, which is how `.Rpart` came to exist rather than by relaxing the
parse test.

## Placeholders

A template may carry `__TOKEN__` placeholders, which the section builder
fills afterwards (`ReportSections.fillToken`, or `strrep` for the one-off
ones). The tokens are the interface between what MATLAB decides and what the
template says, so a template is readable on its own and a generator stays
responsible for every value that depends on the data.

Escaping is the caller's job, as it always was: a value going into an R
string literal passes through `ReportSections.rLit`, one going into markdown
prose through `mdLit`. A template cannot know which of the two a placeholder
of its own is.

## Two rules

**Nothing is added when a template is read.** What the file holds is what the
report gets, so these files carry no header comment of their own: a comment
here would appear in every report made from it. This README is the
explanation instead.

**Templates are inlined at generation, never sourced at render.** A report is
one `.qmd` that reads its own sibling CSVs and nothing else, so a report
exported last year still renders without the repository that made it. If the
document said `source("...")` instead, every exported report would depend on
the vintage of the tree it came from, which is the opposite of what a record
is for.

## Adding one

1. Write the file here, `.R` if it is pure R and `.qmd` if it carries prose
   or fences.
2. Read it where the lines used to sit: `ReportDoc.template('my-thing.R')`,
   inside `ReportDoc.lines({ ... })`.
3. `runtests('tests/ReportTemplatesTest.m')` checks that the name resolves
   and, where R is installed, that an `.R` file parses.

A template that nothing asks for fails `everyTemplateIsAskedFor`, so a
generator and its templates cannot drift apart unnoticed.
