
# One row per test run below (design/group/p, plus its own effect size
# estimate/CI where the test provides one), so the closing section can
# report a BH/FDR-adjusted summary ACROSS every group tested (not just
# within one group's own pairwise comparisons) and a forest plot of every
# effect size alongside it. estimate/conf.low/conf.high are NA for a test
# that does not report a CI-bearing effect size (e.g. an omnibus ANOVA's
# own generalized eta-squared, which rstatix does not attach a CI to).
# group is the glued-together key kept for continuity; the four columns
# after it are the same information taken apart, which is what makes a
# summary row readable. A tag like "N400_mean_amplitude_N400_Cz" is
# window + measure + contrast + channel, and the doubled "N400" there is
# simply a combination bin sharing the window's name -- unreadable glued,
# obvious in columns.
omnibus <- tibble(group = character(), window = character(), measure = character(),
                  channel = character(), contrast = character(),
                  design = character(), test = character(), p = double(),
                  role = character(),
                  estimate = double(), conf.low = double(), conf.high = double())

