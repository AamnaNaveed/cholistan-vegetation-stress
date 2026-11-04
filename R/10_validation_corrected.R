# ============================================================================
# Script: 10_validation_corrected.R
# Purpose: Rigorous spatial and temporal validation for GAM and RF.
# REVISION: Full rewrite to address Reviewer 2: fixed 2024 leakage in spatial 
#           CV, switched to unbiased permutation importance, and added benchmarks.
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

cat("🚀 Starting Rigorous Validation (Step 10)...\n")

# Define predictors and response
predictors <- c("elevation", "slope_degrees", "seasonal_precip", "lagged_seasonal_precip", "seasonal_temp", "land_cover_class")
response <- "ndvi_anomaly"

# Ensure land_cover_class is a factor
modelling_data <- modelling_data %>% mutate(land_cover_class = as.factor(land_cover_class))

# Helper function to calculate metrics
calc_metrics <- function(obs, pred) {
  valid_idx <- !is.na(obs) & !is.na(pred)
  obs <- obs[valid_idx]
  pred <- pred[valid_idx]
  if(length(obs) < 2) return(c(RMSE = NA, MAE = NA, R2 = NA))
  rmse <- sqrt(mean((obs - pred)^2))
  mae <- mean(abs(obs - pred))
  r2 <- cor(obs, pred)^2
  return(c(RMSE = rmse, MAE = mae, R2 = r2))
}

# Create output directory for tables
dir.create(here("outputs/tables"), showWarnings = FALSE)

# --- PART 1: Spatial Block Cross-Validation (4 Folds) ---
cat("\n🗺️ Running 4-Fold Spatial Block Cross-Validation...\n")
cat("⚠️ Strictly filtering out 2024 to prevent temporal leakage in spatial folds...\n")

# FIX: Create a dataset strictly for spatial CV (2018-2023 only)
modelling_data_spatial <- modelling_data %>% filter(year < 2024)
cat("✅ Spatial CV dataset size:", nrow(modelling_data_spatial), "observations (2018-2023).\n")

set.seed(42)
spatial_results <- list()

for (i in 1:4) {
  cat("  Fold", i, "/ 4...\n")
  train_data <- modelling_data_spatial %>% filter(spatial_block != i)
  test_data  <- modelling_data_spatial %>% filter(spatial_block == i)
  
  # 1. Fit GAM
  gam_fold <- mgcv::gam(
    ndvi_anomaly ~ s(elevation) + s(slope_degrees) + s(seasonal_precip) + 
      s(lagged_seasonal_precip) + s(seasonal_temp) + land_cover_class,
    data = train_data, method = "REML"
  )
  pred_gam <- predict(gam_fold, newdata = test_data)
  metrics_gam <- calc_metrics(test_data$ndvi_anomaly, pred_gam)
  
  # 2. Fit Random Forest (FIXED: unbiased permutation importance)
  rf_fold <- ranger(
    ndvi_anomaly ~ .,
    data = train_data %>% select(all_of(c(response, predictors))),
    num.trees = 500, importance = "permutation"
  )
  pred_rf <- predict(rf_fold, data = test_data %>% select(all_of(predictors)))$predictions
  metrics_rf <- calc_metrics(test_data$ndvi_anomaly, pred_rf)
  
  spatial_results[[i]] <- data.frame(
    Fold = i,
    Model = c("GAM", "RF"),
    N_Observations = nrow(test_data),
    RMSE = c(metrics_gam["RMSE"], metrics_rf["RMSE"]),
    MAE = c(metrics_gam["MAE"], metrics_rf["MAE"]),
    R2 = c(metrics_gam["R2"], metrics_rf["R2"])
  )
}

spatial_df <- do.call(rbind, spatial_results)
write_csv(spatial_df, here("outputs/tables/spatial_cv_metrics.csv"))
cat("✅ Saved spatial metrics to: outputs/tables/spatial_cv_metrics.csv\n")

cat("\n--- Spatial Cross-Validation Results (2018-2023) ---\n")
print(spatial_df %>% group_by(Model) %>% summarise(across(c(RMSE, MAE, R2), ~mean(.x, na.rm=TRUE))))

# --- PART 2: Temporal Hold-out (2024) ---
cat("\n⏳ Running Temporal Hold-out Validation (Testing on 2024)...\n")

train_temp <- modelling_data %>% filter(year < 2024)
test_temp  <- modelling_data %>% filter(year == 2024)

