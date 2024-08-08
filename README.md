# Seoul-Bike
Final Project of Generalized Linear Model

## Project Description
This project aims to analyze the Seoul Bike Share program data using Quasi-Poisson model. The goal is to understand the factors influencing bike rentals and to create predictive models to forecast bike rental demand. The significance of this project lies in its potential to inform urban planning and improve bike-sharing services.

## Table of Contents
- [Installation](#installation)
- [Data](#data)
- [Methodology](#methodology)
- [Results](#results)
- [Contributing](#contributing)
- [License](#license)

## Installation
Download Final_Project.Rmd, _output.yml and logo.jpg and put them in the same folder.
Download dashboard folder and deploy it by shinyapps.io for sharing, you can check model predictions by running app.R.

## Data

The dataset used in this project is related to the Seoul Bike Share program, covering the period from December 1, 2017, to November 30, 2018. The dataset contains information about bike rentals and meteorological factors. The variables included in the dataset are:

- **Date**: The date of data collection (year-month-day)
- **Rented Bike count**: The number of bikes rented per hour
- **Hour**: The hour of the day
- **Temperature**: Temperature in degrees Celsius (°C)
- **Humidity**: Humidity percentage (%)
- **Windspeed**: Wind speed in meters per second (m/s)
- **Visibility**: Visibility in 10 meters
- **Dew point temperature**: Dew point temperature in degrees Celsius (°C)
- **Solar radiation**: Solar radiation in megajoules per square meter (MJ/m²)
- **Rainfall**: Rainfall in millimeters (mm)
- **Snowfall**: Snowfall in centimeters (cm)
- **Seasons**: The season of the year (Winter, Spring, Summer, Autumn)
- **Holiday**: Whether the day is a holiday or not (Holiday/ No holiday)
- **Functioning Day**: Whether the day is a functional working day or not (Non Functional Hours, Functional hours)

### Data Source

The data is sourced from the Seoul Bike Share program and is available on [Kaggle](https://www.kaggle.com/). You can access the dataset through the following link: [Seoul Bike Share Dataset](https://www.kaggle.com/your-dataset-link).

### Data Preprocessing

1. **Missing Values**: Data doesn't contain missing values.
2. **Outliers**: We using z-score to hanle univariate outliers and mahalanobis distance to handle multivariate outliers.
3. **Feature Engineering**: New features have been created from existing variables, such as day, month, year, day_of_week to enhance the analysis.


## Methodology
We first use poisson model for modelling but it is not suitable because of overdispersion so we use quasi-poisson model instead.
Then, we use SHAP method to visualize and explain model results



