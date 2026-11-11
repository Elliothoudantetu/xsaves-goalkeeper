# =============================================================================
# 02 - Variables tir / gardien / contexte  -  Shot, goalkeeper and context features
# Entrée / Input  : tirs.rds
# Sortie / Output : tirs_variables.rds, figures/coverage_by_distance.png
#
# Repère StatsBomb : terrain 120 x 80 yards, l'équipe qui tire attaque vers x = 120,
# poteaux en y = 36 et y = 44.
# StatsBomb frame: 120 x 80 yards pitch, shooting team attacks towards x = 120,
# posts at y = 36 and y = 44.
# =============================================================================

library(tidyverse)
tirs <- readRDS("tirs.rds")

but_x <- 120; but_y <- 40; poteau_g <- 36; poteau_d <- 44

# --- 1. Position du gardien adverse / Opposing goalkeeper location ----------
pos_gardien <- function(ff) {
  if (is.null(ff) || nrow(ff) == 0) return(c(NA_real_, NA_real_))
  g <- ff %>% filter(position.name == "Goalkeeper", !teammate)
  if (nrow(g) == 0) return(c(NA_real_, NA_real_))
  g$location[[1]]
}

# --- 2. Joueurs dans le triangle ballon-poteaux / Players inside the shot triangle
signe <- function(px, py, x1, y1, x2, y2) (px - x2) * (y1 - y2) - (x1 - x2) * (py - y2)

joueurs_devant <- function(ff, ax, ay, defenseurs_seulement = FALSE) {
  if (is.null(ff) || nrow(ff) == 0) return(0L)
  ff <- ff %>% filter(position.name != "Goalkeeper")
  if (defenseurs_seulement) ff <- ff %>% filter(!teammate)
  if (nrow(ff) == 0) return(0L)
  px <- map_dbl(ff$location, 1)
  py <- map_dbl(ff$location, 2)
  d1 <- signe(px, py, ax, ay, but_x, poteau_g)
  d2 <- signe(px, py, but_x, poteau_g, but_x, poteau_d)
  d3 <- signe(px, py, but_x, poteau_d, ax, ay)
  dedans <- !((d1 < 0 | d2 < 0 | d3 < 0) & (d1 > 0 | d2 > 0 | d3 > 0))
  sum(dedans)
}

# --- 3. Distance du gardien à la bissectrice / Distance to the angle bisector
decalage_bissectrice <- function(ax, ay, gx, gy) {
  u1 <- c(but_x - ax, poteau_g - ay); u1 <- u1 / sqrt(sum(u1^2))
  u2 <- c(but_x - ax, poteau_d - ay); u2 <- u2 / sqrt(sum(u2^2))
  d  <- (u1 + u2) / sqrt(sum((u1 + u2)^2))
  v  <- c(gx - ax, gy - ay)
  abs(v[1] * d[2] - v[2] * d[1])
}

# --- 4. Part du but cachée par le gardien / Share of the goal hidden by the GK
#     L'"ombre" du gardien (envergure fixe) est projetée depuis le ballon sur la ligne de but.
#     The goalkeeper's "shadow" (fixed reach) is projected from the ball onto the goal line.
envergure <- 1.5   # yards de chaque côté / on each side (body + dive)

part_couverte <- function(ax, ay, gx, gy) {
  if (gx <= ax) return(0)
  proj <- function(y) ay + (y - ay) * (but_x - ax) / (gx - ax)
  y1 <- proj(gy - envergure)
  y2 <- proj(gy + envergure)
  bas  <- max(min(y1, y2), poteau_g)
  haut <- min(max(y1, y2), poteau_d)
  max(0, haut - bas) / (poteau_d - poteau_g)    # 0 - 1
}

