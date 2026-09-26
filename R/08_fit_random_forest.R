# ============================================================================
# Script: 08_fit_random_forest.R
# Purpose: Fit a Random Forest model to predict NDVI anomaly and assess variable importance.
# Reference: Project Plan Section 8.3
# ============================================================================

# 1. Install and load required packages
required_packages <- c("tidyverse", "ranger", "yaml", "here")

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

cat("🌲 Fitting Random Forest Model (Step 8)...\n")

# 3. Prepare data for ranger
# ranger requires a clean dataframe without NAs for the predictors/response
rf_data <- mod_table %>%
  select(ndvi_anomaly, elevation, annual_precip_mm, precip_seasonality) %>%
  na.omit()

cat("Training Random Forest on", nrow(rf_data), "observations...\n")
set.seed(42) # Fixed random seed for reproducibility

# 4. Fit the Random Forest model
# We use regression (probability = FALSE)
# num.trees = 500 is a standard, stable choice
# importance = "impurity" allows us to plot variable importance later
rf_model <- ranger(
  ndvi_anomaly ~ .,
  data = rf_data,
  num.trees = 500,
  importance = "impurity",
  write.forest = TRUE
)

# 5. Print model summary
cat("\n--- Random Forest Model Summary ---\n")
print(rf_model)

# 6. Extract and plot Variable Importance
cat("\n📊 Generating Variable Importance plot...\n")
importance_df <- data.frame(
  Variable = names(rf_model$variable.importance),
  Importance = rf_model$variable.importance
) %>%
  arrange(desc(Importance))

p_imp <- ggplot(importance_df, aes(x = reorder(Variable, Importance), y = Importance, fill = Variable)) +
  geom_bar(stat = "identity", show.legend = FALSE) +
  coord_flip() +
  labs(
    title = "Random Forest Variable Importance",
    subtitle = "Predictive contribution of each environmental variable",
    x = "Predictor",
    y = "Importance (Impurity decrease)"
  ) +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold"))

ggsave(here("outputs/figures/08_rf_variable_importance.png"), p_imp, width = 8, height = 5, dpi = 300)
cat("✅ Saved Variable Importance plot to: outputs/figures/08_rf_variable_importance.png\n")

# 7. Save the model object
saveRDS(rf_model, here("data/processed/rf_model.rds"))
cat("💾 Saved Random Forest model object to: data/processed/rf_model.rds\n")

cat("\n🎉 Step 8 Complete! Random Forest fitted and importance plotted.\n")