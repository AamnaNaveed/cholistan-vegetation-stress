# ============================================================================
# Script: 11_uncertainty_and_novelty.R
# Purpose: Model disagreement, Area of Applicability (DI), and error check.
# REVISION: Fixed list-column write_csv error and added safeguard against 
#           division-by-zero in DI calculation.
# ============================================================================

# 1. Load required packages
required_packages <- c("tidyverse", "mgcv", "ranger", "yaml", "here", "FNN")
lapply(required_packages, function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) install.packages(pkg, dependencies = TRUE)
  library(pkg, character.only = TRUE, quietly = TRUE)
})

# 2. Load data and models
config <- read_yaml(here("config.yaml"))
modelling_data <- read_csv(here("data/processed/modelling_data_clean.csv"), show_col_types = FALSE)
gam_model <- readRDS(here("data/processed/gam_final_2024.rds"))
rf_model  <- readRDS(here("data/processed/rf_final_2024.rds"))

cat("🔍 Calculating Uncertainty and Area of Applicability (Step 11)...\n")

predictors <- c("elevation", "slope_degrees", "seasonal_precip", 
                "lagged_seasonal_precip", "seasonal_temp", "land_cover_class")

# Continuous predictors only for the multivariate dissimilarity index
vars_num <- c("elevation", "slope_degrees", "seasonal_precip", 
              "lagged_seasonal_precip", "seasonal_temp")

train_data <- modelling_data %>% filter(year < 2024) %>%
  mutate(land_cover_class = as.factor(land_cover_class))
test_2024  <- modelling_data %>% filter(year == 2024) %>%
  mutate(land_cover_class = as.factor(land_cover_class))

# --- PART 1: Model Disagreement and Actual Error ---
cat("\n📊 Calculating model disagreement and actual prediction error (2024)...\n")

# FIX: Force predictions to be plain numeric vectors to prevent list-column errors
pred_gam_raw <- predict(gam_model, newdata = test_2024)
pred_rf_raw  <- predict(rf_model, data = test_2024 %>% select(all_of(predictors)))$predictions

uncertainty_2024 <- test_2024 %>%
  mutate(
    pred_gam = as.numeric(unname(pred_gam_raw)),
    pred_rf = as.numeric(unname(pred_rf_raw)),
    disagreement = abs(pred_gam - pred_rf),
    abs_error_rf = abs(ndvi_anomaly - pred_rf)
  )

cat("✅ Mean model disagreement:", round(mean(uncertainty_2024$disagreement, na.rm = TRUE), 3), "\n")

# --- PART 2: Manual Area of Applicability (Dissimilarity Index) ---
cat("\n🌍 Calculating Area of Applicability (Multivariate Dissimilarity Index)...\n")

# 1. Scale training data
train_num <- train_data[, vars_num]
train_scaled <- scale(train_num)

# 2. Scale test data using training parameters
test_num <- test_2024[, vars_num]
test_scaled <- scale(test_num, center = attr(train_scaled, "scaled:center"), 
                     scale = attr(train_scaled, "scaled:scale"))

# 3. Distance from each test point to its 1st nearest neighbor in the training set
test_nn <- FNN::get.knnx(data = train_scaled, query = test_scaled, k = 1)
test_dist <- as.numeric(test_nn$nn.dist)

# 4. Distance to the 2nd nearest neighbor within the training data itself 
train_nn <- FNN::get.knnx(data = train_scaled, query = train_scaled, k = 2)
train_dist <- as.numeric(train_nn$nn.dist[, 2])

# 5. The Area of Applicability threshold is the maximum distance to the 2nd nearest neighbor in training
aoa_threshold <- max(train_dist, na.rm = TRUE)

# FIX: Safeguard against division by zero
if (is.na(aoa_threshold) || aoa_threshold == 0) {
  aoa_threshold <- 1e-6
  cat("  ⚠️ Warning: Training distance threshold was 0 or NA. Applied safeguard (1e-6).\n")
}

# 6. Calculate Dissimilarity Index (DI)
DI <- test_dist / aoa_threshold
is_extrapolation <- DI > 1

final_uncertainty <- uncertainty_2024 %>%
  mutate(
    DI = as.numeric(DI),
    is_extrapolation = as.logical(is_extrapolation)
  )

aoa_summary <- final_uncertainty %>%
  summarise(
    total_2024_obs = n(),
    outside_AOA_obs = sum(is_extrapolation, na.rm = TRUE),
    pct_outside_AOA = round(100 * outside_AOA_obs / total_2024_obs, 1),
    mean_DI = round(mean(DI, na.rm = TRUE), 3),
    max_DI = round(max(DI, na.rm = TRUE), 3)
  )

