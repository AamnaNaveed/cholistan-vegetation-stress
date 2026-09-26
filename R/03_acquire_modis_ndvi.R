# ============================================================================
# Script: 04_acquire_modis_ndvi.R
# Purpose: Download full 200-point, 7-year MODIS NDVI time-series with auto-backups
# ============================================================================

# 1. Install and load required packages
required_packages <- c("sf", "terra", "MODISTools", "yaml", "here")

install_if_missing <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg, dependencies = TRUE)
  }
}
lapply(required_packages, install_if_missing)
lapply(required_packages, library, character.only = TRUE)

# 2. Load configuration and study area
config <- read_yaml(here("config.yaml"))
study_area <- sf::st_read(here(config$study_area$boundary_file), quiet = TRUE)

cat("🚀 Setting up FULL 200-point MODIS NDVI download (2018-2024)...\n")

# 3. Create a regular grid of 200 sample points
set.seed(42) 
sample_points <- st_sample(study_area, size = 200, type = "regular") 
points_sf <- st_as_sf(sample_points)
points_sf$point_id <- 1:nrow(points_sf)

cat("✅ Created a grid of", nrow(points_sf), "sample points.\n")

# 4. Download MODIS NDVI (MOD13Q1) time-series
cat("🛰️ Downloading 7 years of data. This will take 10-15 minutes...\n")
cat("Do not close RStudio. Let it run in the background.\n\n")

coords <- st_coordinates(points_sf)
lats <- coords[, "Y"]
lons <- coords[, "X"]

ndvi_list <- list()

# Loop through each point
for (i in 1:length(lats)) {
  cat("Downloading point", i, "of 200...\n")
  
  # tryCatch ensures that if ONE point fails, the script doesn't crash
  temp_data <- tryCatch({
    mt_subset(
      product = "MOD13Q1",       
      lat = lats[i],
      lon = lons[i],
      band = "250m_16_days_NDVI", 
      start = "2018-01-01",
      end = "2024-12-31",
      km_lr = 0,                 
      km_ab = 0,
      site_name = paste0("point_", i),
      progress = FALSE 
    )
  }, error = function(e) {
    cat("  ⚠️ Warning: Point", i, "timed out. Skipping and moving to next.\n")
    return(NULL)
  })
  
  if (!is.null(temp_data)) {
    ndvi_list[[i]] <- temp_data
  }
  
  # 🛡️ AUTO-BACKUP: Save progress every 50 points
  if (i %% 50 == 0) {
    temp_combined <- do.call(rbind, ndvi_list)
    write.csv(temp_combined, here("data/processed/ndvi_timeseries_partial.csv"), row.names = FALSE)
    cat(" Auto-saved backup at point", i, "\n\n")
  }
  
  # ⏳ THE MAGIC FIX: Pause for 1.5 seconds to prevent NASA API throttling
  Sys.sleep(1.5) 
}

# 5. Combine and save final data
if (length(ndvi_list) > 0) {
  ndvi_data <- do.call(rbind, ndvi_list)
  
  write.csv(ndvi_data, here("data/processed/ndvi_timeseries.csv"), row.names = FALSE)
  cat("\n✅ Successfully downloaded", length(ndvi_list), "out of 200 points.\n")
  cat("💾 Saved final NDVI time-series to: data/processed/ndvi_timeseries.csv\n")
  
  # Quick visual check
  plot(study_area["NAME_2"], main = "200 Sample Points for NDVI Extraction")
  plot(points_sf, add = TRUE, pch = 16, col = "red", cex = 1)
  
  cat("\n Step 4 Complete! Full MODIS NDVI dataset acquired.\n")
} else {
  cat("\n❌ All downloads failed. Check your internet connection.\n")
}