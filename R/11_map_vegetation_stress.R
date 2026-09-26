# ============================================================================
# Script: 11_map_vegetation_stress.R
# Purpose: Calculate model residuals to map vegetation stress across the study area
# ============================================================================

# 1. Install and load required packages
required_packages <- c("tidyverse", "ranger", "sf", "yaml", "here")

install_if_missing <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg, dependencies = TRUE)
  }
}
lapply(required_packages, install_if_missing)
lapply(required_packages, library, character.only = TRUE)

# 2. Load data
config <- read_yaml(here("config.yaml"))
ndvi_response <- read_csv(here("data/processed/ndvi_anomaly_response.csv"), show_col_types = FALSE)
mod_table <- read_csv(here("data/processed/modelling_table_with_blocks.csv"), show_col_types = FALSE)
study_area <- st_read(here(config$study_area$boundary_file), quiet = TRUE)

cat("️ Generating Final Vegetation Stress Map (Step 11)...\n")

# 3. Merge data to get everything in one place
full_data <- ndvi_response %>%
  left_join(mod_table %>% select(latitude, longitude, date, elevation, annual_precip_mm, precip_seasonality), 
            by = c("latitude", "longitude", "date")) %>%
  na.omit() %>%
  mutate(season = as.factor(season))

# 4. Train the FINAL model on ALL data (since we are done validating)
cat("Training final model on all data...\n")
set.seed(42)
final_rf <- ranger(
  ndvi_value ~ elevation + annual_precip_mm + precip_seasonality + season,
  data = full_data,
  num.trees = 500,
  importance = "impurity"
)

# 5. Predict and calculate residuals (Stress)
# Residual = Actual - Predicted. Negative means it's browner than expected (Stress).
full_data <- full_data %>%
  mutate(
    predicted_ndvi = predict(final_rf, data = .)$predictions,
    residual = ndvi_value - predicted_ndvi
  )

# 6. Calculate average stress per location
stress_map_data <- full_data %>%
  group_by(latitude, longitude) %>%
  summarise(
    avg_stress = mean(residual, na.rm = TRUE),
    .groups = "drop"
  )

# Convert to spatial points
stress_points <- st_as_sf(stress_map_data, coords = c("longitude", "latitude"), crs = 4326)

# 7. Plot the map
cat(" Plotting the map...\n")
p_stress <- ggplot() +
  geom_sf(data = study_area, fill = "#f0f0f0", color = "black", linewidth = 0.5) +
  geom_sf(data = stress_points, aes(color = avg_stress), size = 2, alpha = 0.8) +
  scale_color_gradient2(
    low = "#d73027",   # Red = Severe Stress (Browner than expected)
    mid = "#ffffbf",   # Yellow = Normal
    high = "#1a9850",  # Green = Healthy (Greener than expected)
    midpoint = 0,
    name = "Vegetation\nStress Index"
  ) +
  labs(
    title = "Vegetation Stress Map: Cholistan Desert",
    subtitle = "Red areas are browner than expected given the climate (Stress); Green areas are resilient",
    x = "Longitude",
    y = "Latitude"
  ) +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold", size = 14), legend.position = "bottom")

ggsave(here("outputs/figures/11_final_stress_map.png"), p_stress, width = 10, height = 8, dpi = 300)
cat("✅ Saved final stress map to: outputs/figures/11_final_stress_map.png\n")

cat("\n🎉 Step 11 Complete! Project analysis finished.\n")