if (nrow(test_temp) > 0) {
  cat("✅ Training models on", nrow(train_temp), "obs, testing on", nrow(test_temp), "obs (2024).\n")
  
  # Train final models on 2018-2023
  gam_final <- mgcv::gam(
    ndvi_anomaly ~ s(elevation) + s(slope_degrees) + s(seasonal_precip) + 
      s(lagged_seasonal_precip) + s(seasonal_temp) + land_cover_class,
    data = train_temp, method = "REML"
  )
  pred_gam_temp <- predict(gam_final, newdata = test_temp)
  metrics_gam_temp <- calc_metrics(test_temp$ndvi_anomaly, pred_gam_temp)
  
  rf_final <- ranger(
    ndvi_anomaly ~ .,
    data = train_temp %>% select(all_of(c(response, predictors))),
    num.trees = 500, importance = "permutation"
  )
  pred_rf_temp <- predict(rf_final, data = test_temp %>% select(all_of(predictors)))$predictions
  metrics_rf_temp <- calc_metrics(test_temp$ndvi_anomaly, pred_rf_temp)
  
  # --- REVIEWER 2 FIX: ADD BENCHMARK MODELS ---
  cat("\n📊 Calculating Benchmark Models for 2024...\n")
  
  # Benchmark 1: Zero-Anomaly
  pred_zero <- rep(0, nrow(test_temp))
  metrics_zero <- calc_metrics(test_temp$ndvi_anomaly, pred_zero)
  
  # Benchmark 2: Seasonal Climatology
  season_means <- train_temp %>% 
    group_by(season) %>% 
    summarise(season_mean = mean(ndvi_anomaly, na.rm=TRUE), .groups = "drop")
  
  test_temp_bench <- test_temp %>% left_join(season_means, by = "season")
  pred_clim <- test_temp_bench$season_mean
  metrics_clim <- calc_metrics(test_temp$ndvi_anomaly, pred_clim)
  
  cat("✅ Zero-Anomaly R2:", round(metrics_zero["R2"], 4), "\n")
  cat("✅ Seasonal Climatology R2:", round(metrics_clim["R2"], 4), "\n")
  
  # Save temporal metrics (including benchmarks)
  temporal_df <- data.frame(
    Model = c("Zero_Anomaly", "Seasonal_Climatology", "GAM", "RF"),
    Year = 2024,
    N_Observations = nrow(test_temp),
    RMSE = c(metrics_zero["RMSE"], metrics_clim["RMSE"], metrics_gam_temp["RMSE"], metrics_rf_temp["RMSE"]),
    MAE = c(metrics_zero["MAE"], metrics_clim["MAE"], metrics_gam_temp["MAE"], metrics_rf_temp["MAE"]),
    R2 = c(metrics_zero["R2"], metrics_clim["R2"], metrics_gam_temp["R2"], metrics_rf_temp["R2"])
  )
  write_csv(temporal_df, here("outputs/tables/temporal_holdout_2024_metrics.csv"))
  cat("✅ Saved temporal metrics to: outputs/tables/temporal_holdout_2024_metrics.csv\n")
  
  cat("\n--- 2024 Temporal Hold-out Results ---\n")
  print(temporal_df)
  
  # Plot Observed vs Predicted for RF (FIXED: equal axes)
  plot_data <- test_temp %>% mutate(predicted_anomaly_rf = pred_rf_temp)
  p_val <- ggplot(plot_data, aes(x = ndvi_anomaly, y = predicted_anomaly_rf)) +
    geom_point(alpha = 0.3, color = "#2c3e50") +
    geom_abline(slope = 1, intercept = 0, color = "red", linetype = "dashed", linewidth = 1) +
    coord_equal() + 
    labs(
      title = "Temporal Validation: Observed vs. Predicted NDVI Anomaly (2024)",
      subtitle = paste("Random Forest | R² =", round(metrics_rf_temp["R2"], 3), "| RMSE =", round(metrics_rf_temp["RMSE"], 3)),
      x = "Observed NDVI Anomaly", y = "Predicted NDVI Anomaly"
    ) + theme_minimal() + theme(plot.title = element_text(face = "bold"))
  
  ggsave(here("outputs/figures/14_temporal_validation_2024.png"), p_val, width = 8, height = 6, dpi = 300)
  cat("📊 Saved temporal validation plot.\n")
  
  saveRDS(gam_final, here("data/processed/gam_final_2024.rds"))
  saveRDS(rf_final, here("data/processed/rf_final_2024.rds"))
  
} else {
  cat("⚠️ No 2024 data found. Skipping temporal plot.\n")
}

cat("\n🎉 Step 10 Complete! Rigorous validation finished, leakage fixed, and benchmarks saved.\n")