# =============================================================================
# 01 - Extraction des tirs cadrés / Extract on-target shots
# Source : StatsBomb open data (Coupes du monde 2018 & 2022, Euros 2020 & 2024)
# Sortie / Output : tirs.rds
# =============================================================================

library(StatsBombR)
library(tidyverse)

options(timeout = 600)

# Compétitions / Competitions
comps <- FreeCompetitions() %>%
  filter((competition_id == 55 & season_id %in% c(43, 282)) |   # Euro 2020 & 2024
         (competition_id == 43 & season_id %in% c(3, 106)))     # World Cup 2018 & 2022

matches <- FreeMatches(comps)
events  <- free_allevents(MatchesDF = matches, Parallel = TRUE)
events  <- allclean(events)

# Tirs cadrés hors penalties / On-target shots, penalties excluded
tirs <- events %>%
  filter(type.name == "Shot",
         shot.type.name != "Penalty",
         shot.outcome.name %in% c("Goal", "Saved", "Saved to Post")) %>%
  mutate(arret = as.integer(shot.outcome.name != "Goal"))   # 1 = save, 0 = goal

# Contrôles / Checks
nrow(tirs)
table(tirs$shot.outcome.name)

saveRDS(tirs, "tirs.rds")
