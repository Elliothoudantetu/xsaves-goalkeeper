# =============================================================================
# 03 - Modèle xSaves / xSaves model
# Entrée / Input  : tirs_variables.rds
# Sortie / Output : tirs_modele.rds, modele_xsaves.rds, figures/calibration.png
#
# Régression logistique, validation croisée en 5 blocs groupés par match
# (le modèle n'est jamais évalué sur un match vu à l'entraînement).
# Logistic regression, 5-fold cross-validation grouped by match
# (the model is never evaluated on a match it was trained on).
# =============================================================================

library(tidyverse)
library(pROC)

tirs_var <- readRDS("tirs_variables.rds")

# Gardien dans sa surface (exclut les buts quasi vides)
# Goalkeeper inside his box (excludes near-empty-net shots)
d <- tirs_var %>%
  filter(gk_sortie <= 18) %>%
  mutate(proche = as.integer(distance < 8))
nrow(tirs_var) - nrow(d)

# --- 1. Formules / Formulas ---------------------------------------------------
f_tir    <- arret ~ log(distance) + angle + tete + hauteur + n_def_devant
f_sortie <- update(f_tir, . ~ . + gk_sortie + gk_decal + ecart_arrivee)
f_couv   <- update(f_tir, . ~ . + gk_couv   + gk_decal + ecart_arrivee)
f_inter  <- update(f_tir, . ~ . + gk_couv * proche + gk_decal + ecart_arrivee)

# --- 2. Validation croisée par match / Match-grouped cross-validation ---------
set.seed(42)
matchs <- unique(d$match_id)
bloc   <- setNames(sample(rep(1:5, length.out = length(matchs))), matchs)
d$bloc <- bloc[as.character(d$match_id)]

predire_cv <- function(formule) {
  pred <- numeric(nrow(d))
  for (k in 1:5) {
    m <- glm(formule, data = d[d$bloc != k, ], family = binomial)
    pred[d$bloc == k] <- predict(m, d[d$bloc == k, ], type = "response")
  }
  pred
}

d$xs_tir    <- predire_cv(f_tir)
d$xs_sortie <- predire_cv(f_sortie)
d$xs_couv   <- predire_cv(f_couv)
d$xs_inter  <- predire_cv(f_inter)

# --- 3. Évaluation / Evaluation ------------------------------------------------
evaluer <- function(p) c(AUC   = as.numeric(auc(d$arret, p, quiet = TRUE)),
                         Brier = mean((p - d$arret)^2))
round(rbind(shot_only        = evaluer(d$xs_tir),
            gk_depth         = evaluer(d$xs_sortie),
            gk_coverage      = evaluer(d$xs_couv),
            coverage_x_close = evaluer(d$xs_inter)), 3)

# --- 4. Modèle final / Final model ---------------------------------------------
modele <- glm(f_inter, data = d, family = binomial)
summary(modele)

# --- 5. Calibration ------------------------------------------------------------
calib <- d %>%
  mutate(groupe = ntile(xs_inter, 10)) %>%
  group_by(groupe) %>%
  summarise(predit = mean(xs_inter), observe = mean(arret), n = n())

fig <- ggplot(calib, aes(predit, observe)) +
  geom_abline(linetype = "dashed", colour = "grey50") +
  geom_point(size = 3, colour = "#0072B2") +
  coord_equal(xlim = c(0, 1), ylim = c(0, 1)) +
  labs(x = "Predicted save probability (out-of-fold)", y = "Observed save rate",
       title = "xSaves calibration", subtitle = "Deciles of predicted probability",
       caption = "Data: StatsBomb open data") +
  theme_minimal(base_size = 12)

dir.create("figures", showWarnings = FALSE)
ggsave("figures/calibration.png", fig, width = 6, height = 6, dpi = 200, bg = "white")

saveRDS(d, "tirs_modele.rds")
saveRDS(modele, "modele_xsaves.rds")
