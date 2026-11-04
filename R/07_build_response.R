# ============================================================================
# Script: 07_build_response.R
# Purpose: Calculate standardized seasonal NDVI anomaly (vegetation stress)
# REVISION: Aggregate 16-day composites to a single seasonal mean per pixel 
#           to eliminate pseudo-replication (Reviewer 2, Major Comment 5).
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
cat("⚠️ AGGREGATING 16-day composites to pixel-season means to prevent pseudo-replication.\n")

# 3. Clean and prepare the data
ndvi_clean <- ndvi_data %>%
  rename(date = calendar_date, ndvi_value = value) %>%
  mutate(
    date = as.Date(date),
    year = year(date),
    month = month(date),
    # Define season
    season = case_when(
      month %in% c(12, 1, 2) ~ "Winter",
      month %in% c(3, 4, 5) ~ "Spring",
      month %in% c(6, 7, 8) ~ "Summer",
      month %in% c(9, 10, 11) ~ "Autumn"
    ),
    # Create season_year to handle Winter crossing calendar years
    season_year = if_else(month == 12, year + 1, year),
    # Replace MODIS fill values with NA
    ndvi_value = if_else(ndvi_value == -3000, NA, ndvi_value)
  ) %>%
  filter(!is.na(ndvi_value))

cat("✅ Cleaned data:", nrow(ndvi_clean), "valid 16-day composite observations.\n")

# --- REVIEWER 2 FIX: AGGREGATE TO PIXEL-SEASON ---
cat("🔄 Aggregating to one mean NDVI per pixel per season...\n")
ndvi_seasonal <- ndvi_clean %>%
  group_by(latitude, longitude, season, season_year, year) %>%
  summarise(
    ndvi_mean = mean(ndvi_value, na.rm = TRUE),
    n_composites = n(),
    .groups = "drop"
  ) %>%
  filter(!is.na(ndvi_mean))

cat("✅ Aggregated to", nrow(ndvi_seasonal), "unique pixel-season observations.\n")

# 4. Calculate seasonal baseline using ONLY the training period (2018-2023)
cat("⚠️ Calculating baseline using ONLY 2018-2023 to prevent temporal data leakage...\n")
# Note: We filter by season_year < 2024 to ensure Dec 2023 (which belongs to Winter 2024) is excluded from the baseline
baseline_data <- ndvi_seasonal %>% filter(season_year < 2024)

seasonal_baseline <- baseline_data %>%
  group_by(latitude, longitude, season) %>%
  summarise(
    baseline_mean = mean(ndvi_mean, na.rm = TRUE),
    baseline_sd = sd(ndvi_mean, na.rm = TRUE),
    n_obs = n(),
    .groups = "drop"
  ) %>%
  # Flag zero standard deviations and insufficient observations
  mutate(
    baseline_sd = if_else(is.na(baseline_sd) | baseline_sd == 0 | n_obs < 3, NA_real_, baseline_sd)
  )

cat("✅ Baseline calculated for", nrow(seasonal_baseline), "unique pixel-season combinations.\n")

# 5. Join all years to the training-derived baseline without altering it
ndvi_anomaly <- ndvi_seasonal %>%
  left_join(seasonal_baseline, by = c("latitude", "longitude", "season")) %>%
  mutate(
    # Calculate true Z-score
    ndvi_anomaly = (ndvi_mean - baseline_mean) / baseline_sd,
    # Define stress class
    stress_class = case_when(
      is.na(ndvi_anomaly) ~ "Unknown",
      ndvi_anomaly > quantile(ndvi_anomaly, 0.20, na.rm = TRUE) ~ "Normal",
      ndvi_anomaly <= quantile(ndvi_anomaly, 0.20, na.rm = TRUE) & 
        ndvi_anomaly > quantile(ndvi_anomaly, 0.05, na.rm = TRUE) ~ "Moderate Stress",
      ndvi_anomaly <= quantile(ndvi_anomaly, 0.05, na.rm = TRUE) ~ "Severe Stress"
    )
  )

# 6. Save the corrected response dataset
write_csv(ndvi_anomaly, here("data/processed/ndvi_anomaly_response.csv"))
cat("💾 Saved corrected anomaly response to: data/processed/ndvi_anomaly_response.csv\n")

# 7. Quick visual check
p <- ggplot(ndvi_anomaly, aes(x = ndvi_anomaly, fill = stress_class)) +
  geom_histogram(binwidth = 0.5, color = "white", alpha = 0.8, na.rm = TRUE) +
  scale_fill_manual(values = c("Normal" = "#4daf4a", "Moderate Stress" = "#ff7f00", "Severe Stress" = "#e41a1c", "Unknown" = "grey50")) +
  labs(
    title = "Distribution of Seasonal NDVI Anomalies",
    subtitle = "Aggregated to pixel-season means. Baseline strictly on 2018-2023."
  ) +
  theme_minimal()

ggsave(here("outputs/figures/02_ndvi_anomaly_distribution.png"), p, width = 8, height = 5, dpi = 300)
cat("📊 Saved anomaly distribution plot.\n")

cat("\n🎉 Step 7 Complete: Pseudo-replication eliminated. Data aggregated to pixel-season level.\n")