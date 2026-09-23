# The violin distribution layer every per-channel plot below uses. FILL,
# when given, is a literal colour for a single-distribution plot; omitted
# (NULL) so the violin instead inherits the plot's own colour/fill
# aesthetic (e.g. aes(colour = group, fill = group)) for a multi-group plot.
# A RAINCLOUD, not a bare violin. The violin used to sit directly
# behind the individual points, so the density and the observations
# that produced it obscured each other and neither could be read. Here
# the density and a narrow box are nudged aside, leaving the points
# clear: distribution, quartiles and raw data at once, which is what
# lets a reader see bimodality or a single subject carrying an effect.
violin_layers <- function(fill = NULL, nudge = 0.17) {
  shape <- list(alpha = 0.15, trim = FALSE, linewidth = 0.4, width = 0.5,
                position = position_nudge(x = nudge))
  box <- list(alpha = 0.25, width = 0.09, outlier.shape = NA, linewidth = 0.4,
              position = position_nudge(x = nudge))
  if (!is.null(fill)) {
    shape <- c(shape, list(fill = fill, colour = fill))
    box <- c(box, list(fill = fill, colour = fill))
  }
  list(do.call(geom_violin, shape), do.call(geom_boxplot, box))
}

# ---- Bayes factors, beside every t-test ----
# The reading guide at the top of this report promised these for years
# while no section computed one, and the BayesFactor package had even
# dropped out of the setup chunk above. They are here because a
# non-significant p cannot tell "no effect" from "not enough data to
# say", and a Bayes factor can: BF10 above 1 favours a difference, below
# 1 favours its absence.
#
# The default JZS prior of BayesFactor::ttestBF (a Cauchy on the effect
# size with scale sqrt(2)/2, "medium"), which is the one JASP uses and
# the one a reader is most likely to know. For the two-group case it is
# the equal-variance model: BayesFactor has no Welch form, so the Bayes
# factor beside a Welch t-test assumes what the t-test does not.
#
# NA rather than an error when it cannot be computed (too few subjects,
# a constant difference), so one channel failing does not take the
# rest of its table with it.
bf10_ttest <- function(...) {
  out <- tryCatch(suppressMessages(BayesFactor::ttestBF(...)),
                  error = function(e) NULL)
  if (is.null(out)) return(NA_real_)
  as.numeric(BayesFactor::extractBF(out)$bf)
}

# The Bayes factor for one effect of a mixed model: the model with EFFECT
# against the same model without it, both with a random intercept per
# person and BayesFactor::lmBF's default priors (Rouder et al., 2012), as
# a Bayesian repeated-measures ANOVA compares them. TERMS are the fixed
# terms of the model the section fitted, so a design that fell back to a
# simpler model gets the Bayes factor of that model. It does not let the
# effect vary between people, as the fitted model may; the report says so.
# lmBF integrates the random effect by sampling, so the seed is fixed and
# rendering twice gives the same number. NA when the effect is not in the
# model or the comparison cannot be computed.
bf10_effect <- function(data, terms, effect) {
  if (!(effect %in% terms)) return(NA_real_)
  tryCatch({
    df <- as.data.frame(data)
    for (v in intersect(c("bin", "group", "session", "person_id"), names(df))) {
      df[[v]] <- droplevels(factor(df[[v]]))
    }
    model <- function(t) {
      set.seed(20260101)
      suppressMessages(BayesFactor::lmBF(stats::as.formula(paste("value ~", paste(c(t, "person_id"), collapse = " + "))),
        data = df, whichRandom = "person_id", progress = FALSE))
    }
    as.numeric(BayesFactor::extractBF(model(terms) / model(setdiff(terms, effect)))$bf)
  }, error = function(e) NA_real_)
}

# Three significant figures, because a Bayes factor ranges over orders
# of magnitude and the three decimals apa_gt gives a number would show
# 0.000 for a strong result in favour of no difference.
fmt_bf <- function(bf) {
  ifelse(is.na(bf), NA_character_,
    ifelse(bf >= 1000, "> 1000",
      ifelse(bf < 0.001, "< 0.001", formatC(bf, digits = 3, format = "fg"))))
}

# The conventional reading of a Bayes factor's size: Jeffreys (1961), in
# the wording of Lee and Wagenmakers (2013). The same cut-offs apply in
# both directions, as reciprocals.
bf_word <- function(bf) {
  strength <- function(x) ifelse(x > 100, "extreme", ifelse(x > 30, "very strong",
    ifelse(x > 10, "strong", ifelse(x > 3, "moderate", "anecdotal"))))
  ifelse(is.na(bf), NA_character_,
    ifelse(bf == 1, "no evidence either way",
      ifelse(bf > 1, paste(strength(bf), "for a difference"),
                     paste(strength(1 / bf), "for no difference"))))
}
