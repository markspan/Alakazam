common_layers <- list(
  geom_jitter(width = 0.06, alpha = 0.6),
  zero_line,
  stat_summary(fun = mean, geom = "point", size = 3),
  stat_summary(fun.data = mean_se, geom = "errorbar", width = 0.1),
  labs(x = "Group", y = "__YLABEL__"),
  scale_colour_brewer(palette = "Set2"),
  scale_fill_brewer(palette = "Set2"),
  facet_wrap(~channel),
  alz_theme(),
  theme(legend.position = "none")
)
p <- ggplot(grp %>% filter(!is.na(value)), aes(group, value, colour = group, fill = group)) + violin_layers() + common_layers
print(p)
