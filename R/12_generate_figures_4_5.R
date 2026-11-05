# ============================================================================
# Script: 12_generate_figures_4_5.R
# Purpose: Generate Figure 4 (RF Permutation Importance) and Figure 5 (GAM Partial Effects)
# ============================================================================

# 1. Load required packages
required_packages <- c("tidyverse", "mgcv", "ranger", "yaml", "here", "gratia")
lapply(required_packages, function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) install.packages(pkg, dependencies = TRUE)
  library(pkg, character.only = TRUE, quietly = TRUE)
})

# 2. Load final models and data
config <- read_yaml(here("config.yaml"))
modelling_data <- read_csv(here("data/processed/modelling_data_clean.csv"), show_col_types = FALSE)
gam_model <- readRDS(here("data/processed/gam_final_2024.rds"))
rf_model <- readRDS(here("data/processed/rf_final_2024.rds"))

cat("🎨 Generating Figure 4: Random Forest Permutation Importance...\n")

# --- FIGURE 4: RF Variable Importance ---
# Extract unbiased permutation importance from the trained ranger model
rf_imp <- data.frame(
  Predictor = names(rf_model$variable.importance),
  Importance = rf_model$variable.importance
) %>%
  # Order by importance for a clean bar chart
  mutate(Predictor = factor(Predictor, levels = Predictor[order(Importance)])) %>%
  arrange(Importance)

# Create publication-ready plot
p4 <- ggplot(rf_imp, aes(x = Importance, y = Predictor)) +
  geom_col(fill = "#2c3e50") +
  labs(
    title = "Random Forest Variable Importance",
    subtitle = "Unbiased permutation importance (Mean Decrease in Accuracy)",
    x = "Permutation Importance",
    y = NULL
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(size = 11, color = "gray40"),
    axis.text.y = element_text(size = 11, face = "bold"),
    axis.title.x = element_text(size = 11)
  )

ggsave(here("outputs/figures/04_rf_variable_importance.png"), p4, width = 8, height = 5, dpi = 300)
cat("✅ Saved Figure 4 to: outputs/figures/04_rf_variable_importance.png\n")

# --- FIGURE 5: GAM Partial Effects ---
cat("\n🎨 Generating Figure 5: GAM Partial Effects...\n")
cat("(This may take a few seconds to render all smooths and confidence intervals)\n")

# gratia::draw() is the gold standard for mgcv plots. 
# pages = 1 forces all terms onto a single multi-panel figure.
p5 <- draw(gam_model, pages = 1)

ggsave(here("outputs/figures/05_gam_partial_effects.png"), p5, width = 10, height = 8, dpi = 300)
cat("✅ Saved Figure 5 to: outputs/figures/05_gam_partial_effects.png\n")

cat("\n🎉 Figures 4 and 5 generated successfully!\n")