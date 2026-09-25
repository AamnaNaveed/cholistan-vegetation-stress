# ============================================================================
# Script: 02_define_study_area.R
# Purpose: Download administrative boundaries and define the study area
# ============================================================================

# 1. Install and load required packages
required_packages <- c("sf", "terra", "geodata", "ggplot2", "yaml", "here")

install_if_missing <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg, dependencies = TRUE)
  }
}
lapply(required_packages, install_if_missing)
lapply(required_packages, library, character.only = TRUE)

# 2. Load configuration
config <- read_yaml(here("config.yaml"))

cat("🌍 Downloading Pakistan administrative boundaries (Level 2)...\n")
cat("(This might take a minute depending on your internet speed)\n")

# 3. Download boundaries
# We save it to the 'data/raw' folder
pakistan_boundaries <- geodata::gadm(
  country = "PAK", 
  level = 2, 
  path = here("data/raw")
)

# 4. Filter for our three specific districts
target_districts <- config$study_area$districts

study_area <- pakistan_boundaries[pakistan_boundaries$NAME_2 %in% target_districts, ]

# Convert to sf object for easier handling and plotting
study_area_sf <- sf::st_as_sf(study_area)

cat("✅ Successfully filtered districts:", paste(target_districts, collapse = ", "), "\n")

# 5. Save the study area as a GeoPackage file
sf::st_write(
  study_area_sf, 
  dsn = here(config$study_area$boundary_file), 
  delete_dsn = TRUE
)
cat("💾 Saved study area boundary to:", config$study_area$boundary_file, "\n")

# 6. Create a quick map to verify it looks correct
map_plot <- ggplot() +
  geom_sf(data = study_area_sf, fill = "lightblue", color = "darkblue", linewidth = 0.8) +
  labs(
    title = "Study Area: Cholistan Desert Region",
    subtitle = paste("Districts:", paste(target_districts, collapse = ", "))
  ) +
  theme_minimal()

# Save the map
ggsave(
  here("outputs/figures/01_study_area.png"), 
  map_plot, 
  width = 8, height = 6, dpi = 300
)
cat("🗺️ Saved study area map to: outputs/figures/01_study_area.png\n")

cat("\n🎉 Step 2 Complete! Study area defined and saved.\n")