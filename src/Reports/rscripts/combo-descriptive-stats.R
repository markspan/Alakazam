d <- grp %>% filter(!is.na(value)) %>% droplevels()
if (nrow(d) == 0) {
  cat("\n*No usable values for this combination bin.*\n\n")
} else {
  descr <- d %>% group_by(channel) %>% summarise(M = mean(value), SD = sd(value), n = n(), .groups = "drop")
  cat(as_raw_html(blank_missing(apa_gt(descr, "Descriptive Statistics by Channel"))))

  common_layers <- list(
    geom_jitter(width = 0.05, colour = "grey40", alpha = 0.6),
    stat_summary(fun = mean, geom = "point", size = 3, colour = "#4a7fc9"),
    stat_summary(fun.data = mean_se, geom = "errorbar", width = 0.1, colour = "#4a7fc9"),
    labs(x = NULL, y = "__YLABEL__"),
    scale_x_continuous(breaks = NULL),
    facet_wrap(~channel),
    alz_theme()
  )
  p <- ggplot(d, aes(x = 1, y = value, group = 1)) + violin_layers("#4a7fc9") + common_layers
  print(p)
}
