# ============================================================================
# Script: 08_rebuild_modelling_table.R
# Purpose: Join aggregated NDVI anomalies with climate/terrain predictors,
#          apply log-transform to precipitation (critical for arid ecosystems),
#          filter out irrigated cropland, and generate the final clean dataset.
# ============================================================================

required_packages <- c("tidyverse", "yaml", "here")
lapply(required_packages, function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) install.packages(pkg, dependencies = TRUE)
  library(pkg, character.only = TRUE, quietly = TRUE)
})

config <- read_yaml(here("config.yaml"))

cat("🔄 Rebuilding final modelling table (Step 8)...\n")

# 1. Load the aggregated anomaly response (from Script 07)
ndvi_anomaly <- read_csv(here("data/processed/ndvi_anomaly_response.csv"), show_col_types = FALSE)
cat("✅ Loaded aggregated NDVI anomaly data:", nrow(ndvi_anomaly), "pixel-season observations.\n")

# 2. Load the FULL terrain + climate + land cover table (from Script 06)
mod_table_final <- read_csv(here("data/processed/modelling_table_final.csv"), show_col_types = FALSE)
cat("✅ Loaded terrain/climate/land cover table:", nrow(mod_table_final), "rows.\n")

# 3. Aggregate climate/terrain data to ONE row per pixel-season
climate_aggregated <- mod_table_final %>%
  group_by(latitude, longitude, year, season) %>%
  summarise(
    elevation = first(elevation),
    slope_degrees = first(slope_degrees),
    land_cover_class = first(land_cover_class),
    spatial_block = first(spatial_block),
    seasonal_precip = first(seasonal_precip),
    seasonal_temp = first(seasonal_temp),
    lagged_seasonal_precip = first(lagged_seasonal_precip),
    .groups = "drop"
  )

cat("✅ Aggregated climate/terrain data to", nrow(climate_aggregated), "pixel-season observations.\n")

# 4. Join anomaly data with climate/terrain data
modelling_data <- ndvi_anomaly %>%
  inner_join(climate_aggregated, by = c("latitude", "longitude", "year", "season"))

cat("✅ Joined datasets. Total observations before land cover filtering:", nrow(modelling_data), "\n")

# 5. REVIEWER 2 FIX: Filter out irrigated cropland + APPLY LOG TRANSFORM
modelling_data <- modelling_data %>%
  filter(land_cover_class != "Cropland") %>%
  mutate(
    land_cover_class = as.factor(land_cover_class),
    # CRITICAL FIX FOR ARID ECOSYSTEMS: Log-transform precipitation
    # log1p(x) = log(x + 1), which handles zeros gracefully and spreads out small values
    log_seasonal_precip = log1p(seasonal_precip),
    log_lagged_precip = log1p(lagged_seasonal_precip)
  ) %>%
  na.omit() # Remove any rows with NAs

cat("🌵 Filtered out irrigated cropland and applied log-transform to precipitation.\n")
cat("🌵 Final dataset size:", nrow(modelling_data), "observations.\n")

# 6. Save the clean modelling table
write_csv(modelling_data, here("data/processed/modelling_data_clean.csv"))
cat("💾 Saved clean modelling data to: data/processed/modelling_data_clean.csv\n")

# 7. Final Summary
cat("\n--- Final Predictor Summary ---\n")
# Note: We will use the log versions in the models now
predictors <- c("elevation", "slope_degrees", "log_seasonal_precip", "log_lagged_precip", "seasonal_temp", "land_cover_class")
print(summary(modelling_data %>% select(all_of(predictors))))

cat("\n🎉 Step 8 Complete! Modelling table rebuilt with arid-optimized predictors.\n")