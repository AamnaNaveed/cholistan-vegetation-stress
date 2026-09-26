# ============================================================================
# Script: 08_uncertainty_and_novelty.R
# Purpose: Calculate model disagreement and environmental novelty (MESS-style).
# Reference: PDF Step 8 (Section 1.8.8)
# ============================================================================

# 1. Load required packages
required_packages <- c("tidyverse", "mgcv", "ranger", "yaml", "here")
lapply(required_packages, function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) install.packages(pkg, dependencies = TRUE)
  library(pkg, character.only = TRUE, quietly = TRUE)
})

# 2. Load data and models
config <- read_yaml(here("config.yaml"))
modelling_data <- read_csv(here("data/processed/modelling_data_clean.csv"), show_col_types = FALSE)

gam_model <- readRDS(here("data/processed/gam_final_2024.rds"))
rf_model <- readRDS(here("data/processed/rf_final_2024.rds"))

cat("🔍 Calculating Uncertainty and Environmental Novelty (Step 8)...\n")

# Define predictors
predictors <- c("elevation", "slope_degrees", "seasonal_precip", "lagged_seasonal_precip", "seasonal_temp", "land_cover_class")

# Split data
train_data <- modelling_data %>% filter(year < 2024)
test_2024 <- modelling_data %>% filter(year == 2024) %>% mutate(land_cover_class = as.factor(land_cover_class))

# --- PART 1: Model Disagreement ---
cat("\n📊 Calculating Model Disagreement on 2024 data...\n")

pred_gam <- predict(gam_model, newdata = test_2024)
pred_rf <- predict(rf_model, data = test_2024 %>% select(all_of(predictors)))$predictions

uncertainty_2024 <- test_2024 %>%
  mutate(
    pred_gam = pred_gam,
    pred_rf = pred_rf,
    disagreement = abs(pred_gam - pred_rf) # Absolute difference between models
  )

cat("✅ Mean Model Disagreement (MAE between models):", round(mean(uncertainty_2024$disagreement), 3), "\n")

# Plot Disagreement vs Predicted Anomaly
p_disagree <- ggplot(uncertainty_2024, aes(x = pred_rf, y = disagreement)) +
  geom_point(alpha = 0.4, color = "#e74c3c") +
  geom_smooth(method = "loess", color = "black", se = TRUE) +
  labs(
    title = "Model Disagreement (Uncertainty Proxy)",
    subtitle = "Higher disagreement indicates areas where GAM and RF strongly diverge",
    x = "Random Forest Predicted Anomaly",
    y = "Absolute Disagreement (|GAM - RF|)"
  ) +
  theme_minimal() + theme(plot.title = element_text(face = "bold"))

ggsave(here("outputs/figures/15_model_disagreement.png"), p_disagree, width = 8, height = 6, dpi = 300)
cat("📊 Saved disagreement plot to: outputs/figures/15_model_disagreement.png\n")

# --- PART 2: Environmental Novelty (Simplified MESS) ---
cat("\n🌍 Calculating Environmental Novelty (Out-of-Range Check)...\n")

# Calculate 5th and 95th percentiles for continuous predictors from TRAINING data
ranges <- train_data %>%
  summarise(
    precip_min = quantile(seasonal_precip, 0.05, na.rm = TRUE),
    precip_max = quantile(seasonal_precip, 0.95, na.rm = TRUE),
    lag_precip_min = quantile(lagged_seasonal_precip, 0.05, na.rm = TRUE),
    lag_precip_max = quantile(lagged_seasonal_precip, 0.95, na.rm = TRUE),
    temp_min = quantile(seasonal_temp, 0.05, na.rm = TRUE),
    temp_max = quantile(seasonal_temp, 0.95, na.rm = TRUE)
  )

# Flag novelty in 2024 test data
novelty_2024 <- uncertainty_2024 %>%
  mutate(
    novel_precip = seasonal_precip < ranges$precip_min | seasonal_precip > ranges$precip_max,
    novel_lag_precip = lagged_seasonal_precip < ranges$lag_precip_min | lagged_seasonal_precip > ranges$lag_precip_max,
    novel_temp = seasonal_temp < ranges$temp_min | seasonal_temp > ranges$temp_max,
    is_novel = novel_precip | novel_lag_precip | novel_temp
  )

novelty_summary <- novelty_2024 %>%
  summarise(
    total_2024_obs = n(),
    novel_obs = sum(is_novel),
    pct_novel = round((novel_obs / total_2024_obs) * 100, 1)
  )

cat("✅ Novelty Check Complete.\n")
cat("Total 2024 observations:", novelty_summary$total_2024_obs, "\n")
cat("Observations with NOVEL climate conditions:", novelty_summary$novel_obs, "(", novelty_summary$pct_novel, "%)\n")

# Save novelty summary
write_csv(novelty_summary, here("data/processed/novelty_summary_2024.csv"))
cat("💾 Saved novelty summary to: data/processed/novelty_summary_2024.csv\n")

# Plot Novelty
p_novelty <- ggplot(novelty_2024, aes(x = as.factor(is_novel), y = disagreement, fill = as.factor(is_novel))) +
  geom_boxplot(alpha = 0.7) +
  scale_fill_manual(values = c("FALSE" = "#4daf4a", "TRUE" = "#e41a1c"), labels = c("FALSE" = "Familiar Conditions", "TRUE" = "Novel Conditions")) +
  labs(
    title = "Uncertainty vs. Environmental Novelty",
    subtitle = "Do models disagree more when facing unseen climate conditions?",
    x = "Environmental Condition in 2024",
    y = "Model Disagreement"
  ) +
  theme_minimal() + theme(plot.title = element_text(face = "bold"), legend.position = "none")

ggsave(here("outputs/figures/16_novelty_vs_uncertainty.png"), p_novelty, width = 7, height = 6, dpi = 300)
cat("📊 Saved novelty plot to: outputs/figures/16_novelty_vs_uncertainty.png\n")

cat("\n🎉 Step 8 Complete! Uncertainty and novelty outputs generated.\n")