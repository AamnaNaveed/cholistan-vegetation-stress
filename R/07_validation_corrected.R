# ============================================================================
# Script: 07_validation_corrected.R
# Purpose: Rigorous spatial and temporal validation for GAM and RF.
# Reference: PDF Step 7 (Section 1.8.7)
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

cat(" Starting Rigorous Validation (Step 7)...\n")

# Define predictors and response
predictors <- c("elevation", "slope_degrees", "seasonal_precip", "lagged_seasonal_precip", "seasonal_temp", "land_cover_class")
response <- "ndvi_anomaly"

# Ensure land_cover_class is a factor
modelling_data <- modelling_data %>% mutate(land_cover_class = as.factor(land_cover_class))

# Helper function to calculate metrics
calc_metrics <- function(obs, pred) {
  rmse <- sqrt(mean((obs - pred)^2))
  mae <- mean(abs(obs - pred))
  r2 <- cor(obs, pred)^2
  return(c(RMSE = rmse, MAE = mae, R2 = r2))
}

# --- PART 1: Spatial Block Cross-Validation (4 Folds) ---
cat("\n🗺️ Running 4-Fold Spatial Block Cross-Validation...\n")
set.seed(42)

spatial_results <- list()

for (i in 1:4) {
  cat("  Fold", i, "/ 4...\n")
  train_data <- modelling_data %>% filter(spatial_block != i)
  test_data <- modelling_data %>% filter(spatial_block == i)
  
  # 1. Fit GAM
  gam_fold <- mgcv::gam(
    ndvi_anomaly ~ s(elevation) + s(slope_degrees) + s(seasonal_precip) + 
      s(lagged_seasonal_precip) + s(seasonal_temp) + land_cover_class,
    data = train_data, method = "REML"
  )
  pred_gam <- predict(gam_fold, newdata = test_data)
  metrics_gam <- calc_metrics(test_data$ndvi_anomaly, pred_gam)
  
  # 2. Fit Random Forest
  rf_fold <- ranger(
    ndvi_anomaly ~ .,
    data = train_data %>% select(all_of(c(response, predictors))),
    num.trees = 500, importance = "impurity"
  )
  pred_rf <- predict(rf_fold, data = test_data %>% select(all_of(predictors)))$predictions
  metrics_rf <- calc_metrics(test_data$ndvi_anomaly, pred_rf)
  
  # Store results
  spatial_results[[i]] <- data.frame(
    Fold = i,
    Model = c("GAM", "RF"),
    RMSE = c(metrics_gam["RMSE"], metrics_rf["RMSE"]),
    MAE = c(metrics_gam["MAE"], metrics_rf["MAE"]),
    R2 = c(metrics_gam["R2"], metrics_rf["R2"])
  )
}

spatial_df <- do.call(rbind, spatial_results)
cat("\n--- Spatial Cross-Validation Results ---\n")
print(spatial_df %>% group_by(Model) %>% summarise(across(c(RMSE, MAE, R2), ~mean(.x))))

# --- PART 2: Temporal Hold-out (2024) ---
cat("\n⏳ Running Temporal Hold-out Validation (Testing on 2024)...\n")

train_temp <- modelling_data %>% filter(year < 2024)
test_temp <- modelling_data %>% filter(year == 2024)

if (nrow(test_temp) > 0) {
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
    num.trees = 500, importance = "impurity"
  )
  pred_rf_temp <- predict(rf_final, data = test_temp %>% select(all_of(predictors)))$predictions
  metrics_rf_temp <- calc_metrics(test_temp$ndvi_anomaly, pred_rf_temp)
  
  cat("\n--- 2024 Temporal Hold-out Results ---\n")
  cat("GAM  - RMSE:", round(metrics_gam_temp["RMSE"], 3), "| MAE:", round(metrics_gam_temp["MAE"], 3), "| R²:", round(metrics_gam_temp["R2"], 3), "\n")
  cat("RF   - RMSE:", round(metrics_rf_temp["RMSE"], 3), "| MAE:", round(metrics_rf_temp["MAE"], 3), "| R²:", round(metrics_rf_temp["R2"], 3), "\n")
  
  # Plot Observed vs Predicted for RF (usually performs better on complex data)
  plot_data <- test_temp %>% mutate(predicted_anomaly_rf = pred_rf_temp)
  
  p_val <- ggplot(plot_data, aes(x = ndvi_anomaly, y = predicted_anomaly_rf)) +
    geom_point(alpha = 0.3, color = "#2c3e50") +
    geom_abline(slope = 1, intercept = 0, color = "red", linetype = "dashed", linewidth = 1) +
    labs(
      title = "Temporal Validation: Observed vs. Predicted NDVI Anomaly (2024)",
      subtitle = paste("Random Forest | R² =", round(metrics_rf_temp["R2"], 2), "| RMSE =", round(metrics_rf_temp["RMSE"], 2)),
      x = "Observed NDVI Anomaly", y = "Predicted NDVI Anomaly"
    ) +
    theme_minimal() + theme(plot.title = element_text(face = "bold"))
  
  ggsave(here("outputs/figures/14_temporal_validation_2024.png"), p_val, width = 8, height = 6, dpi = 300)
  cat(" Saved temporal validation plot to: outputs/figures/14_temporal_validation_2024.png\n")
  
  # Save models for the next step (mapping)
  saveRDS(gam_final, here("data/processed/gam_final_2024.rds"))
  saveRDS(rf_final, here("data/processed/rf_final_2024.rds"))
  
} else {
  cat("️ No 2024 data found. Skipping temporal plot.\n")
}

cat("\n🎉 Step 7 Complete! Rigorous validation finished.\n")