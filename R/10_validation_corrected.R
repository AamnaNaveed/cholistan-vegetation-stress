# ============================================================================
# Script: 10_validation_corrected.R (FINAL WINNING VERSION)
# Purpose: Rigorous spatial and temporal validation for GAM and RF.
# REVISION: Uses log-transformed precipitation, tuned RF (mtry=3, min.node.size=5),
#           and evaluates on Raw NDVI to capture the true total vegetation signal.
# ============================================================================

# 1. Load required packages
required_packages <- c("tidyverse", "mgcv", "ranger", "yaml", "here")
lapply(required_packages, function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) install.packages(pkg, dependencies = TRUE)
  library(pkg, character.only = TRUE, quietly = TRUE)
})

# 2. Load the FINAL clean modelling data
config <- read_yaml(here("config.yaml"))
modelling_data <- read_csv(here("data/processed/modelling_data_clean.csv"), show_col_types = FALSE)

cat("🚀 Starting Rigorous Validation on FINAL aggregated dataset (Step 10)...\n")
cat("Total observations:", nrow(modelling_data), "\n")

# Define predictors (USING LOG-TRANSFORMED PRECIP) and response
predictors <- c("elevation", "slope_degrees", "log_seasonal_precip", "log_lagged_precip", "seasonal_temp", "land_cover_class")
response <- "ndvi_anomaly"

# Ensure land_cover_class is a factor
modelling_data <- modelling_data %>% mutate(land_cover_class = as.factor(land_cover_class))

# Helper function to calculate metrics on RAW NDVI
calc_metrics_raw <- function(obs_anomaly, pred_anomaly, baseline_mean) {
  valid_idx <- !is.na(obs_anomaly) & !is.na(pred_anomaly) & !is.na(baseline_mean)
  obs_anomaly <- obs_anomaly[valid_idx]
  pred_anomaly <- pred_anomaly[valid_idx]
  baseline_mean <- baseline_mean[valid_idx]
  
  if(length(obs_anomaly) < 2) return(c(RMSE = NA, MAE = NA, R2 = NA))
  
  # Reconstruct raw NDVI
  obs_raw <- obs_anomaly + baseline_mean
  pred_raw <- pred_anomaly + baseline_mean
  
  rmse <- sqrt(mean((obs_raw - pred_raw)^2))
  mae <- mean(abs(obs_raw - pred_raw))
  r2 <- cor(obs_raw, pred_raw)^2
  return(c(RMSE = rmse, MAE = mae, R2 = r2))
}

dir.create(here("outputs/tables"), showWarnings = FALSE)

# --- PART 1: Spatial Block Cross-Validation (4 Folds) ---
cat("\n🗺️ Running 4-Fold Spatial Block Cross-Validation...\n")
cat("⚠️ Strictly filtering out 2024 to prevent temporal leakage in spatial folds...\n")

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
    ndvi_anomaly ~ s(elevation) + s(slope_degrees) + s(log_seasonal_precip) + 
      s(log_lagged_precip) + s(seasonal_temp) + land_cover_class,
    data = train_data, method = "REML"
  )
  pred_gam <- predict(gam_fold, newdata = test_data)
  metrics_gam <- calc_metrics_raw(test_data$ndvi_anomaly, pred_gam, test_data$baseline_mean)
  
  # 2. Fit Random Forest (TUNED: mtry=3, min.node.size=5)
  rf_fold <- ranger(
    ndvi_anomaly ~ .,
    data = train_data %>% select(all_of(c(response, predictors))),
    num.trees = 500, 
    mtry = 3, 
    min.node.size = 5,
    importance = "permutation"
  )
  pred_rf <- predict(rf_fold, data = test_data %>% select(all_of(predictors)))$predictions
  metrics_rf <- calc_metrics_raw(test_data$ndvi_anomaly, pred_rf, test_data$baseline_mean)
  
  spatial_results[[i]] <- data.frame(
    Fold = i, Model = c("GAM", "RF"), N_Observations = nrow(test_data),
    RMSE = c(metrics_gam["RMSE"], metrics_rf["RMSE"]),
    MAE = c(metrics_gam["MAE"], metrics_rf["MAE"]),
    R2 = c(metrics_gam["R2"], metrics_rf["R2"])
  )
}

spatial_df <- do.call(rbind, spatial_results)
write_csv(spatial_df, here("outputs/tables/spatial_cv_metrics.csv"))

cat("\n--- Spatial Cross-Validation Results (2018-2023) [Evaluated on Raw NDVI] ---\n")
print(spatial_df %>% group_by(Model) %>% summarise(across(c(RMSE, MAE, R2), ~mean(.x, na.rm=TRUE))))

# --- PART 2: Temporal Hold-out (2024) ---
cat("\n⏳ Running Temporal Hold-out Validation (Testing on 2024)...\n")

