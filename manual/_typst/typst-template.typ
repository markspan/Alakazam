// Alakazam manual: the Typst page design for the PDF.
//
// Replaces Quarto's default typst-template.typ partial (see manual.qmd,
// template-partials). It keeps the default's article() signature, so
// Quarto's own typst-show.typ calls it unchanged, and draws the manual in
// the application's own look: the colours of the ribbon and the dialogs
// (src/AlakazamRibbon.html, the dialogs' title bars) and Noto Sans, the
// font MATLAB's Report Generator ships (fonts/, loaded by font-paths).

// ---- The application's colours -------------------------------------------
#let alz-accent  = rgb("#4a7fc9")   // Alakazam tab, every dialog's title bar
#let alz-tools   = rgb("#6fa8dc")   // Tools tab
#let alz-navy    = rgb("#2e5c8a")   // Grand Average tab, ribbon group labels
#let alz-report  = rgb("#3f6fa8")   // Export/Report tab
#let alz-active  = rgb("#4472c4")   // the active tab's underline
#let alz-surface = rgb("#f5f5f5")   // the uifigure window background
#let alz-text    = rgb("#1f2a37")   // body text, a blue-leaning near-black
#let alz-muted   = rgb("#5a6b7d")   // captions, running heads
#let alz-rule    = rgb("#d5dfeb")   // hairlines
#let alz-zebra   = rgb("#f2f6fb")   // alternate table rows
#let alz-tint    = rgb("#e8f0fa")   // inline code

#let alz-sans = ("Noto Sans",)
#let alz-mono = ("Noto Mono",)

// A chapter opening: the dialog title bar, a blue block with white bold
// text, over a navy strip like the ribbon's group labels.
#let alz-banner(title, number: none) = block(width: 100%, breakable: false, above: 0pt, below: 11mm)[
  #if number != none {
    text(size: 8.5pt, weight: "bold", fill: alz-accent, tracking: 0.14em)[CHAPTER #number]
    v(2.2mm)
  }
  #block(width: 100%, fill: alz-accent, inset: (x: 6mm, top: 5mm, bottom: 5mm), below: 0pt)[
    #set par(justify: false, leading: 0.45em)
    #text(size: 21pt, weight: "bold", fill: white)[#title]
  ]
  #block(width: 100%, height: 1.6mm, fill: alz-navy, above: 0pt)
]