# --- 5. Calcul des variables / Feature computation ---------------------------
tirs_var <- tirs %>%
  mutate(
    gardien = map(shot.freeze_frame, pos_gardien),
    gk_x    = map_dbl(gardien, 1),
    gk_y    = map_dbl(gardien, 2)
  ) %>%
  filter(!is.na(gk_x)) %>%
  mutate(
    # Tir / Shot
    distance  = sqrt((but_x - location.x)^2 + (but_y - location.y)^2),
    angle     = abs(atan2(poteau_d - location.y, but_x - location.x) -
                    atan2(poteau_g - location.y, but_x - location.x)) * 180 / pi,
    tete      = as.integer(shot.body_part.name == "Head"),
    # Gardien / Goalkeeper
    gk_sortie = but_x - gk_x,
    gk_ballon = sqrt((gk_x - location.x)^2 + (gk_y - location.y)^2),
    gk_decal  = pmap_dbl(list(location.x, location.y, gk_x, gk_y), decalage_bissectrice),
    gk_couv   = pmap_dbl(list(location.x, location.y, gk_x, gk_y), part_couverte),
    # Contexte / Context
    n_devant     = pmap_int(list(shot.freeze_frame, location.x, location.y), joueurs_devant),
    n_def_devant = pmap_int(list(shot.freeze_frame, location.x, location.y),
                            joueurs_devant, defenseurs_seulement = TRUE),
    ecart_arrivee = abs(shot.end_location.y - gk_y),
    hauteur       = shot.end_location.z
  ) %>%
  select(id, match_id, team.name, player.name, shot.outcome.name, arret,
         location.x, location.y, gk_x, gk_y, shot.end_location.y,
         distance, angle, tete, gk_sortie, gk_ballon, gk_decal, gk_couv,
         n_devant, n_def_devant, ecart_arrivee, hauteur)

saveRDS(tirs_var, "tirs_variables.rds")

# --- 6. Contrôles / Checks ---------------------------------------------------
nrow(tirs) - nrow(tirs_var)
summary(select(tirs_var, distance:hauteur))

tirs_var %>% group_by(arret) %>%
  summarise(across(c(distance, angle, gk_decal, gk_couv, n_def_devant, ecart_arrivee),
                   ~ round(mean(.x, na.rm = TRUE), 2)))

# Couverture par tranche de distance / Coverage by distance band
couv_zone <- tirs_var %>%
  mutate(zone = cut(distance, breaks = c(0, 8, 12, 18, 25, 60),
                    labels = c("0-8", "8-12", "12-18", "18-25", "25+"))) %>%
  group_by(zone, arret) %>%
  summarise(couv = mean(gk_couv), n = n(), .groups = "drop")

couv_zone %>%
  mutate(couv = round(couv, 2)) %>%
  pivot_wider(names_from = arret, values_from = c(couv, n),
              names_glue = "{.value}_{ifelse(arret == 1, 'save', 'goal')}")

# Test sur les tirs proches / Test on close-range shots
proches <- tirs_var %>% filter(distance < 8)
wilcox.test(gk_couv ~ arret, data = proches)

# --- 7. Figure ---------------------------------------------------------------
fig <- couv_zone %>%
  mutate(issue = if_else(arret == 1, "Saved", "Goal")) %>%
  ggplot(aes(zone, couv, fill = issue)) +
  geom_col(position = position_dodge(width = 0.75), width = 0.7) +
  geom_text(aes(label = paste0("n=", n)), position = position_dodge(width = 0.75),
            vjust = -0.4, size = 3, colour = "grey30") +
  scale_y_continuous(labels = scales::percent, limits = c(0, 0.7),
                     expand = expansion(mult = c(0, 0.02))) +
  scale_fill_manual(values = c(Goal = "#D55E00", Saved = "#0072B2")) +
  labs(x = "Shot distance (yards)", y = "Share of the goal hidden by the goalkeeper",
       fill = NULL,
       title = "Angle coverage only matters at close range",
       subtitle = "On-target non-penalty shots, World Cups 2018-2022 & Euros 2020-2024",
       caption = "Data: StatsBomb open data") +
  theme_minimal(base_size = 12) +
  theme(legend.position = "top", panel.grid.major.x = element_blank())

dir.create("figures", showWarnings = FALSE)
ggsave("figures/coverage_by_distance.png", fig, width = 8, height = 5, dpi = 200, bg = "white")