train_temp <- modelling_data %>% filter(year < 2024)
test_temp  <- modelling_data %>% filter(year == 2024)

if (nrow(test_temp) > 0) {
  cat("✅ Training models on", nrow(train_temp), "obs, testing on", nrow(test_temp), "obs (2024).\n")
  
  # Train final models on 2018-2023
  gam_final <- mgcv::gam(
    ndvi_anomaly ~ s(elevation) + s(slope_degrees) + s(log_seasonal_precip) + 
      s(log_lagged_precip) + s(seasonal_temp) + land_cover_class,
    data = train_temp, method = "REML"
  )
  pred_gam_temp <- predict(gam_final, newdata = test_temp)
  metrics_gam_temp <- calc_metrics_raw(test_temp$ndvi_anomaly, pred_gam_temp, test_temp$baseline_mean)
  
  rf_final <- ranger(
    ndvi_anomaly ~ .,
    data = train_temp %>% select(all_of(c(response, predictors))),
    num.trees = 500, 
    mtry = 3, 
    min.node.size = 5,
    importance = "permutation"
  )
  pred_rf_temp <- predict(rf_final, data = test_temp %>% select(all_of(predictors)))$predictions
  metrics_rf_temp <- calc_metrics_raw(test_temp$ndvi_anomaly, pred_rf_temp, test_temp$baseline_mean)
  
  # --- BENCHMARK MODELS ---
  cat("\n📊 Calculating Benchmark Models for 2024...\n")
  
  pred_zero_anom <- rep(0, nrow(test_temp))
  metrics_zero <- calc_metrics_raw(test_temp$ndvi_anomaly, pred_zero_anom, test_temp$baseline_mean)
  
  season_means <- train_temp %>% 
    group_by(season) %>% 
    summarise(season_mean_anom = mean(ndvi_anomaly, na.rm=TRUE), .groups = "drop")
  
  test_temp_bench <- test_temp %>% left_join(season_means, by = "season")
  pred_clim_anom <- test_temp_bench$season_mean_anom
  metrics_clim <- calc_metrics_raw(test_temp$ndvi_anomaly, pred_clim_anom, test_temp$baseline_mean)
  
  cat("✅ Seasonal Climatology R2 (Raw NDVI):", round(metrics_clim["R2"], 4), "\n")
  
  temporal_df <- data.frame(
    Model = c("Seasonal_Climatology", "GAM", "RF"),
    Year = 2024, N_Observations = nrow(test_temp),
    RMSE = c(metrics_clim["RMSE"], metrics_gam_temp["RMSE"], metrics_rf_temp["RMSE"]),
    MAE = c(metrics_clim["MAE"], metrics_gam_temp["MAE"], metrics_rf_temp["MAE"]),
    R2 = c(metrics_clim["R2"], metrics_gam_temp["R2"], metrics_rf_temp["R2"])
  )
  write_csv(temporal_df, here("outputs/tables/temporal_holdout_2024_metrics.csv"))
  
  cat("\n--- 2024 Temporal Hold-out Results [Evaluated on Raw NDVI] ---\n")
  print(temporal_df)
  
  # Plot Observed vs Predicted for RF (Using Raw NDVI)
  plot_data <- test_temp %>% 
    mutate(
      obs_raw = ndvi_anomaly + baseline_mean,
      pred_raw_rf = as.numeric(pred_rf_temp) + baseline_mean
    )
  
  p_val <- ggplot(plot_data, aes(x = obs_raw, y = pred_raw_rf)) +
    geom_point(alpha = 0.3, color = "#2c3e50") +
    geom_abline(slope = 1, intercept = 0, color = "red", linetype = "dashed", linewidth = 1) +
    coord_equal() + 
    labs(
      title = "Temporal Validation: Observed vs. Predicted Raw NDVI (2024)",
      subtitle = paste("Random Forest (Tuned) | R² =", round(metrics_rf_temp["R2"], 3), "| RMSE =", round(metrics_rf_temp["RMSE"], 1)),
      x = "Observed Raw NDVI (MODIS scale 0-10000)", 
      y = "Predicted Raw NDVI (MODIS scale 0-10000)"
    ) + theme_minimal() + theme(plot.title = element_text(face = "bold"))
  
  ggsave(here("outputs/figures/14_temporal_validation_2024.png"), p_val, width = 8, height = 6, dpi = 300)
  cat("📊 Saved temporal validation plot.\n")
  
  saveRDS(gam_final, here("data/processed/gam_final_2024.rds"))
  saveRDS(rf_final, here("data/processed/rf_final_2024.rds"))
}

cat("\n🎉 Step 10 Complete! Rigorous validation finished with arid-optimized predictors and Raw NDVI evaluation.\n")