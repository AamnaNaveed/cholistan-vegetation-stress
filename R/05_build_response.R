# ============================================================================
# Script: 05_build_response.R
# Purpose: Calculate standardized seasonal NDVI anomaly (vegetation stress)
# ============================================================================

# 1. Install and load required packages
required_packages <- c("tidyverse", "lubridate", "yaml", "here")

install_if_missing <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg, dependencies = TRUE)
  }
}
lapply(required_packages, install_if_missing)
lapply(required_packages, library, character.only = TRUE)

# 2. Load configuration and the FULL NDVI dataset
config <- read_yaml(here("config.yaml"))
ndvi_data <- read_csv(here("data/processed/ndvi_timeseries.csv"), show_col_types = FALSE)

cat("🌱 Building seasonal NDVI anomaly response variable...\n")
cat("Starting with", nrow(ndvi_data), "raw observations.\n")

# 3. Clean and prepare the data
ndvi_clean <- ndvi_data %>%
  rename(
    date = calendar_date, 
    ndvi_value = value    
  ) %>%
  mutate(
    date = as.Date(date),
    year = year(date),
    month = month(date),
    # Define seasons for the Northern Hemisphere (Pakistan)
    season = case_when(
      month %in% c(12, 1, 2) ~ "Winter",
      month %in% c(3, 4, 5) ~ "Spring",
      month %in% c(6, 7, 8) ~ "Summer",
      month %in% c(9, 10, 11) ~ "Autumn"
    ),
    # Replace MODIS fill values (-3000) with NA
    ndvi_value = ifelse(ndvi_value == -3000, NA, ndvi_value)
  ) %>%
  filter(!is.na(ndvi_value)) # Remove missing data

cat("✅ Cleaned data:", nrow(ndvi_clean), "valid observations remaining.\n")

# 4. Calculate seasonal baseline (mean and standard deviation) per point
# We group by latitude and longitude, which is 100% reliable for spatial grids
seasonal_baseline <- ndvi_clean %>%
  group_by(latitude, longitude) %>%
  summarise(
    ndvi_mean = mean(ndvi_value, na.rm = TRUE),
    ndvi_sd = sd(ndvi_value, na.rm = TRUE),
    .groups = "drop"
  )

# 5. Join baseline back to the main data and calculate the Z-score anomaly
ndvi_anomaly <- ndvi_clean %>%
  left_join(seasonal_baseline, by = c("latitude", "longitude")) %>%
  mutate(
    # Standardized anomaly: (Value - Mean) / Standard Deviation
    ndvi_anomaly = (ndvi_value - ndvi_mean) / ndvi_sd,
    
    # Define stress class based on quantiles
    stress_class = case_when(
      ndvi_anomaly > quantile(ndvi_anomaly, 0.20, na.rm = TRUE) ~ "Normal",
      ndvi_anomaly <= quantile(ndvi_anomaly, 0.20, na.rm = TRUE) & 
        ndvi_anomaly > quantile(ndvi_anomaly, 0.05, na.rm = TRUE) ~ "Moderate Stress",
      ndvi_anomaly <= quantile(ndvi_anomaly, 0.05, na.rm = TRUE) ~ "Severe Stress",
      TRUE ~ "Unknown"
    )
  )

# 6. Save the processed response dataset
write_csv(ndvi_anomaly, here("data/processed/ndvi_anomaly_response.csv"))
cat("💾 Saved anomaly response to: data/processed/ndvi_anomaly_response.csv\n")

# 7. Quick visual check: Plot the anomaly distribution
p <- ggplot(ndvi_anomaly, aes(x = ndvi_anomaly, fill = stress_class)) +
  geom_histogram(binwidth = 0.5, color = "white", alpha = 0.8) +
  scale_fill_manual(values = c("Normal" = "#4daf4a", "Moderate Stress" = "#ff7f00", "Severe Stress" = "#e41a1c")) +
  labs(
    title = "Distribution of Seasonal NDVI Anomalies",
    subtitle = "Negative values indicate below-normal vegetation condition (stress)",
    x = "Standardized NDVI Anomaly (Z-score)",
    y = "Count"
  ) +
  theme_minimal() +
  theme(legend.position = "bottom")

ggsave(here("outputs/figures/02_ndvi_anomaly_distribution.png"), p, width = 8, height = 5, dpi = 300)
cat("📊 Saved anomaly distribution plot to: outputs/figures/02_ndvi_anomaly_distribution.png\n")

cat("\n🎉 Step 5 Complete! Response variable built and saved.\n")