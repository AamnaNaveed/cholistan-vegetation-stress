# ============================================================================
# Script: 06_spatial_blocks.R
# Purpose: Create 4 spatial blocks for cross-validation using K-Means clustering
# Reference: Project Plan Section 9.1 (Spatial block cross-validation)
# ============================================================================

# 1. Install and load required packages
required_packages <- c("tidyverse", "sf", "yaml", "here")

install_if_missing <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg, dependencies = TRUE)
  }
}
lapply(required_packages, install_if_missing)
lapply(required_packages, library, character.only = TRUE)

# 2. Load configuration and the modelling table
config <- read_yaml(here("config.yaml"))
mod_table <- read_csv(here("data/processed/modelling_table.csv"), show_col_types = FALSE)

cat("🗺️ Creating 4 spatial blocks for cross-validation (Step 6)...\n")

# 3. Extract coordinates for clustering
coords <- mod_table %>% select(longitude, latitude)

# 4. Create spatial blocks using K-Means clustering
# This groups nearby points into 4 distinct spatial clusters
cat("Calculating spatial clusters...\n")
set.seed(42) # Fixed random seed for reproducibility

kmeans_result <- kmeans(coords, centers = 4, nstart = 25)

# 5. Add the block assignments to our modelling table
mod_table <- mod_table %>%
  mutate(spatial_block = as.factor(kmeans_result$cluster))

cat("✅ Spatial blocks created successfully.\n")
cat("Distribution of points across 4 blocks:\n")
print(table(mod_table$spatial_block))

# 6. Visualize the Spatial Blocks
p_blocks <- ggplot(mod_table, aes(x = longitude, y = latitude, color = spatial_block)) +
  geom_point(size = 1.5, alpha = 0.8) +
  scale_color_brewer(palette = "Set1", name = "Spatial Block") +
  labs(
    title = "Spatial Blocks for Cross-Validation",
    subtitle = "4 distinct spatial clusters created via K-Means to prevent spatial autocorrelation leakage",
    x = "Longitude",
    y = "Latitude"
  ) +
  theme_minimal() +
  theme(legend.position = "bottom")

ggsave(here("outputs/figures/06_spatial_blocks.png"), p_blocks, width = 8, height = 6, dpi = 300)
cat("📊 Saved spatial blocks map to: outputs/figures/06_spatial_blocks.png\n")

# 7. Save the updated table with block assignments
write_csv(mod_table, here("data/processed/modelling_table_with_blocks.csv"))
cat("💾 Saved updated table to: data/processed/modelling_table_with_blocks.csv\n")

cat("\n🎉 Step 6 Complete! Spatial blocks created and saved.\n")