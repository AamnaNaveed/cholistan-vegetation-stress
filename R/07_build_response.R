# ============================================================================
# Script: 07_build_response.R
# Purpose: Calculate ABSOLUTE seasonal NDVI anomaly (vegetation stress)
# FIX: Switch from Z-score to Absolute Difference (ndvi_mean - baseline_mean).
#      This prevents "tiny SD" noise in bare soil from destroying the signal
#      and removes the need for arbitrary clipping.
# ============================================================================

# 1. Install and load required packages
required_packages <- c("tidyverse", "lubridate", "yaml", "here")
install_if_missing <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg, dependencies = TRUE)
  }
}
lapply(required_packages, install_if_missing)
lapply(required_packages, library, character.only = TRUE, quietly = TRUE)

# 2. Load configuration and the FULL NDVI dataset
config <- read_yaml(here("config.yaml"))
ndvi_data <- read_csv(here("data/processed/ndvi_timeseries.csv"), show_col_types = FALSE)

cat("🌱 Building seasonal NDVI anomaly response variable...\n")

# 3. Clean and prepare the 16-day data
ndvi_clean <- ndvi_data %>%
  rename(date = calendar_date, ndvi_value = value) %>%
  mutate(
    date = as.Date(date),
    year = year(date),
    month = month(date),
    season = case_when(
      month %in% c(12, 1, 2) ~ "Winter",
      month %in% c(3, 4, 5) ~ "Spring",
      month %in% c(6, 7, 8) ~ "Summer",
      month %in% c(9, 10, 11) ~ "Autumn"
    ),
    season_year = if_else(month == 12, year + 1, year),
    ndvi_value = if_else(ndvi_value == -3000, NA, ndvi_value)
  ) %>%
  filter(!is.na(ndvi_value))

cat("✅ Cleaned data:", nrow(ndvi_clean), "valid 16-day composite observations.\n")

# 4. AGGREGATE TO PIXEL-SEASON-YEAR MEANS FIRST
ndvi_yearly_seasonal <- ndvi_clean %>%
  group_by(latitude, longitude, year, season, season_year) %>%
  summarise(
    ndvi_mean = mean(ndvi_value, na.rm = TRUE),
    n_composites = n(),
    .groups = "drop"
  ) %>%
  filter(!is.na(ndvi_mean))

cat("✅ Aggregated to", nrow(ndvi_yearly_seasonal), "unique pixel-season-year observations.\n")

# 5. Calculate baseline using ONLY training period (2018-2023)
cat("⚠️ Calculating baseline using ONLY 2018-2023...\n")
baseline_data <- ndvi_yearly_seasonal %>% filter(year < 2024)

seasonal_baseline <- baseline_data %>%
  group_by(latitude, longitude, season) %>%
  summarise(
    baseline_mean = mean(ndvi_mean, na.rm = TRUE),
    baseline_sd = sd(ndvi_mean, na.rm = TRUE), # Kept for reference, but not used for division
    n_obs = n(),
    .groups = "drop"
  )

cat("✅ Baseline calculated for", nrow(seasonal_baseline), "unique pixel-season combinations.\n")

# 6. Calculate ABSOLUTE ANOMALY (Difference from baseline)
ndvi_anomaly <- ndvi_yearly_seasonal %>%
  left_join(seasonal_baseline, by = c("latitude", "longitude", "season")) %>%
  mutate(
    # FIX: Use simple difference instead of Z-score. 
    # This preserves the true magnitude of vegetation green-up.
    ndvi_anomaly = ndvi_mean - baseline_mean,
    
    # Define stress class based on absolute difference
    # (e.g., if NDVI is 200 units below average, it's severe stress)
    stress_class = case_when(
      is.na(ndvi_anomaly) ~ "Unknown",
      ndvi_anomaly > quantile(ndvi_anomaly, 0.20, na.rm = TRUE) ~ "Normal",
      ndvi_anomaly <= quantile(ndvi_anomaly, 0.20, na.rm = TRUE) & 
        ndvi_anomaly > quantile(ndvi_anomaly, 0.05, na.rm = TRUE) ~ "Moderate Stress",
      ndvi_anomaly <= quantile(ndvi_anomaly, 0.05, na.rm = TRUE) ~ "Severe Stress"
    )
  ) %>%
  filter(!is.na(ndvi_anomaly))

cat("✅ Final clean anomaly dataset:", nrow(ndvi_anomaly), "observations.\n")
cat("   Range of anomalies:", round(min(ndvi_anomaly$ndvi_anomaly), 1), "to", round(max(ndvi_anomaly$ndvi_anomaly), 1), "\n")

# 7. Save the corrected response dataset
write_csv(ndvi_anomaly, here("data/processed/ndvi_anomaly_response.csv"))
cat("💾 Saved corrected anomaly response to: data/processed/ndvi_anomaly_response.csv\n")

# 8. Quick visual check
p <- ggplot(ndvi_anomaly, aes(x = ndvi_anomaly, fill = stress_class)) +
  geom_histogram(binwidth = 50, color = "white", alpha = 0.8, na.rm = TRUE) + # Binwidth 50 for absolute NDVI units
  scale_fill_manual(values = c("Normal" = "#4daf4a", "Moderate Stress" = "#ff7f00", "Severe Stress" = "#e41a1c", "Unknown" = "grey50")) +
  labs(
    title = "Distribution of Absolute NDVI Anomalies",
    subtitle = "Calculated as (Current Season NDVI - Historical Mean NDVI). No Z-score division."
  ) +
  theme_minimal()

ggsave(here("outputs/figures/02_ndvi_anomaly_distribution.png"), p, width = 8, height = 5, dpi = 300)
cat("📊 Saved anomaly distribution plot.\n")

cat("\n🎉 Step 7 Complete: Switched to Absolute Anomaly to preserve signal magnitude.\n")