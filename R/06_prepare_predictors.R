# ============================================================================
# Script: 06_prepare_predictors.R
# Purpose: Extract terrain and climate predictors to points and build the master modelling table
# ============================================================================

# 1. Install and load required packages
required_packages <- c("tidyverse", "terra", "sf", "yaml", "here")

install_if_missing <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg, dependencies = TRUE)
  }
}
lapply(required_packages, install_if_missing)
lapply(required_packages, library, character.only = TRUE)

# 2. Load configuration and the NDVI anomaly dataset
config <- read_yaml(here("config.yaml"))
ndvi_anomaly <- read_csv(here("data/processed/ndvi_anomaly_response.csv"), show_col_types = FALSE)

cat("🌍 Building the final master modelling table...\n")
cat("Starting with", nrow(ndvi_anomaly), "NDVI observations.\n")

# 3. Load the terrain and climate rasters
cat("Loading DEM and Climate rasters...\n")
dem_rast <- rast(here("data/processed/dem_srtm.tif"))
climate_rast <- rast(here("data/processed/climate_worldclim.tif"))

# 4. Convert our point data into a spatial object
# MODISTools provides 'longitude' and 'latitude' columns
points_sf <- st_as_sf(ndvi_anomaly, coords = c("longitude", "latitude"), crs = 4326)
points_spat <- vect(points_sf)

# 5. Extract raster values to each point
cat("Extracting elevation and climate values to sample points...\n")
dem_vals <- terra::extract(dem_rast, points_spat)
clim_vals <- terra::extract(climate_rast, points_spat)

# 6. Combine everything into one clean table
# terra::extract returns an ID column and the value column. We take the value column.
modelling_table <- ndvi_anomaly %>%
  mutate(
    elevation = dem_vals[[2]],          # The second column is the DEM value
    annual_precip_mm = clim_vals[[2]],  # Bio12: Annual Precipitation
    precip_seasonality = clim_vals[[3]] # Bio15: Precipitation Seasonality
  )

# 7. Clean up and save
# Remove any rows where extraction failed (returned NA)
modelling_table <- modelling_table %>%
  filter(!is.na(elevation), !is.na(annual_precip_mm))

cat("✅ Final modelling table has", nrow(modelling_table), "rows and", ncol(modelling_table), "columns.\n")

write_csv(modelling_table, here("data/processed/modelling_table.csv"))
cat("💾 Saved modelling table to: data/processed/modelling_table.csv\n")

# 8. Quick visual check: Summary of predictors
cat("\n--- Summary of Predictors ---\n")
print(summary(modelling_table %>% select(elevation, annual_precip_mm, precip_seasonality, ndvi_anomaly)))

cat("\n🎉 Step 6 Complete! Master modelling table built and saved.\n")