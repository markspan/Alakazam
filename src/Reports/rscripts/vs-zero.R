
  # One-sample-vs-zero, once PER GROUP: with groups present, "does
  # this effect exist at all" becomes a per-group question -- never
  # folded into the between-groups comparison below, which asks a
  # different thing (does the effect DIFFER between groups, not
  # whether it exists in either one).
  vs_zero <- d %>% group_by(group) %>% group_modify(~ {
    missing_row <- tibble(M = mean(.x$value), n = nrow(.x), Test = NA_character_, Statistic = NA_real_, df = NA_real_,
                          p = NA_character_, Effect = NA_character_, Estimate = NA_real_, CI_low = NA_real_, CI_high = NA_real_)
    tt <- tryCatch(t.test(.x$value, mu = 0), error = function(e) NULL)
    if (is.null(tt)) return(missing_row)
    # The test of record and its check, both, always (see paired-section.qmd).
    eff <- cohens_d_ci(.x$value)
    bf <- bf10_ttest(x = .x$value, mu = 0)
    res <- tibble(M = mean(.x$value), n = nrow(.x), Test = "One-sample t-test", Statistic = unname(tt$statistic), df = unname(tt$parameter), p = apa_p(tt$p.value),
                  Effect = "Cohen's d", Estimate = eff$effsize, CI_low = eff$conf.low, CI_high = eff$conf.high,
                  BF10 = fmt_bf(bf), Evidence = bf_word(bf), Shapiro_Wilk_p = shapiro_note(.x$value))
    wt <- tryCatch(suppressWarnings(wilcox.test(.x$value, mu = 0, conf.int = TRUE)), error = function(e) NULL)
    if (is.null(wt)) return(res)
    rb <- rank_biserial_ci(.x$value, mu = 0)
    bind_rows(res, tibble(M = mean(.x$value), n = nrow(.x), Test = "Wilcoxon signed-rank", Statistic = unname(wt$statistic), df = NA_real_, p = apa_p(wt$p.value),
                          Effect = "Rank-biserial r", Estimate = rb$effsize, CI_low = rb$conf.low, CI_high = rb$conf.high))
  }) %>% ungroup()
  vszero_list[[ch]] <- vs_zero %>% select(-M, -n) %>% mutate(channel = ch, .before = 1)

