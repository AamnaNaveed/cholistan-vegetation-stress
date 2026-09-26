# ============================================================================
# Script: 07_fit_gam.R
# Purpose: Fit a Generalized Additive Model (GAM) to estimate smooth, 
#          interpretable relationships between vegetation stress and predictors.
# Reference: Project Plan Section 8.2
# ============================================================================

# 1. Install and load required packages
required_packages <- c("tidyverse", "mgcv", "yaml", "here")

install_if_missing <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg, dependencies = TRUE)
  }
}
lapply(required_packages, install_if_missing)
lapply(required_packages, library, character.only = TRUE)

# 2. Load configuration and the modelling table with blocks
config <- read_yaml(here("config.yaml"))
mod_table <- read_csv(here("data/processed/modelling_table_with_blocks.csv"), show_col_types = FALSE)

cat(" Fitting Generalized Additive Model (GAM) (Step 7)...\n")

# 3. Fit the GAM
# We use smooth terms s() for continuous predictors to capture non-linear relationships
# method = "REML" is the recommended, stable estimation method for GAMs
cat("Training GAM on the full dataset to inspect partial effects...\n")
set.seed(42)

gam_model <- mgcv::gam(
  ndvi_anomaly ~ s(elevation) + 
    s(annual_precip_mm) + 
    s(precip_seasonality),
  data = mod_table,
  method = "REML"
)

# 4. Print model summary
cat("\n--- GAM Model Summary ---\n")
print(summary(gam_model))

# 5. Plot the smooth partial effects (The most important part for interpretation!)
cat("\n📊 Generating partial effect plots...\n")
png(here("outputs/figures/07_gam_partial_effects.png"), width = 1200, height = 800, res = 150)
par(mfrow = c(1, 3), mar = c(5, 5, 2, 1))
plot(gam_model, shade = TRUE, seWithMean = TRUE, main = "")
# Add custom titles
mtext("Effect of Elevation", side = 3, line = -1, cex = 1.2)
mtext("Effect of Annual Precipitation", side = 3, line = -1, cex = 1.2)
mtext("Effect of Precipitation Seasonality", side = 3, line = -1, cex = 1.2)
dev.off()
cat("✅ Saved GAM partial effects plot to: outputs/figures/07_gam_partial_effects.png\n")

# 6. Save the model object so we can use it later for validation
saveRDS(gam_model, here("data/processed/gam_model.rds"))
cat("💾 Saved GAM model object to: data/processed/gam_model.rds\n")

cat("\n Step 7 Complete! GAM fitted and partial effects plotted.\n")