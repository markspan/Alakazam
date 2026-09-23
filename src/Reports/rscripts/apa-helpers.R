# ---- APA-style formatting helpers ----
# apa_p/apa_num both drop the leading zero APA convention omits for any
# statistic that cannot exceed 1 in magnitude (p, r, eta-squared, ...) --
# and, since the regex only matches a value that STARTS with "0.", leave a
# statistic that CAN exceed 1 (t, F, M, SD, ...) untouched, so one helper
# serves both without the caller having to say which kind of number it is.
# Vectorised (ifelse, not if): called on a single test statistic in most
# sections, but on a whole column at once (e.g. sig_pw$p.adj, one row per
# significant pair) when narrating pairwise comparisons -- a scalar if()
# on a length > 1 vector is a hard error as of R >= 4.2/4.3.
apa_p <- function(p) {
  ifelse(is.na(p), "= NA",
    ifelse(p < .001, "< .001",
      paste("=", sub("^0\\.", ".", sprintf("%.3f", p)))))
}
apa_num <- function(x, digits = 2) {
  ifelse(is.na(x), "NA",
    sub("^(-?)0\\.", "\\1.", sprintf(paste0("%.", digits, "f"), x)))
}
# A three-line APA table (rule above the header, rule below it, rule at the
# foot; no vertical rules) via gt, printed with as_raw_html() so it can be
# emitted from inside a per-channel for loop in a results:"asis" chunk --
# gt's own auto-print only works for a table that is a chunk's sole,
# top-level, unassigned result, which a table built inside a loop never is.
# Numeric columns that happen to be whole numbers everywhere (n, df, ...)
# are formatted with 0 decimals, not 3 -- APA never shows a sample size or
# degrees of freedom as e.g. "10.000".
apa_gt <- function(df, title = NULL) {
  is_whole <- function(x) is.numeric(x) && all(x == round(x), na.rm = TRUE)
  int_cols <- names(df)[sapply(df, is_whole)]
  dec_cols <- setdiff(names(df)[sapply(df, is.numeric)], int_cols)
  tbl <- gt(df)
  if (!is.null(title)) tbl <- tab_header(tbl, title = title)
  if (length(dec_cols) > 0) tbl <- tbl %>% fmt_number(columns = all_of(dec_cols), decimals = 3)
  if (length(int_cols) > 0) tbl <- tbl %>% fmt_number(columns = all_of(int_cols), decimals = 0)
  tbl %>%
    tab_options(
      table.border.top.style = "solid", table.border.top.width = px(1.5), table.border.top.color = "black",
      table.border.bottom.style = "solid", table.border.bottom.width = px(1.5), table.border.bottom.color = "black",
      column_labels.border.bottom.style = "solid", column_labels.border.bottom.width = px(1), column_labels.border.bottom.color = "black",
      table_body.hlines.style = "none", table.border.left.style = "none", table.border.right.style = "none",
      column_labels.font.weight = "bold", table.font.size = px(13), heading.align = "left"
    )
}

# Render an empty cell as empty, rather than as the letters "NA".
# For a table whose columns apply to some rows and not others -- a
# per-step provenance table is the case in hand -- "NA" reads as a
# measurement that went missing, when what it means is that the
# column does not apply to that row. Opt in per table: elsewhere an
# NA really is a failed measurement and should be visible as one.
blank_missing <- function(tbl) sub_missing(tbl, columns = everything(), missing_text = "")

# ---- one figure look, shared by every report ----
# Named rather than repeated: the same role had three different reds and
# two blues across the sections, which reads as carelessness before a
# reader reaches the numbers.
alz_blue  <- "#4a7fc9"
alz_red   <- "#c1272d"
alz_grey  <- "#5b6670"
alz_light <- "#f2f6fa"

