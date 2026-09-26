# ============================================================================
# Script: 05_rebuild_modelling_table.R
# Purpose: Finalize the modelling table, define the strict predictor list, 
#          and generate a data dictionary. (PDF Step 5)
# ============================================================================

required_packages <- c("tidyverse", "yaml", "here")
lapply(required_packages, function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) install.packages(pkg, dependencies = TRUE)
  library(pkg, character.only = TRUE, quietly = TRUE)
})

config <- read_yaml(here("config.yaml"))
mod_table <- read_csv(here("data/processed/modelling_table_final.csv"), show_col_types = FALSE)

cat(" Rebuilding final modelling table and defining predictors (Step 5)...\n")

# 1. STRICT PREDICTOR DEFINITION
# We now have genuine, independent predictors. No circularity.
predictors <- c(
  "elevation", 
  "slope_degrees", 
  "seasonal_precip", 
  "lagged_seasonal_precip", 
  "seasonal_temp", 
  "land_cover_class" # Genuine MODIS MCD12Q1.061 (2021)
)
response <- "ndvi_anomaly"

# 2. Clean the data
# We must remove rows where the dynamic climate data is missing (e.g., the very first season has no lagged precip)
# We also ensure land_cover_class is a factor for the Random Forest model.
modelling_data <- mod_table %>%
  select(all_of(c(
    "latitude", "longitude", "date", "year", "season", 
    response, predictors, "spatial_block"
  ))) %>%
  mutate(land_cover_class = as.factor(land_cover_class)) %>%
  na.omit() # Removes rows with NA in any predictor or response

cat("✅ Final dataset has", nrow(modelling_data), "valid observations for modelling.\n")
cat("(Rows removed due to missing lagged precipitation or other NAs.)\n")

# 3. Save the clean modelling table
write_csv(modelling_data, here("data/processed/modelling_data_clean.csv"))
cat(" Saved clean modelling data to: data/processed/modelling_data_clean.csv\n")

# 4. Generate Data Dictionary (PDF Requirement)
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
    "Genuine MODIS MCD12Q1.061 (2021) IGBP land cover class (Bare_Sparse, Grass_Shrub, Cropland, Other).",
    "K-means spatial block ID (1-4) for cross-validation."
  ),
  Source = c("MODIS MOD13Q1", "SRTM DEM", "Derived from DEM", "NASA POWER API", 
             "NASA POWER API", "NASA POWER API", "MODIS MCD12Q1.061", "Calculated")
)

write_csv(data_dict, here("data/processed/data_dictionary.csv"))
cat(" Saved data dictionary to: data/processed/data_dictionary.csv\n")

# 5. Final Summary
cat("\n--- Final Predictor Summary ---\n")
print(summary(modelling_data %>% select(all_of(predictors))))

cat("\n🎉 Step 5 Complete! Modelling table rebuilt with genuine, non-circular predictors.\n")