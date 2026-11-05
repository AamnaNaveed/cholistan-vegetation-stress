# Data Sources and Processing Notes

This document details the provenance, processing steps, and limitations of all datasets used in the Cholistan Vegetation Stress Analysis. It is designed to perfectly mirror Section 2.2 of the revised manuscript.

## 1. Vegetation Response: MODIS MOD13Q1 (Version 6.1)
* **Source:** NASA LP DAAC (Land Processes Distributed Active Archive Center).
* **Product:** MOD13Q1 (16-day, 250m resolution NDVI).
* **Processing:** 
  * Fill values (`-3000`) were converted to `NA`.
  * **Pseudo-replication prevention:** Rather than treating every 16-day composite as an independent observation, valid composites within each pixel and meteorological season were aggregated into a **single seasonal mean value** prior to any anomaly calculation or modelling.
  * **Land cover filtering:** To focus strictly on the natural arid ecosystem, irrigated cropland pixels were excluded from the analysis.

## 2. Dynamic Climate Predictors: NASA POWER API
* **Source:** NASA Prediction of Worldwide Energy Resources (POWER) Project.
* **Access Method:** Queried programmatically via the `httr` / `MODISTools` R packages for each unique coordinate. Rate limits were handled using `Sys.sleep(1)` between requests.
* **Parameters & Units:**
  * `T2M`: Temperature at 2 meters (Kelvin). Converted to Celsius (`K - 273.15`) and averaged per season.
  * `PRECTOT`: Precipitation (mm/day). Summed to calculate the total seasonal precipitation (mm).
* **Lagged Variable:** `lagged_seasonal_precip` was created by shifting the seasonal precipitation by one chronological season per location to capture soil moisture memory. 
* **Transformations:** To account for the highly skewed distribution of rainfall in hyper-arid environments, both the seasonal and lagged precipitation variables were **log-transformed (`log1p`)** prior to modelling.

## 3. Terrain Predictors: SRTM DEM
* **Source:** Shuttle Radar Topography Mission (SRTM) via `geodata` R package.
* **Resolution:** ~30 meters (resampled to match the 250m MODIS analysis grid).
* **Processing:** Slope was derived directly from the elevation raster using `terra::terrain(v = "slope", unit = "degrees")` and extracted to sample points.

## 4. Land Cover Predictor: MODIS MCD12Q1 (Version 6.1)
* **Source:** NASA LP DAAC.
* **Product:** MCD12Q1.061 (Year 2021, 500m resolution).
* **Band:** `LC_Type1` (IGBP Global Land Cover Classification).
* **Recoding Rules:** The original 17 IGBP classes were simplified. Irrigated cropland was excluded. The remaining classes were recoded into three ecologically meaningful categories for the Cholistan desert context:
  * `Bare_Sparse`: Classes 15 (Barren), 16 (Sparse vegetation).
  * `Grass_Shrub`: Classes 6 (Closed shrublands), 7 (Open shrublands), 9 (Savannas), 10 (Grasslands).
  * `Other`: All remaining classes (Urban, water, forests), which are rare in this study area.
* **Note:** The 2021 layer is treated as a relatively stable categorical predictor, not a time-varying record.

## 5. Study Area Boundary
* **Source:** Custom GeoPackage defining the operational dryland mask for Bahawalpur, Bahawalnagar, and Rahim Yar Khan districts, Punjab, Pakistan.
* **CRS:** WGS84 (EPSG:4326).