cat("✅ Area of Applicability check complete.\n")
cat("Total 2024 observations:", aoa_summary$total_2024_obs, "\n")
cat("Observations OUTSIDE the AoA:", aoa_summary$outside_AOA_obs, 
    "(", aoa_summary$pct_outside_AOA, "%)\n")
cat("Mean Dissimilarity Index (DI):", aoa_summary$mean_DI, "\n")

write_csv(aoa_summary, here("data/processed/aoa_summary_2024.csv"))

# FIX: Explicitly select and cast to ensure no list columns
export_df <- final_uncertainty %>%
  select(latitude, longitude, year, season, ndvi_anomaly,
         pred_gam, pred_rf, disagreement, abs_error_rf, DI, is_extrapolation) %>%
  mutate(across(everything(), as.numeric)) %>%
  mutate(is_extrapolation = as.logical(is_extrapolation),
         year = as.integer(year),
         season = as.character(season))

write_csv(export_df, here("data/processed/uncertainty_aoa_2024.csv"))
cat("💾 Saved AoA outputs to data/processed/\n")

# --- PART 3: Is disagreement actually related to error? (Reviewer 2) ---
cat("\n🔗 Testing whether disagreement is informative about actual error...\n")
cor_disagree_error <- cor(final_uncertainty$disagreement,
                          final_uncertainty$abs_error_rf,
                          use = "complete.obs", method = "spearman")
cor_DI_error <- cor(final_uncertainty$DI,
                    final_uncertainty$abs_error_rf,
                    use = "complete.obs", method = "spearman")

cat("Spearman correlation (disagreement vs |RF error|):", round(cor_disagree_error, 3), "\n")
cat("Spearman correlation (DI vs |RF error|):", round(cor_DI_error, 3), "\n")

error_check <- data.frame(
  Relationship = c("Disagreement_vs_AbsError", "DI_vs_AbsError"),
  Spearman_rho = c(cor_disagree_error, cor_DI_error)
)
write_csv(error_check, here("outputs/tables/uncertainty_error_relationship.csv"))

# Mean error inside vs outside AoA
error_by_aoa <- final_uncertainty %>%
  group_by(is_extrapolation) %>%
  summarise(n = n(),
            mean_abs_error = mean(abs_error_rf, na.rm = TRUE),
            mean_disagreement = mean(disagreement, na.rm = TRUE),
            .groups = "drop")
cat("\n--- Error inside vs outside the Area of Applicability ---\n")
print(error_by_aoa)
write_csv(error_by_aoa, here("outputs/tables/error_by_aoa.csv"))

# --- PART 4: Plots ---
cat("\n🎨 Generating uncertainty plots...\n")

p_disagree <- ggplot(final_uncertainty, aes(x = pred_rf, y = disagreement)) +
  geom_point(alpha = 0.4, color = "#e74c3c") +
  geom_smooth(method = "loess", color = "black", se = TRUE) +
  labs(
    title = "Model disagreement between GAM and random forest",
    subtitle = "Absolute difference between model predictions on the 2024 hold-out",
    x = "Random forest predicted NDVI anomaly (Z-score)",
    y = "Absolute disagreement (|GAM - RF|)"
  ) +
  theme_minimal() + theme(plot.title = element_text(face = "bold"))
ggsave(here("outputs/figures/15_model_disagreement.png"), p_disagree, width = 8, height = 6, dpi = 300)

# Descriptive labels + n per group (Reviewer 2 minor comment 6)
plot_df <- final_uncertainty %>%
  filter(!is.na(is_extrapolation)) %>%
  mutate(AoA_status = if_else(is_extrapolation,
                              "Outside area of applicability",
                              "Within area of applicability"))
n_labels <- plot_df %>% count(AoA_status) %>%
  mutate(label = paste0(AoA_status, "\n(n = ", n, ")"))
plot_df <- plot_df %>%
  left_join(n_labels %>% select(AoA_status, label), by = "AoA_status")

p_novelty <- ggplot(plot_df, aes(x = label, y = disagreement, fill = AoA_status)) +
  geom_boxplot(alpha = 0.7, outlier.alpha = 0.3) +
  scale_fill_manual(values = c("Within area of applicability" = "#4daf4a",
                               "Outside area of applicability" = "#e41a1c")) +
  labs(
    title = "Model disagreement and area of applicability",
    subtitle = "Area of applicability derived from the multivariate dissimilarity index",
    x = NULL, y = "Absolute disagreement (|GAM - RF|)"
  ) +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold"), legend.position = "none")
ggsave(here("outputs/figures/16_novelty_vs_uncertainty.png"), p_novelty, width = 7, height = 6, dpi = 300)

cat("📊 Saved figures 15 and 16.\n")
cat("\n🎉 Step 11 Complete! Area of Applicability and error relationship calculated.\n")
