# ============================================================================
# Script: 04e_add_slope.R
# Purpose: Calculate slope and add it to the final modelling table.
# ============================================================================

required_packages <- c("tidyverse", "terra", "sf", "yaml", "here")
lapply(required_packages, function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) install.packages(pkg, dependencies = TRUE)
  library(pkg, character.only = TRUE, quietly = TRUE)
})

config <- read_yaml(here("config.yaml"))
mod_table <- read_csv(here("data/processed/modelling_table_final.csv"), show_col_types = FALSE)

cat("⛰️ Calculating slope from DEM and adding to table...\n")

# 1. Calculate Slope
dem_rast <- rast(here("data/processed/dem_srtm.tif"))
slope_rast <- terra::terrain(dem_rast, v = "slope", unit = "degrees")

# 2. Extract to points
points_sf <- st_as_sf(mod_table, coords = c("longitude", "latitude"), crs = 4326)
points_spat <- vect(points_sf)

slope_vals <- terra::extract(slope_rast, points_spat)[[2]]

# 3. Add to table and save
mod_table$slope_degrees <- slope_vals

write_csv(mod_table, here("data/processed/modelling_table_final.csv"))
cat("✅ Done! Slope added to modelling_table_final.csv.\n")