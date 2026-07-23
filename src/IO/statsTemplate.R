# ============================================================
# Alakazam -- statistical analysis of exported ERP measurements
# Auto-generated (edit freely: this is a sensible starting point,
# not the last word on your design).
#
# It reads the long-format measurement CSV from the Measurements
# tab and, for each measure_type x window x channel, runs a
# repeated-measures ANOVA across bins (subject as the random
# factor) and Holm-corrected pairwise paired t-tests, then draws a
# per-group plot (individual subjects, group mean, standard error,
# and significance brackets). Tables and plots are written to the
# alakazam_stats folder next to this script.
#
# Uses the tidyverse (dplyr, tidyr, ggplot2), rstatix and ggpubr.
# ============================================================

pkgs <- c("tidyverse", "rstatix", "ggpubr")
missing <- pkgs[!pkgs %in% rownames(installed.packages())]
if (length(missing)) install.packages(missing, repos = "https://cloud.r-project.org")
invisible(lapply(pkgs, library, character.only = TRUE))

# --- inputs ---
csv_file <- "__CSVFILE__"       # the exported measurements CSV
out_dir  <- "alakazam_stats"    # tables and plots go here
dir.create(out_dir, showWarnings = FALSE)

# Single-subject rows only (grand averages are summaries, not a sample).
dat <- read_csv(csv_file, show_col_types = FALSE) %>%
  filter(dataset_type == "subject") %>%
  mutate(dataset = factor(dataset), bin = factor(bin))

if (n_distinct(dat$dataset) < 2)
  stop("Need at least two subjects (dataset_type == subject) for statistics.")

# One analysis per measure x window x channel.
groups <- dat %>% distinct(measure_type, window, channel)
cat(sprintf("Analysing %d measure x window x channel group(s).\n", nrow(groups)))

for (i in seq_len(nrow(groups))) {
  g <- groups[i, ]
  d <- dat %>%
    filter(measure_type == g$measure_type, window == g$window, channel == g$channel) %>%
    droplevels()
  if (n_distinct(d$bin) < 2) next

  # Balanced repeated measures: keep only subjects present in every bin.
  keep <- d %>% count(dataset) %>% filter(n == n_distinct(d$bin)) %>% pull(dataset)
  d <- d %>% filter(dataset %in% keep) %>% droplevels()
  if (n_distinct(d$dataset) < 2) next

  tag <- str_replace_all(paste(g$measure_type, g$window, g$channel, sep = "_"),
                         "[^A-Za-z0-9]+", "_")

  cat("\n============================================================\n")
  cat(sprintf("%s | window %s | channel %s | n = %d\n",
              g$measure_type, g$window, g$channel, n_distinct(d$dataset)))

  # ---- Repeated-measures ANOVA across bins ----
  aov <- tryCatch(anova_test(data = d, dv = value, wid = dataset, within = bin),
                  error = function(e) NULL)
  p_bin <- NA
  if (!is.null(aov)) {
    tab <- get_anova_table(aov)
    print(tab)
    write_csv(as.data.frame(tab), file.path(out_dir, paste0("anova_", tag, ".csv")))
    if ("bin" %in% tab$Effect) p_bin <- tab$p[tab$Effect == "bin"][1]
  }

  # ---- Pairwise paired t-tests (Holm) ----
  pw <- d %>% pairwise_t_test(value ~ bin, paired = TRUE, p.adjust.method = "holm")
  print(pw)
  write_csv(pw, file.path(out_dir, paste0("pairwise_", tag, ".csv")))

  # ---- Plot: subjects + group mean + SE + significance ----
  summ <- d %>% group_by(bin) %>%
    summarise(mean = mean(value), se = sd(value) / sqrt(n()), .groups = "drop")
  pw_xy <- pw %>% add_xy_position(x = "bin")

  subtitle <- if (!is.na(p_bin))
    sprintf("Repeated-measures ANOVA (bin): p = %.4g", p_bin) else ""

  p <- ggplot(d, aes(bin, value)) +
    geom_line(aes(group = dataset), colour = "grey75", alpha = 0.5) +
    geom_point(colour = "grey40", size = 1.4, alpha = 0.5,
               position = position_jitter(width = 0.04, height = 0)) +
    geom_col(data = summ, aes(bin, mean), inherit.aes = FALSE,
             fill = "#4a7fc9", alpha = 0.22, width = 0.6) +
    geom_errorbar(data = summ, aes(bin, ymin = mean - se, ymax = mean + se),
                  inherit.aes = FALSE, width = 0.18) +
    stat_pvalue_manual(pw_xy, hide.ns = TRUE, tip.length = 0.01) +
    labs(title = sprintf("%s  (%s @ %s)", g$measure_type, g$window, g$channel),
         subtitle = subtitle, x = "Bin", y = "Value") +
    theme_pubr()

  ggsave(file.path(out_dir, paste0("plot_", tag, ".pdf")), p, width = 6, height = 4)
}

cat(sprintf("\nDone. Tables and plots written to %s/\n", out_dir))
