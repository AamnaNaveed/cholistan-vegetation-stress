# 4. Download WorldClim Bioclimatic Variables (10-minute resolution, ~1km)
cat("🌧️ Downloading WorldClim climate data...\n")
# Download all bioclim variables first
climate_all <- geodata::worldclim_global(
  var = "bio",
  res = 10,
  path = here("data/raw")
)

# Keep only Bio12 (Annual Precipitation) and Bio15 (Precipitation Seasonality)
# We use indices 12 and 15 because the layer names can vary by version
climate <- climate_all[[c(12, 15)]]

# Rename them to keep our code clean
names(climate) <- c("bio12", "bio15")

# Crop and mask
climate <- terra::crop(climate, study_area)
climate <- terra::mask(climate, study_area)

# Save the climate rasters
writeRaster(climate, here("data/processed/climate_worldclim.tif"), overwrite = TRUE)
cat("✅ WorldClim data saved to: data/processed/climate_worldclim.tif\n")