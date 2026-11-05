# Cholistan Vegetation Stress Modelling

This repository contains the complete, reproducible R pipeline for the manuscript: 
**"Modelling seasonal NDVI anomalies in the Cholistan region of Pakistan using random forests and generalized additive models with spatial and temporal validation"** by Aamna Naveed.

This manuscript is archived as a preprint with a permanent DOI: [Insert your ResearchSquare DOI link here].

## Pipeline Overview
This workflow models seasonal NDVI anomalies using MODIS NDVI, NASA POWER climate data, and SRTM terrain data. It strictly prevents temporal data leakage and pseudo-replication by aggregating 16-day composites to seasonal means and calculating anomaly baselines exclusively on the 2018–2023 training period.

## Script Descriptions
The analysis is divided into sequential R scripts. Run them in order:

*   `01_generate_study_area_map_v2.R`: Generates the publication-quality study area map (Figure 1).
*   `02_data_preprocessing.R`: Downloads MODIS and NASA POWER data, aggregates 16-day composites to seasonal means, filters out irrigated cropland, and calculates the leakage-free Z-score anomalies.
*   `03_09_modelling_and_analysis.R`: [Update these names to match your actual scripts] Sets up the spatial blocks, fits the GAM and Random Forest models, and calculates variable importance.
*   `10_validation_corrected.R`: Performs the rigorous 4-fold spatial cross-validation and the strict 2024 temporal hold-out, including the Seasonal Climatology benchmarks. Evaluates skill on Raw NDVI.
*   `11_uncertainty_novelty.R`: Calculates the multivariate Dissimilarity Index (Area of Applicability) and model disagreement.
*   `12_generate_figures_4_5.R`: Generates the final publication-quality figures for variable importance and GAM partial effects.

## Data Availability
All data used are freely available:
*   MODIS NDVI (MOD13Q1 v6.1) and Land Cover (MCD12Q1 v6.1): NASA LP DAAC
*   Climate Data: NASA POWER API
*   Terrain Data: SRTM via USGS

## License
This code is released under the MIT License.