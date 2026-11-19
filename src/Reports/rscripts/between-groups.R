
  n_groups <- n_distinct(d$group)
  if (n_groups < 2) {
    betweenRes2_list[[ch]] <- tibble(Channel = ch, Test = NA_character_,
      Note = "Only one group has a usable value for this channel; the between-group comparison could not be run.")
  } else if (n_groups == 2) {
    # The test of record and its check, both, always (see paired-section.qmd). The
    # Shapiro-Wilk p is of the values about their own group's mean: the raw values
    # of two groups pooled are bimodal exactly when the groups differ, and were
    # choosing the rank test for 77% of samples at d = 4.
    lv <- levels(droplevels(factor(d$group)))
    tt <- t.test(value ~ group, data = d)
    eff <- cohens_d_ci(d$value[d$group == lv[1]], d$value[d$group == lv[2]])
    bf <- bf10_ttest(formula = value ~ group,
                     data = as.data.frame(d %>% mutate(group = droplevels(factor(group)))))
    res2 <- tibble(Channel = ch, Test = "Welch two-sample t-test", Statistic = unname(tt$statistic), df = apa_num(unname(tt$parameter), 1),
                   p = apa_p(tt$p.value), Effect = "Cohen's d", Estimate = eff$effsize,
                   CI_low = eff$conf.low, CI_high = eff$conf.high,
                   BF10 = fmt_bf(bf), Evidence = bf_word(bf),
                   Shapiro_Wilk_p = shapiro_note(d$value - ave(d$value, d$group)))
    p_grp <- tt$p.value
    omnibus <- bind_rows(omnibus, tibble(group = tag, window = "__WINDOW_R__", measure = "__MEASURETYPE_R__", channel = ch, contrast = "__COMBOLABEL_R__", role = "secondary", design = "between_group_combo", test = "welch_t_test", p = p_grp,
                                          estimate = eff$effsize, conf.low = eff$conf.low, conf.high = eff$conf.high))
    wt <- tryCatch(suppressWarnings(wilcox.test(value ~ group, data = d, conf.int = TRUE)), error = function(e) NULL)
    if (!is.null(wt)) {
      rb <- rank_biserial_ci(value ~ group, data = d)
      res2 <- bind_rows(res2, tibble(Channel = ch, Test = "Mann-Whitney U", Statistic = unname(wt$statistic), df = "--",
                                     p = apa_p(wt$p.value), Effect = "Rank-biserial r", Estimate = rb$effsize,
                                     CI_low = rb$conf.low, CI_high = rb$conf.high))
    }
    betweenRes2_list[[ch]] <- res2
  } else {
    # Welch ANOVA + Games-Howell, not classic ANOVA + Tukey -- see
    # betweenSection's own comment on this same choice.
    aov <- tryCatch(welch_anova_test(data = d, formula = value ~ group), error = function(e) NULL)
    p_grp <- NA_real_
    if (!is.null(aov)) {
      p_grp <- aov$p[1]
      betweenAnova_list[[ch]] <- as.data.frame(aov) %>% mutate(channel = ch, .before = 1)
    }

    betweenPw_list[[ch]] <- (d %>% games_howell_test(value ~ group)) %>% mutate(channel = ch, .before = 1)

    omnibus <- bind_rows(omnibus, tibble(group = tag, window = "__WINDOW_R__", measure = "__MEASURETYPE_R__", channel = ch, contrast = "__COMBOLABEL_R__", role = "secondary", design = "between_group_combo", test = "welch_anova", p = p_grp,
                                          estimate = NA_real_, conf.low = NA_real_, conf.high = NA_real_))
  }
