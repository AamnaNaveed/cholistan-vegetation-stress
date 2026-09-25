# ============================================================================
# Script: 01_setup.R
# Purpose: Install required packages and test project configuration
# ============================================================================

# 1. Install packages if they are not already installed
if (!requireNamespace("yaml", quietly = TRUE)) {
  install.packages("yaml")
}
if (!requireNamespace("here", quietly = TRUE)) {
  install.packages("here")
}

# 2. Load the packages
library(yaml)
library(here)

# 3. Read the config.yaml file from the project root
config <- read_yaml(here("config.yaml"))

# 4. Print a test message to prove it worked
cat("✅ Project setup successful!\n")
cat("Study area districts:", paste(config$study_area$districts, collapse = ", "), "\n")
cat("Project root folder:", here(), "\n")