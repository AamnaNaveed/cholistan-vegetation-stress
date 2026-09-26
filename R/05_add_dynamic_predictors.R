# ============================================================================
# Script: 03_add_dynamic_predictors.R
# Purpose: Add time-varying climate predictors using NASA POWER API
# Reference: PDF Step 3 - Add dynamic predictors (seasonal precip, lagged precip, temp)
# ============================================================================

# 1. Install and load required packages
required_packages <- c("tidyverse", "jsonlite", "yaml", "here")

install_if_missing <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg, dependencies = TRUE)
  }
}
lapply(required_packages, install_if_missing)
lapply(required_packages, library, character.only = TRUE)

# 2. Load configuration and data
config <- read_yaml(here("config.yaml"))
mod_table <- read_csv(here("data/processed/modelling_table_with_blocks.csv"), show_col_types = FALSE)

cat("️ Adding dynamic climate predictors via NASA POWER API (Step 3)...\n")

# 3. Get unique coordinates to minimize API calls
unique_points <- mod_table %>%
  distinct(latitude, longitude) %>%
  mutate(point_id = row_number())

cat("Querying NASA POWER for", nrow(unique_points), "unique locations...\n")
cat("(This will take 2-4 minutes)\n")

# 4. Query NASA POWER API for monthly data (2018-2024)
# T2M = Temperature at 2m (Celsius), PRECTOT = Precipitation (mm/day)
climate_data <- list()

for (i in 1:nrow(unique_points)) {
  lat <- unique_points$latitude[i]
  lon <- unique_points$longitude[i]
  
  # NASA POWER API URL for monthly point data
  url <- sprintf(
    "https://power.larc.nasa.gov/api/temporal/monthly/point?parameters=T2M,PRECTOT&community=RE&longitude=%.4f&latitude=%.4f&start=2018&end=2024&format=JSON",
    lon, lat
  )
  
  # Fetch and parse JSON
  response <- tryCatch({
    fromJSON(url, simplifyVector = TRUE)
  }, error = function(e) {
    cat("  Warning: Failed for point", i, "\n")
    return(NULL)
  })
  
  if (!is.null(response)) {
    # Extract the monthly parameters
    params <- response$properties$parameter
    
    # Convert to a tidy dataframe
    monthly_df <- data.frame(
      latitude = lat,
      longitude = lon,
      year = as.integer(substr(names(params$T2M), 1, 4)),
      month = as.integer(substr(names(params$T2M), 6, 7)),
      monthly_temp_c = as.numeric(params$T2M),
      monthly_precip_mm_day = as.numeric(params$PRECTOT)
    )
    climate_data[[i]] <- monthly_df
  }
  
  # Be polite to the API
  Sys.sleep(0.2)
}

climate_long <- bind_rows(climate_data)
cat("✅ API data downloaded and parsed.\n")

# 5. Aggregate to Seasonal Variables
# Define seasons and calculate seasonal sums/means
climate_seasonal <- climate_long %>%
  mutate(
    season = case_when(
      month %in% c(12, 1, 2) ~ "Winter",
      month %in% c(3, 4, 5) ~ "Spring",
      month %in% c(6, 7, 8) ~ "Summer",
      month %in% c(9, 10, 11) ~ "Autumn"
    ),
    # Handle season_year for Winter (Dec belongs to next year's winter group)
    season_year = if_else(month == 12, year + 1, year)
  ) %>%
  group_by(latitude, longitude, season, season_year) %>%
  summarise(
    seasonal_precip = sum(monthly_precip_mm_day, na.rm = TRUE), # Total precip for season
    seasonal_temp = mean(monthly_temp_c, na.rm = TRUE),          # Avg temp for season
    .groups = "drop"
  )

# 6. Create Lagged Variables (Previous Season's Precipitation)
# This is crucial for dryland ecology (soil moisture memory)
climate_lagged <- climate_seasonal %>%
  arrange(latitude, longitude, season_year) %>%
  group_by(latitude, longitude) %>%
  mutate(
    lagged_seasonal_precip = lag(seasonal_precip, 1)
  ) %>%
  ungroup()

cat("✅ Seasonal and lagged variables calculated.\n")

# 7. Join dynamic climate data back to the main modelling table
# We join on lat, lon, and the specific year/season of the observation
mod_table_dynamic <- mod_table %>%
  mutate(
    # Recreate season_year to match the climate data
    season_year = if_else(month == 12, year + 1, year)
  ) %>%
  left_join(climate_lagged, by = c("latitude", "longitude", "season", "season_year"))

# 8. Clean up and save
mod_table_dynamic <- mod_table_dynamic %>%
  select(-month, -season_year) # Remove helper columns

write_csv(mod_table_dynamic, here("data/processed/modelling_table_dynamic.csv"))
cat(" Saved dynamic modelling table to: data/processed/modelling_table_dynamic.csv\n")

# 9. Quick visual check
cat("\n--- Summary of Dynamic Predictors ---\n")
print(summary(mod_table_dynamic %>% select(seasonal_precip, seasonal_temp, lagged_seasonal_precip)))

cat("\n Step 3 Complete! Dynamic climate predictors added.\n")