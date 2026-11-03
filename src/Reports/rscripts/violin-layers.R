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

# ---- effect sizes with their intervals ----
# Cohen's d with a BCa bootstrap interval, written out rather than through
# rstatix::cohens_d, whose resampling runs through dplyr and takes about two
# seconds for each 2000 draws: per channel and window, that is minutes per
# report. Same d (rstatix's default, the mean difference over the root mean
# of the two variances for two groups, and over the SD for one sample or a
# paired difference). 2000 draws, because a BCa end point at 200 moved by about
# a fifth of a standard deviation between renders of the same data; the seed
# makes rendering twice give the same interval. boot ships with R.
alz_boot_draws <- 2000
cohens_d_ci <- function(x, y = NULL) {
  none <- tibble(effsize = NA_real_, conf.low = NA_real_, conf.high = NA_real_)
  tryCatch({
    set.seed(20260101)
    if (is.null(y)) {
      d_of <- function(v) mean(v) / sd(v)
      est <- d_of(x)
      draws <- boot::boot(x, function(v, i) d_of(v[i]), R = alz_boot_draws)
    } else {
      d_of <- function(a, b) (mean(a) - mean(b)) / sqrt((var(a) + var(b)) / 2)
      est <- d_of(x, y)
      strata <- rep(c(1L, 2L), c(length(x), length(y)))
      draws <- boot::boot(c(x, y), function(v, i) d_of(v[i[strata[i] == 1L]], v[i[strata[i] == 2L]]),
                          R = alz_boot_draws, strata = strata)
    }
    ends <- boot::boot.ci(draws, type = "bca")$bca[4:5]
    tibble(effsize = est, conf.low = ends[1], conf.high = ends[2])
  }, error = function(e) none)
}

# The rank-biserial correlation, signed, in the direction of the test beside it
# (Kerby, 2014). rstatix::wilcox_effsize is a different quantity, |Z| / sqrt(N),
# with no sign: it read +.85 on differences whose rank-biserial is -.96.
rank_biserial_ci <- function(...) {
  out <- tryCatch(effectsize::rank_biserial(...), error = function(e) NULL)
  if (is.null(out)) return(tibble(effsize = NA_real_, conf.low = NA_real_, conf.high = NA_real_))
  tibble(effsize = out$r_rank_biserial, conf.low = out$CI_low, conf.high = out$CI_high)
}

# The Shapiro-Wilk p of X as text, or "" when it cannot be computed. A
# description printed beside a test, never a gate that chooses one: testing for
# normality first distorts the error rates of the test that follows, and has
# least power where it would matter most (Rochon et al., 2012; Shatz, 2024).
shapiro_note <- function(x) {
  s <- tryCatch(shapiro.test(x), error = function(e) NULL)
  if (is.null(s) || is.na(s$p.value)) "" else apa_p(s$p.value)
}

# ---- one value per person ----
# Every test without a person term (a t-test, a Wilcoxon, a Welch ANOVA) takes
# its rows to be independent, and two sessions of one person are not: counted as
# two subjects, 12 people with two sessions gave .154 false positives at .05,
# where the same test on the 12 people gave .050. So each person's recordings
# are averaged first, within a condition, group and channel; on angles, by the
# circular mean. With one recording per person this returns its input.
per_person <- function(d) {
  keys <- intersect(c("person_id", "group", "bin", "channel", "window", "measure_type"), names(d))
  if (!"person_id" %in% names(d) || !anyDuplicated(d[keys])) return(d)
  circular <- all(d$measure_type %in% c("phase", "phaselag"))
  d %>%
    group_by(across(all_of(keys))) %>%
    summarise(value = if (circular) atan2(mean(sin(value), na.rm = TRUE), mean(cos(value), na.rm = TRUE))
                      else mean(value, na.rm = TRUE), .groups = "drop") %>%
    mutate(value = ifelse(is.nan(value), NA_real_, value), dataset = as.character(person_id))
}

# ---- the sphericity assumption ----
# The Huynh-Feldt correction of each within-subjects term, on the people with a
# value in every cell: a table with one row per term that has one to correct
# (three levels or more). A mixed model with a random intercept and no slopes
# assumes sphericity as an uncorrected repeated-measures ANOVA does, and is that
# ANOVA when the data are complete. Its false positives grow with the number of
# conditions when the assumption fails: .05 at 3 bins, .087 at 6 and .103 at 8
# with neighbouring bins correlated at .8 (N = 16), where the correction holds
# them near .04. Haverkamp & Beauducel (2017) find the same pattern and advise
# Huynh-Feldt. The term's name is sorted, so "group:bin" finds "bin:group".
term_key <- function(term) paste(sort(strsplit(term, ":", fixed = TRUE)[[1]]), collapse = ":")
huynh_feldt <- function(d, within, between = character()) {
  none <- tibble(key = character(), epsilon = double(), p = double(), n_complete = integer())
  tryCatch({
    cells <- d %>%
      group_by(across(all_of(c("person_id", within, between)))) %>%
      summarise(value = mean(value), .groups = "drop")
    n_cells <- prod(vapply(within, function(w) n_distinct(cells[[w]]), numeric(1)))
    complete <- cells %>% group_by(person_id) %>% filter(n() == n_cells) %>% ungroup() %>% droplevels()
    if (n_distinct(complete$person_id) < 3) return(none)
    f <- stats::as.formula(sprintf("value ~ %s + Error(person_id / (%s))",
                                   paste(c(within, between), collapse = " * "),
                                   paste(within, collapse = " * ")))
    fit <- suppressWarnings(suppressMessages(rstatix::anova_test(data = as.data.frame(complete), formula = f)))
    corr <- as.data.frame(fit[["Sphericity Corrections"]])
    if (nrow(corr) == 0) return(none)
    aov_tab <- as.data.frame(fit[["ANOVA"]])
    rows <- match(corr$Effect, aov_tab$Effect)
    eps <- pmin(as.numeric(corr$HFe), 1)   # an estimate above 1 means no correction
    tibble(key = vapply(as.character(corr$Effect), term_key, ""), epsilon = eps,
           p = pf(aov_tab$F[rows], aov_tab$DFn[rows] * eps, aov_tab$DFd[rows] * eps, lower.tail = FALSE),
           n_complete = n_distinct(complete$person_id))
  }, error = function(e) none)
}

# The Friedman test of the conditions, on the people with a value in all of them.
friedman_note <- function(d) {
  wide <- d %>% group_by(person_id, bin) %>% summarise(value = mean(value), .groups = "drop") %>%
    pivot_wider(names_from = bin, values_from = value) %>% drop_na()
  out <- tryCatch(friedman.test(as.matrix(select(wide, -person_id))), error = function(e) NULL)
  if (is.null(out) || is.na(out$p.value)) "" else apa_p(out$p.value)
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
