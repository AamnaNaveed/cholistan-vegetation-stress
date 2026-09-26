# ============================================================================
# Script: 06_rerun_models.R
# Purpose: Fit GAM and Random Forest on the corrected, non-circular dataset.
# Reference: PDF Step 6 - Rerun the models (Section 1.8.6)
# ============================================================================

# 1. Load required packages
required_packages <- c("tidyverse", "mgcv", "ranger", "yaml", "here")
lapply(required_packages, function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) install.packages(pkg, dependencies = TRUE)
  library(pkg, character.only = TRUE, quietly = TRUE)
})

# 2. Load the clean modelling data
config <- read_yaml(here("config.yaml"))
modelling_data <- read_csv(here("data/processed/modelling_data_clean.csv"), show_col_types = FALSE)

cat("🚀 Rerunning GAM and Random Forest on corrected data (Step 6)...\n")

# 3. Define strict predictors and response
# Note: 'land_cover_class' is now a genuine, independent categorical predictor!
predictors <- c("elevation", "slope_degrees", "seasonal_precip", "lagged_seasonal_precip", "seasonal_temp", "land_cover_class")
response <- "ndvi_anomaly"

# Ensure land_cover_class is a factor for the models
modelling_data <- modelling_data %>%
  mutate(land_cover_class = as.factor(land_cover_class))

cat("✅ Dataset ready with", nrow(modelling_data), "observations and", length(predictors), "predictors.\n")

# --- PART 1: Fit Generalized Additive Model (GAM) ---
cat("\n📈 Fitting GAM...\n")
set.seed(42)

# Note: land_cover_class is categorical, so we do NOT wrap it in s()
gam_model <- mgcv::gam(
  ndvi_anomaly ~ s(elevation) + 
    s(slope_degrees) + 
    s(seasonal_precip) + 
    s(lagged_seasonal_precip) + 
    s(seasonal_temp) + 
    land_cover_class,
  data = modelling_data,
  method = "REML"
)

cat("✅ GAM fitted.\n")
print(summary(gam_model))

# Plot GAM partial effects
png(here("outputs/figures/12_gam_partial_effects.png"), width = 1500, height = 1000, res = 150)
par(mfrow = c(2, 3), mar = c(5, 5, 2, 1))
plot(gam_model, shade = TRUE, seWithMean = TRUE, main = "")
dev.off()
cat("📊 Saved GAM partial effects to: outputs/figures/12_gam_partial_effects.png\n")

saveRDS(gam_model, here("data/processed/gam_model_corrected.rds"))

# --- PART 2: Fit Random Forest ---
cat("\n🌲 Fitting Random Forest...\n")
set.seed(42)

rf_model <- ranger(
  ndvi_anomaly ~ .,
  data = modelling_data %>% select(all_of(c(response, predictors))),
  num.trees = 500,
  importance = "impurity",
  write.forest = TRUE
)

cat("✅ Random Forest fitted.\n")
print(rf_model)

# Plot Variable Importance
importance_df <- data.frame(
  Variable = names(rf_model$variable.importance),
  Importance = rf_model$variable.importance
) %>% arrange(desc(Importance))

p_imp <- ggplot(importance_df, aes(x = reorder(Variable, Importance), y = Importance, fill = Variable)) +
  geom_bar(stat = "identity", show.legend = FALSE) +
  coord_flip() +
  labs(
    title = "Random Forest Variable Importance (Corrected Model)",
    subtitle = "Predictors: Dynamic climate, terrain, and genuine MODIS land cover",
    x = "Predictor", y = "Importance (Impurity decrease)"
  ) +
  theme_minimal() + theme(plot.title = element_text(face = "bold"))

ggsave(here("outputs/figures/13_rf_variable_importance.png"), p_imp, width = 8, height = 5, dpi = 300)
cat("📊 Saved RF variable importance to: outputs/figures/13_rf_variable_importance.png\n")

saveRDS(rf_model, here("data/processed/rf_model_corrected.rds"))

cat("\n🎉 Step 6 Complete! Both models rerun on the scientifically clean dataset.\n")