# Data plots, following APA 7 figure style as far as a theme can.
#
# WHAT APA ACTUALLY ASKS FOR, and what each line here is doing about it:
#   a sans-serif face, 8 to 14 pt, one size throughout   -> base_family, base_size
#   axis lines only, no border and no gridlines          -> theme_classic, panel.grid
#   black lines and black text                           -> colour = "black" below
#   shading kept light, so it prints and greyscales well -> strip.background
#   a legend with no box or key background               -> legend.key/background
#   white throughout, so it prints on white              -> plot/panel background
#
# THE FACET STRIP IS A DELIBERATE DEPARTURE, and the one place these
# figures keep a colour APA would rather they did not. What APA actually
# objects to is heavy shading: a saturated fill with bold white text on it,
# which is what these reports used to draw and which greyscales into a
# black bar. A pale tint with ordinary black text keeps the blue the app
# is recognisable by, stays legible printed in greyscale, and reads as a
# panel label rather than a banner. Nine of the report figures are
# faceted, so this is the choice that shows most.
#
# BUILT ON theme_classic, WHICH IS ggplot2 ITSELF, not on ggpubr theme_pubr
# despite that being the publication theme already in use in one report.
# This block is loaded by ALL THREE report generators, and only the
# statistical one installs ggpubr: the cluster and data-quality reports
# load tidyverse and gt alone, so a theme reaching for theme_pubr would
# leave every figure in two of the three reports undefined.
#
# WHAT A THEME CANNOT DO is the rest of APA figure style: a numbered
# "Figure 1" above in bold, an italic title under it, and a Note beneath
# defining any abbreviation and saying what the error bars are. Those are
# document furniture rather than plot furniture, and most of these figures
# are printed from inside a results=asis loop where Quarto cannot number
# them. The prose around each figure carries that information instead.
alz_theme <- function(base_size = 11, base_family = "sans") {
  theme_classic(base_size = base_size, base_family = base_family) +
    theme(
      text = element_text(colour = "black"),
      axis.text = element_text(colour = "black", size = base_size - 1),
      axis.title = element_text(colour = "black", size = base_size),
      axis.line = element_line(colour = "black", linewidth = 0.4),
      axis.ticks = element_line(colour = "black", linewidth = 0.4),
      panel.grid = element_blank(),
      panel.background = element_rect(fill = "white", colour = NA),
      plot.background = element_rect(fill = "white", colour = NA),
      strip.background = element_rect(fill = alz_light, colour = NA),
      strip.text = element_text(colour = "black", size = base_size, hjust = 0,
                                margin = margin(3, 4, 3, 4)),
      legend.key = element_blank(),
      legend.background = element_blank(),
      legend.title = element_text(colour = "black", size = base_size - 1),
      legend.text = element_text(colour = "black", size = base_size - 1),
      plot.title = element_text(size = base_size, face = "plain", colour = "black"),
      plot.caption = element_text(size = base_size - 2, colour = alz_grey, hjust = 0),
      plot.margin = margin(4, 8, 4, 4)
    )
}

# Rasters and topographies. The same APA choices, minus the axis lines:
# a filled plane is bounded by its own edge, and drawing an axis line over
# it adds a second boundary a reader has to ignore. A grid over a filled
# plane is noise rather than a reading aid, so it goes too.
alz_theme_map <- function(base_size = 10, base_family = "sans") {
  theme_minimal(base_size = base_size, base_family = base_family) +
    theme(
      text = element_text(colour = "black"),
      panel.grid = element_blank(),
      panel.background = element_rect(fill = "white", colour = NA),
      plot.background = element_rect(fill = "white", colour = NA),
      strip.background = element_rect(fill = alz_light, colour = NA),
      strip.text = element_text(colour = "black", size = base_size, hjust = 0,
                                margin = margin(3, 4, 3, 4)),
      legend.key = element_blank(),
      legend.background = element_blank(),
      plot.title = element_text(size = base_size, face = "plain", colour = "black"),
      plot.subtitle = element_text(size = base_size - 1, colour = alz_grey, hjust = 0),
      axis.text = element_text(colour = "black", size = base_size - 2),
      axis.title = element_text(colour = "black", size = base_size),
      axis.ticks = element_line(colour = "black", linewidth = 0.3),
      legend.title = element_text(colour = "black", size = base_size - 1),
      legend.text = element_text(colour = "black", size = base_size - 1),
      plot.margin = margin(4, 8, 4, 4)
    )
}