// Code blocks, redrawn. Quarto highlights code as a run of inline raw
// tokens (NormalTok, StringTok, ...) ending each line in EndLine(), a raw
// newline, so the inline-code style below must not reach inside a block:
// boxing each token, the newline among them, runs the lines together. The
// state marks the stretch inside a block; it replaces Quarto's Skylighting,
// which is defined before this partial.
#let alz-in-code = state("alz-in-code", false)
#let Skylighting(fill: none, number: false, start: 1, sourcelines) = {
  let blocks = []
  let lnum = start - 1
  for ln in sourcelines {
    if number {
      lnum = lnum + 1
      blocks = blocks + box(width: 24pt, text(fill: alz-muted, [#lnum]))
    }
    blocks = blocks + ln + EndLine()
  }
  alz-in-code.update(true)
  block(
    width: 100%, fill: alz-surface, inset: (left: 10pt, rest: 8pt),
    radius: (right: 2pt), stroke: (left: 2.5pt + alz-tools),
    { set par(justify: false); set text(size: 9.4pt); blocks },
  )
  alz-in-code.update(false)
}

// Syntax colours in the application's blues rather than Quarto's defaults,
// with a warm tone kept for literals so they still stand out.
#let NormalTok(s) = text(fill: alz-text, raw(s))
#let FunctionTok(s) = text(fill: alz-accent, raw(s))
#let KeywordTok(s) = text(fill: alz-navy, weight: "bold", raw(s))
#let ControlFlowTok(s) = text(fill: alz-navy, weight: "bold", raw(s))
#let DataTypeTok(s) = text(fill: alz-report, raw(s))
#let StringTok(s) = text(fill: rgb("#8a5a12"), raw(s))
#let DecValTok(s) = text(fill: rgb("#8a5a12"), raw(s))
#let FloatTok(s) = text(fill: rgb("#8a5a12"), raw(s))
#let CommentTok(s) = text(fill: alz-muted, style: "italic", raw(s))
#let OperatorTok(s) = text(fill: alz-muted, raw(s))

// Quarto's callouts, redrawn: a pale panel with a coloured edge. The edge
// keeps the callout type's own colour (a warning still reads as one); the
// panel and the title follow the manual's palette.
#let callout(body: [], title: "Callout", background_color: rgb("#dddddd"), icon: none, icon_color: black, body_background_color: white) = {
  block(
    breakable: false,
    width: 100%,
    fill: alz-zebra,
    stroke: (left: 2.5pt + icon_color),
    inset: (left: 10pt, right: 10pt, top: 8pt, bottom: 8pt),
    radius: (right: 2pt),
  )[
    #text(weight: "bold", fill: alz-navy)[#if icon != none [#text(icon_color)[#icon] ]#title]
    #if body != [] { v(3pt); body }
  ]
}

#let article(
  title: none,
  subtitle: none,
  authors: none,
  keywords: (),
  date: none,
  abstract-title: none,
  abstract: none,
  thanks: none,
  cols: 1,
  lang: "en",
  region: "GB",
  font: none,
  fontsize: 10pt,
  title-size: 1.5em,
  subtitle-size: 1.25em,
  heading-family: none,
  heading-weight: "bold",
  heading-style: "normal",
  heading-color: black,
  heading-line-height: 0.65em,
  mathfont: none,
  codefont: none,
  linestretch: 1,
  sectionnumbering: none,
  linkcolor: none,
  citecolor: none,
  filecolor: none,
  toc: false,
  toc_title: none,
  toc_depth: none,
  toc_indent: 1.5em,
  doc,
) = {
  set document(title: title, keywords: keywords)

  // ---- Type ----------------------------------------------------------------
  set text(font: alz-sans, size: fontsize, fill: alz-text, lang: lang, region: region)
  set par(justify: false, leading: 0.68em * linestretch, spacing: 1.05em)
  show raw: set text(font: alz-mono, size: 0.9em)
  show raw.where(block: true): set block(
    width: 100%, fill: alz-surface, inset: (left: 10pt, rest: 8pt),
    radius: (right: 2pt), stroke: (left: 2.5pt + alz-tools),
  )
  show raw.where(block: false): it => context {
    if alz-in-code.get() { it } else {
      box(fill: alz-tint, inset: (x: 2.5pt, y: 0pt), outset: (y: 2.5pt), radius: 2pt, it)
    }
  }
  show strong: set text(fill: alz-navy)
  show link: set text(fill: alz-accent)
  show ref: set text(fill: alz-accent)
  set list(marker: text(fill: alz-accent)[•], indent: 2pt, body-indent: 6pt)
  set enum(indent: 2pt, body-indent: 6pt)

  // ---- Headings ------------------------------------------------------------
  set heading(numbering: sectionnumbering)
  // Figures and tables numbered per chapter (Figure 3.2), as in the HTML
  // (crossref: chapters), which Quarto's Typst output does not do itself.
  set figure(numbering: n => numbering("1.1", counter(heading).get().first(), n))
  show heading.where(level: 1): it => {
    pagebreak(weak: true)
    counter(figure.where(kind: "quarto-float-fig")).update(0)
    counter(figure.where(kind: "quarto-float-tbl")).update(0)
    v(6mm)
    let number = if it.numbering != none { counter(heading).display("1") } else { none }
    alz-banner(it.body, number: number)
  }
  show heading.where(level: 2): it => block(above: 1.9em, below: 0.85em, breakable: false, sticky: true)[
    #set text(size: 13.5pt, weight: "bold", fill: alz-navy)
    #if it.numbering != none [#text(fill: alz-accent)[#counter(heading).display()]#h(0.55em)]#it.body
  ]
  show heading.where(level: 3): it => block(above: 1.5em, below: 0.7em, breakable: false, sticky: true)[
    #set text(size: 11pt, weight: "bold", fill: alz-accent)
    #if it.numbering != none [#counter(heading).display()#h(0.5em)]#it.body
  ]
  show heading.where(level: 4): it => block(above: 1.2em, below: 0.6em, sticky: true)[
    #set text(size: 10pt, weight: "bold", fill: alz-navy)
    #it.body
  ]

  // ---- Tables: a navy header row, like the ribbon's group labels ----------
  set table(
    stroke: (x, y) => (bottom: 0.5pt + alz-rule),
    inset: (x: 6pt, y: 4.5pt),
    fill: (x, y) => if y == 0 { alz-navy } else if calc.even(y) { alz-zebra } else { none },
  )
  // Cells left-aligned: Pandoc gives every column "auto", which inherits
  // the centring of the figure the table sits in.
  show table: set align(start)
  show table: set text(size: 8.8pt)
  show table: set par(leading: 0.55em)
  show table.cell.where(y: 0): set text(fill: white, weight: "bold")
  show table.cell.where(y: 0): set par(justify: false)

  // ---- Figures -------------------------------------------------------------
  show image: it => box(stroke: 0.6pt + alz-rule, it)
  show figure: set block(breakable: false, above: 1.4em, below: 1.4em)
  show figure.caption: it => {
    set text(size: 8.4pt, fill: alz-muted)
    set par(justify: false, leading: 0.55em)
    block(width: 100%, inset: (x: 2pt))[
      #text(weight: "bold", fill: alz-accent)[#it.supplement #context it.counter.display(it.numbering)]#it.separator#it.body
    ]
  }

  // ---- Pages ---------------------------------------------------------------
  set page(
    paper: "a4",
    margin: (top: 26mm, bottom: 22mm, x: 22mm),
    header: context {
      let here-page = here().page()
      let openings = query(heading.where(level: 1))
      if openings.any(o => o.location().page() == here-page) { return }
      let before = query(heading.where(level: 1).before(here()))
      if before.len() == 0 { return }
      let chapter = before.last()
      set text(size: 7.8pt, fill: alz-muted)
      grid(
        columns: (1fr, auto),
        [#text(weight: "bold", fill: alz-accent)[Alakazam] #h(0.3em) user manual],
        [#if chapter.numbering != none [#counter(heading).at(chapter.location()).first()#h(0.5em)]#chapter.body],
      )
      v(-1.2mm)
      line(length: 100%, stroke: 0.5pt + alz-rule)
    },
    footer: context {
      set text(size: 8pt)
      grid(
        columns: (1fr, auto),
        [],
        box(fill: alz-accent, inset: (x: 5pt, y: 3pt), radius: 1.5pt)[
          #text(fill: white, weight: "bold")[#counter(page).display()]
        ],
      )
    },
  )

  // ---- Cover ---------------------------------------------------------------
  if title != none {
    page(margin: 0pt, header: none, footer: none, fill: alz-surface)[
      // The ribbon's tab row, the Alakazam tab active.
      #place(top + left, dx: 22mm, dy: 14mm)[
        #set text(size: 7.2pt, weight: "bold")
        #stack(dir: ltr, spacing: 0pt,
          box(fill: alz-surface, inset: (x: 7pt, y: 5pt), stroke: (bottom: 1.6pt + alz-active))[#text(fill: rgb("#333333"))[ALAKAZAM]],
          box(fill: alz-tools, inset: (x: 7pt, y: 5pt))[#text(fill: white)[TOOLS]],
          box(fill: alz-navy, inset: (x: 7pt, y: 5pt))[#text(fill: white)[GRAND AVERAGE]],
          box(fill: alz-report, inset: (x: 7pt, y: 5pt))[#text(fill: white)[EXPORT/REPORT]],
        )
      ]
      // The title, on a dialog's title bar.
      #place(top + left, dy: 30mm)[
        #block(width: 210mm, fill: alz-accent, inset: (x: 22mm, top: 13mm, bottom: 12mm), below: 0pt)[
          #set par(justify: false, leading: 0.4em)
          #text(size: 46pt, weight: "bold", fill: white)[#title]
          #if subtitle != none {
            v(5mm)
            text(size: 14pt, fill: white)[#subtitle]
          }
        ]
        #block(width: 210mm, height: 2.4mm, fill: alz-navy, above: 0pt)
      ]
      // The program itself.
      #place(top + left, dx: 22mm, dy: 104mm)[
        #block(width: 166mm)[#image("images/ui-main.jpg", width: 100%)]
      ]
      #place(bottom + left, dx: 22mm, dy: -20mm)[
        #set text(size: 9pt, fill: alz-muted)
        #text(weight: "bold", fill: alz-navy)[An interactive MATLAB workbench for EEG and ERP analysis] \
        #if date != none [#date #h(0.6em) · #h(0.6em)]github.com/markspan/Alakazam
      ]
    ]
  }

  // ---- Contents ------------------------------------------------------------
  if toc {
    page(header: none, footer: none)[
      #v(6mm)
      #alz-banner(if toc_title == none [Contents] else { toc_title })
      #show outline.entry.where(level: 1): it => {
        v(0.95em, weak: true)
        text(weight: "bold", fill: alz-navy)[#it]
      }
      #show outline.entry.where(level: 2): set text(size: 9.2pt)
      #outline(title: none, depth: toc_depth, indent: 1.4em)
    ]
    counter(page).update(1)
  }

  doc
}
