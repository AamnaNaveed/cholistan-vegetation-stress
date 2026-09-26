# ============================================================================
# Script: 09_validation.R
# Purpose: Validate the Random Forest model (Updated with Outlier Clipping)
# ============================================================================

# 1. Install and load required packages
required_packages <- c("tidyverse", "ranger", "yardstick", "yaml", "here")

install_if_missing <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg, dependencies = TRUE)
  }
}
lapply(required_packages, install_if_missing)
lapply(required_packages, library, character.only = TRUE)

# 2. Load configuration and the modelling table
config <- read_yaml(here("config.yaml"))
mod_table <- read_csv(here("data/processed/modelling_table_with_blocks.csv"), show_col_types = FALSE)

# CRITICAL FIX 1: Ensure 'season' is treated as a category
mod_table <- mod_table %>%
  mutate(season = as.factor(season))

# CRITICAL FIX 2: Clip extreme outliers (Winsorize)
# We cap the NDVI anomaly between -3 and +3 to prevent the model from shrinking to the mean
mod_table <- mod_table %>%
  mutate(
    ndvi_anomaly_clipped = pmax(pmin(ndvi_anomaly, 3), -3)
  )

cat(" Starting Model Validation (Step 9)...\n")

# Define predictors and response (using the CLIPPED version)
predictors <- c("elevation", "annual_precip_mm", "precip_seasonality", "season")
response <- "ndvi_anomaly_clipped"

# --- PART 1: Spatial Block Cross-Validation ---
cat("\n🗺️ Running 4-Fold Spatial Block Cross-Validation...\n")
set.seed(42)

spatial_metrics <- list()

for (i in 1:4) {
  train_data <- mod_table %>% filter(spatial_block != i)
  test_data <- mod_table %>% filter(spatial_block == i)
  
  rf_spatial <- ranger(
    ndvi_anomaly_clipped ~ .,
    data = train_data %>% select(all_of(c(response, predictors))),
    num.trees = 500,
    importance = "impurity"
  )
  
  preds <- predict(rf_spatial, data = test_data %>% select(all_of(predictors)))$predictions
  
  rmse_val <- sqrt(mean((test_data$ndvi_anomaly_clipped - preds)^2))
  r2_val <- cor(test_data$ndvi_anomaly_clipped, preds)^2
  
  spatial_metrics[[i]] <- data.frame(Fold = i, RMSE = rmse_val, R2 = r2_val)
  cat("  Fold", i, "- RMSE:", round(rmse_val, 3), "| R²:", round(r2_val, 3), "\n")
}

spatial_results <- do.call(rbind, spatial_metrics)
cat("\n✅ Average Spatial CV RMSE:", round(mean(spatial_results$RMSE), 3), "\n")
cat("✅ Average Spatial CV R²:", round(mean(spatial_results$R2), 3), "\n")

# --- PART 2: Temporal Hold-out (2024) ---
cat("\n⏳ Running Temporal Hold-out Validation (Testing on 2024)...\n")

train_temporal <- mod_table %>% filter(year < 2024)
test_temporal <- mod_table %>% filter(year == 2024)

if (nrow(test_temporal) > 0) {
  rf_temporal <- ranger(
    ndvi_anomaly_clipped ~ .,
    data = train_temporal %>% select(all_of(c(response, predictors))),
    num.trees = 500,
    importance = "impurity"
  )
  
  preds_temp <- predict(rf_temporal, data = test_temporal %>% select(all_of(predictors)))$predictions
  
  rmse_temp <- sqrt(mean((test_temporal$ndvi_anomaly_clipped - preds_temp)^2))
  r2_temp <- cor(test_temporal$ndvi_anomaly_clipped, preds_temp)^2
  
  cat("✅ Temporal Hold-out RMSE:", round(rmse_temp, 3), "\n")
  cat("✅ Temporal Hold-out R²:", round(r2_temp, 3), "\n")
  
  plot_data <- test_temporal %>%
    mutate(predicted_ndvi = preds_temp)
} else {
  cat("️ No 2024 data found. Skipping temporal plot.\n")
  plot_data <- NULL
}

# --- PART 3: Visualize Validation ---
cat("\n📈 Generating Observed vs. Predicted plot...\n")

if (!is.null(plot_data)) {
  p_val <- ggplot(plot_data, aes(x = ndvi_anomaly_clipped, y = predicted_ndvi)) +
    geom_point(alpha = 0.4, color = "#2c3e50") +
    geom_abline(slope = 1, intercept = 0, color = "red", linetype = "dashed", linewidth = 1) +
    labs(
      title = "Temporal Validation: Observed vs. Predicted NDVI Anomaly (2024)",
      subtitle = paste("R² =", round(r2_temp, 2), "| RMSE =", round(rmse_temp, 2)),
      x = "Observed NDVI Anomaly (Clipped to +/- 3)",
      y = "Predicted NDVI Anomaly"
    ) +
    theme_minimal() +
    theme(plot.title = element_text(face = "bold"))
  
  ggsave(here("outputs/figures/09_validation_plot.png"), p_val, width = 8, height = 6, dpi = 300)
  cat("✅ Saved validation plot to: outputs/figures/09_validation_plot.png\n")
}

cat("\n🎉 Step 9 Complete! Model validation finished.\n")