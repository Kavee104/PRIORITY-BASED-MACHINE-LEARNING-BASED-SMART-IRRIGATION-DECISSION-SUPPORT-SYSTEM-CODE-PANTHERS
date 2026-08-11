import requests
import pandas as pd
import numpy as np

# Live ArcGIS Dashboard backend Google Sheet CSV URL
ARCGIS_SHEET_URL = 'https://docs.google.com/spreadsheets/d/e/2PACX-1vTcSGhi9RESl7CMCl1TQnrKe07Gx5Q696YiSB9jneIHqIP9lifpqSErgI3D5k9KtQXSdW5JpycIIr5e/pub?output=csv'

# Open-Meteo Weather API endpoint for Anuradhapura / Nachchaduwa (Lat: 8.3122, Lon: 80.4131)
WEATHER_API_URL = 'https://api.open-meteo.com/v1/forecast'
DEFAULT_LAT = 8.3122
DEFAULT_LON = 80.4131


def clean_float(val, default=0.0):
    if val is None or pd.isna(val):
        return default
    val_str = str(val).strip().replace(',', '')
    if val_str in ['', '-', 'nan', 'None']:
        return default
    try:
        return float(val_str)
    except ValueError:
        return default


def fetch_open_meteo_rainfall(lat=DEFAULT_LAT, lon=DEFAULT_LON):
    """
    Fetch live rainfall data (1-day, 3-day sum, 7-day sum) from Open-Meteo API.
    """
    try:
        params = {
            'latitude': lat,
            'longitude': lon,
            'daily': 'precipitation_sum',
            'timezone': 'Asia/Colombo',
            'past_days': 7
        }
        res = requests.get(WEATHER_API_URL, params=params, timeout=10)
        if res.status_code == 200:
            data = res.json()
            precip = data.get('daily', {}).get('precipitation_sum', [])
            if precip:
                # Clean negative/nulls
                precip = [max(0.0, clean_float(p)) for p in precip]
                rainfall_today = precip[-1] if len(precip) >= 1 else 0.0
                rainfall_3day = sum(precip[-3:]) if len(precip) >= 3 else sum(precip)
                rainfall_7day = sum(precip[-7:]) if len(precip) >= 7 else sum(precip)
                return {
                    'rainfall_today': rainfall_today,
                    'rainfall_3day_sum': round(rainfall_3day, 2),
                    'rainfall_7day_sum': round(rainfall_7day, 2),
                    'source': 'Open-Meteo Weather API'
                }
    except Exception as e:
        print("Error fetching Open-Meteo rainfall:", e)
    
    return {
        'rainfall_today': 0.0,
        'rainfall_3day_sum': 0.0,
        'rainfall_7day_sum': 0.0,
        'source': 'fallback'
    }


def fetch_arcgis_reservoir_data(target_reservoir='Mahakandarawa'):
    """
    Fetch live water depth, gross capacity, date, and rainfall from ArcGIS CSV sheet.
    """
    try:
        df = pd.read_csv(ARCGIS_SHEET_URL)
        if len(df) > 4:
            target_lower = target_reservoir.lower()
            for _, row in df.iloc[4:].iterrows():
                res_name = str(row.iloc[1]) if not pd.isna(row.iloc[1]) else ''
                if target_lower in res_name.lower():
                    date_str = str(row.iloc[7]) if not pd.isna(row.iloc[7]) else ''
                    water_depth = clean_float(row.iloc[8])
                    capacity = clean_float(row.iloc[5])
                    rainfall_arcgis = clean_float(row.iloc[12], default=-1.0)
                    
                    return {
                        'found': True,
                        'reservoir_name': res_name.strip(),
                        'date': date_str.strip(),
                        'water_depth_ft': water_depth,
                        'gross_capacity_acft': capacity,
                        'rainfall_arcgis_mm': rainfall_arcgis if rainfall_arcgis >= 0 else None,
                        'source': 'ArcGIS Irrigation Dashboard'
                    }
    except Exception as e:
        print("Error fetching ArcGIS sheet:", e)
        
    return {
        'found': False,
        'reservoir_name': target_reservoir,
        'date': 'N/A',
        'water_depth_ft': 13.67,
        'gross_capacity_acft': 38420.0,
        'rainfall_arcgis_mm': None,
        'source': 'fallback'
    }


def get_realtime_feature_payload(reservoir_name='Mahakandarawa', custom_overrides=None):

    """
    Combines ArcGIS dashboard live data and Open-Meteo weather data into a feature dict
    ready for model inference.
    """
    arcgis_info = fetch_arcgis_reservoir_data(reservoir_name)
    weather_info = fetch_open_meteo_rainfall()
    
    if arcgis_info.get('rainfall_arcgis_mm') is not None:
        rainfall_val = arcgis_info['rainfall_arcgis_mm']
    else:
        rainfall_val = weather_info['rainfall_today']
        
    water_level = arcgis_info.get('water_depth_ft', 15.0)
    capacity = arcgis_info.get('gross_capacity_acft', 45157.0)
    
    payload = {
        'Reservoir Water Level': water_level,
        'Reservoir Capacity': capacity,
        'Rainfall (Nachchaduwa)': rainfall_val,
        'prev_day_level': water_level,  # Default to current level if no prev day history
        'prev_day_release': 30.0,       # Average historical baseline release
        'rainfall_3day_sum': weather_info.get('rainfall_3day_sum', 0.0),
        'rainfall_7day_sum': weather_info.get('rainfall_7day_sum', 0.0),
        'level_change': 0.0             # Default to 0 level change if same day
    }
    
    if custom_overrides and isinstance(custom_overrides, dict):
        for k, v in custom_overrides.items():
            if k in payload:
                payload[k] = clean_float(v, payload[k])
                
        payload['level_change'] = payload['Reservoir Water Level'] - payload['prev_day_level']
        
    metadata = {
        'reservoir_name': arcgis_info.get('reservoir_name', reservoir_name),
        'date': arcgis_info.get('date', 'N/A'),
        'arcgis_found': arcgis_info.get('found', False),
        'rainfall_source': weather_info.get('source', 'Open-Meteo') if arcgis_info.get('rainfall_arcgis_mm') is None else 'ArcGIS'
    }
    
    return payload, metadata


if __name__ == '__main__':
    payload, meta = get_realtime_feature_payload('Nachchaduwa')
    print("Metadata:", meta)
    print("Realtime Features:", payload)
