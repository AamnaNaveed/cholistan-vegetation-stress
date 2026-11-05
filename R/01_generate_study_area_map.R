# ============================================================================
# Script: 01_generate_study_area_map_v2.R
# Purpose: Generate a professional, publication-quality study area map (Figure 1)
# Improvements: Filled study area polygon, white halos on points, embedded 
#               inset map, and a clean, minimalist cartographic theme.
# ============================================================================

# 1. Install and load required packages
required_packages <- c("tidyverse", "sf", "rnaturalearth", "rnaturalearthdata", "ggspatial", "cowplot")
install_if_missing <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg, dependencies = TRUE)
  }
}
lapply(required_packages, install_if_missing)
lapply(required_packages, library, character.only = TRUE, quietly = TRUE)

dir.create(here("outputs/figures"), showWarnings = FALSE)

cat("🗺️ Generating Professional Study Area Map (Figure 1)...\n")

# 2. Load the clean modelling data to extract unique sampling coordinates
modelling_data <- read_csv(here("data/processed/modelling_data_clean.csv"), show_col_types = FALSE)

# Extract unique pixel coordinates
sampling_points <- modelling_data %>%
  distinct(latitude, longitude) %>%
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326)

cat("✅ Extracted", nrow(sampling_points), "unique sampling coordinates.\n")

# Create a "Convex Hull" polygon around the points to define the study area visually
study_area_hull <- sampling_points %>% st_convex_hull()
bbox <- st_bbox(sampling_points)

# 3. Get base maps
world <- ne_countries(scale = "medium", returnclass = "sf")
pakistan <- ne_countries(country = "Pakistan", scale = "medium", returnclass = "sf")

# 4. Create the Main Map (Cholistan Region)
# We use a clean, minimalist theme with specific colors for land and the study area
p_main <- ggplot() +
  # Pakistan background (light grey land, subtle borders)
  geom_sf(data = pakistan, fill = "#f4f4f4", color = "grey60", size = 0.3) +
  
  # The Study Area (Light orange fill, dark orange border)
  geom_sf(data = study_area_hull, fill = "#fee6ce", color = "#d95f02", size = 1.2, alpha = 0.8) +
  
  # The Sampling Points (Red dots with a white "halo" to make them pop)
  geom_sf(data = sampling_points, color = "#d73027", size = 2, stroke = 0.6, shape = 21, fill = "#d73027") +
  
  # Focus the map extent on the study area with some padding
  coord_sf(xlim = c(bbox["xmin"] - 0.8, bbox["xmax"] + 0.8), 
           ylim = c(bbox["ymin"] - 0.8, bbox["ymax"] + 0.8),
           expand = FALSE) +
  
  # CARTOGRAPHY RULES: Scale Bar and North Arrow
  annotation_scale(location = "bl", width_hint = 0.3, text_cex = 0.9, bar_cols = c("black", "white")) +
  annotation_north_arrow(location = "tl", which_north = "true", 
                         pad_x = unit(0.2, "in"), pad_y = unit(0.2, "in"),
                         style = north_arrow_fancy_orienteering) +
  
  # Clean labels
  labs(title = "Study Area: Cholistan Desert, Pakistan",
       subtitle = "200 sampled MODIS pixels (red dots) within the arid ecosystem") +
  
  # Professional Theme
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 16, hjust = 0, margin = margin(b = 5)),
    plot.subtitle = element_text(size = 12, color = "grey40", hjust = 0, margin = margin(b = 15)),
    axis.text = element_text(size = 10, color = "black"),
    axis.title = element_blank(),
    panel.grid.major = element_blank(), # Remove grid lines for a cleaner look
    panel.grid.minor = element_blank(),
    panel.background = element_rect(fill = "#f9f9f9") # Very subtle background
  )

# 5. Create the Inset Map (World with Pakistan highlighted)
p_inset <- ggplot() +
  geom_sf(data = world, fill = "#f4f4f4", color = "grey80", size = 0.2) +
  # Highlight Pakistan in dark orange
  geom_sf(data = pakistan, fill = "#d95f02", color = "black", size = 0.5) +
  # Draw a red dashed box showing where the main map is located
  geom_sf(data = st_as_sfc(bbox), fill = NA, color = "#d73027", linetype = "dashed", size = 1.2) +
  theme_void() +
  theme(plot.margin = margin(0, 0, 0, 0))

# 6. Combine using cowplot to embed the inset map into the bottom-right corner
# x=0.62, y=0.05 places it in the bottom right. Adjust if needed.
final_map <- ggdraw(p_main) + 
  draw_plot(p_inset, x = 0.62, y = 0.05, width = 0.35, height = 0.35)

# 7. Save the final high-resolution map
ggsave(here("outputs/figures/01_study_area_map_v2.png"), final_map, width = 12, height = 9, dpi = 300)
cat("💾 Saved Figure 1 to: outputs/figures/01_study_area_map_v2.png\n")

cat("\n🎉 Professional map generation complete!\n")