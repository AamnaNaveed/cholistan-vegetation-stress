# ============================================================================
# Script: 05_build_response.R
# Purpose: Calculate standardized seasonal NDVI anomaly (vegetation stress)
# CORRECTION (PDF Section 4.1): Fix seasonal baseline, exclude 2024 from baseline,
# handle season-year, and flag zero-variance. No clipping in primary response.
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

cat("🌱 Building seasonal NDVI anomaly response variable (PDF Step 1)...\n")

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
    # PDF 4.1: Create season_year to handle Winter crossing calendar years 
    # (e.g., Dec 2018 belongs to the 2019 winter season group)
    season_year = if_else(month == 12, year + 1, year),
    # Replace MODIS fill values with NA
    ndvi_value = if_else(ndvi_value == -3000, NA, ndvi_value)
  ) %>%
  filter(!is.na(ndvi_value))

cat("✅ Cleaned data:", nrow(ndvi_clean), "valid observations.\n")

# 4. PDF 4.1: Calculate seasonal baseline using ONLY the training period (2018-2023)
cat("⚠️ Calculating baseline using ONLY 2018-2023 to prevent temporal data leakage...\n")
baseline_data <- ndvi_clean %>% filter(year < 2024)

seasonal_baseline <- baseline_data %>%
  # PDF 4.1: Group by latitude, longitude, AND season
  group_by(latitude, longitude, season) %>%
  summarise(
    ndvi_mean = mean(ndvi_value, na.rm = TRUE),
    ndvi_sd = sd(ndvi_value, na.rm = TRUE),
    n_obs = n(),
    .groups = "drop"
  ) %>%
  # PDF 4.1: Flag zero standard deviations and insufficient observations
  mutate(
    ndvi_sd = if_else(is.na(ndvi_sd) | ndvi_sd == 0 | n_obs < 5, NA_real_, ndvi_sd)
  )

cat("✅ Baseline calculated for", nrow(seasonal_baseline), "unique pixel-season combinations.\n")

# 5. PDF 4.1: Join 2024 to the training-derived baseline without altering it
ndvi_anomaly <- ndvi_clean %>%
  left_join(seasonal_baseline, by = c("latitude", "longitude", "season")) %>%
  mutate(
    # Calculate true Z-score (will be NA if sd was flagged)
    ndvi_anomaly = (ndvi_value - ndvi_mean) / ndvi_sd,
    
    # Define stress class (PDF 4.6: No clipping in primary analysis)
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
    subtitle = "Baseline calculated strictly on 2018-2023 training data (No clipping)"
  ) +
  theme_minimal()

ggsave(here("outputs/figures/02_ndvi_anomaly_distribution.png"), p, width = 8, height = 5, dpi = 300)
cat("📊 Saved anomaly distribution plot.\n")

cat("\n🎉 Step 1 Complete (PDF Section 4.1): Seasonal baseline corrected and data leakage prevented.\n")