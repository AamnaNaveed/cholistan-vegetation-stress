# ============================================================================
# Script: 08_rebuild_modelling_table.R
# Purpose: Join aggregated NDVI anomalies with climate/terrain predictors,
#          filter out irrigated cropland, and generate the final clean dataset.
# REVISION: Reads modelling_table_final.csv (which includes slope, elevation, 
#           land_cover) and aggregates to pixel-season level to match Script 07.
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
# This file has: latitude, longitude, date, year, month, season, season_year,
#                elevation, slope_degrees, seasonal_precip, lagged_seasonal_precip,
#                seasonal_temp, land_cover_class, spatial_block
mod_table_final <- read_csv(here("data/processed/modelling_table_final.csv"), show_col_types = FALSE)
cat("✅ Loaded terrain/climate/land cover table:", nrow(mod_table_final), "rows.\n")

# 3. Aggregate climate/terrain data to ONE row per pixel-season to prevent pseudo-replication
# (Since Script 05 joined seasonal climate to 16-day composites, we must collapse it here)
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

# 5. REVIEWER 2 FIX: Filter out irrigated cropland to focus strictly on the arid ecosystem
modelling_data <- modelling_data %>%
  filter(land_cover_class != "Cropland") %>%
  mutate(land_cover_class = as.factor(land_cover_class)) %>%
  na.omit() # Remove any rows with NAs in predictors (e.g., first season lacking lagged precip)

cat("🌵 Filtered out irrigated cropland. Final dataset size:", nrow(modelling_data), "observations.\n")
cat("📊 Remaining land cover distribution:\n")
print(table(modelling_data$land_cover_class))

# 6. Save the clean modelling table
write_csv(modelling_data, here("data/processed/modelling_data_clean.csv"))
cat("💾 Saved clean modelling data to: data/processed/modelling_data_clean.csv\n")

# 7. Generate Data Dictionary
data_dict <- data.frame(
  Variable = c("ndvi_anomaly", "elevation", "slope_degrees", "seasonal_precip",
               "lagged_seasonal_precip", "seasonal_temp", "land_cover_class", "spatial_block"),
  Type = c("Response", "Predictor", "Predictor", "Predictor", "Predictor", "Predictor", "Predictor", "Grouping"),
  Description = c(
    "Standardized seasonal NDVI anomaly (Z-score). Baseline calculated strictly on 2018-2023.",
    "SRTM elevation in meters.",
    "Slope derived from DEM in degrees.",
    "Total seasonal precipitation (mm) from NASA POWER (Dynamic).",
    "Precipitation from the previous season (mm) to account for soil moisture memory (Dynamic).",
    "Mean seasonal temperature (Celsius) from NASA POWER (Dynamic).",
    "MODIS MCD12Q1.061 (2021) IGBP land cover class. Irrigated Cropland excluded.",
    "K-means spatial block ID (1-4) for cross-validation."
  ),
  Source = c("MODIS MOD13Q1", "SRTM DEM", "Derived from DEM", "NASA POWER API",
             "NASA POWER API", "NASA POWER API", "MODIS MCD12Q1.061", "Calculated")
)
write_csv(data_dict, here("data/processed/data_dictionary.csv"))
cat("💾 Saved data dictionary to: data/processed/data_dictionary.csv\n")

# 8. Final Summary
cat("\n--- Final Predictor Summary ---\n")
predictors <- c("elevation", "slope_degrees", "seasonal_precip", "lagged_seasonal_precip", "seasonal_temp", "land_cover_class")
print(summary(modelling_data %>% select(all_of(predictors))))

# 9. Year breakdown (for manuscript)
cat("\n--- Year breakdown (for manuscript Table 1) ---\n")
print(table(modelling_data$year))

cat("\n--- Season breakdown ---\n")
print(table(modelling_data$season))

cat("\n🎉 Step 8 Complete! Modelling table rebuilt, cropland excluded, and pseudo-replication eliminated.\n")