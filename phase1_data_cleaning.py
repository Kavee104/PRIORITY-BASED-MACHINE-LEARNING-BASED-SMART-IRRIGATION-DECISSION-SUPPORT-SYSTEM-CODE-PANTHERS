import pandas as pd
import numpy as np
import datetime
import re

print("Starting Phase 1 Data Cleaning & Preparation Process...")

# 1. Load and Process Nachchaduwa Rainfall Excel Data
rain_file = 'Nachchaduwa_Rainfall_Data_Cleaned_2009-2026 (2).xlsx'
df_rain = pd.read_excel(rain_file, sheet_name='Cleaned Data')
df_rain['Date'] = pd.to_datetime(df_rain['Date'])
df_rain_clean = df_rain[['Date', 'Rain Fall (mm)']].rename(columns={'Rain Fall (mm)': 'Historical_Rainfall_mm'})
df_rain_clean['Historical_Rainfall_mm'] = df_rain_clean['Historical_Rainfall_mm'].fillna(0.0)

# 2. Function to parse Mahakanadarawa feet-inch string formats (e.g. 19' - 10" -> 19.83)
def parse_ft_str(val):
    if pd.isna(val):
        return np.nan
    if isinstance(val, (int, float)):
        return float(val)
    val_str = str(val).strip()
    if not val_str or val_str.lower() in ['nan', '-', '']:
        return np.nan
    m = re.match(r"^(\d+)['\s\-\–]+(\d+)", val_str)
    if m:
        feet = float(m.group(1))
        inches = float(m.group(2))
        return feet + inches / 12.0
    try:
        clean_num = re.findall(r"[-+]?\d*\.\d+|\d+", val_str)
        if clean_num:
            return float(clean_num[0])
    except:
        pass
    return np.nan

# 3. Load and Process Mahakanadarawa Water Level Excel Data across all 36 sheets (1990-2025)
water_file = 'Water Level in Mahakandarawa 1990 to 2025.xlsx'
excel_water = pd.ExcelFile(water_file)

records = []
for sheet in excel_water.sheet_names:
    df_raw = pd.read_excel(excel_water, sheet_name=sheet)
    date_col_idx, wl_col_idx, cap_col_idx = None, None, None
    for r in range(min(5, len(df_raw))):
        row_vals = [str(v).lower() for v in df_raw.iloc[r].values]
        for c, v in enumerate(row_vals):
            if 'date' in v and date_col_idx is None:
                date_col_idx = c
            if 'water level' in v and wl_col_idx is None:
                wl_col_idx = c
            if 'capacity' in v and cap_col_idx is None:
                cap_col_idx = c
                
    if 'year' in [str(v).lower() for v in df_raw.iloc[0].values] and 'month' in [str(v).lower() for v in df_raw.iloc[0].values]:
        for idx in range(2, len(df_raw)):
            row = df_raw.iloc[idx]
            y, m, d = row.iloc[0], row.iloc[1], row.iloc[2]
            wl = row.iloc[3]
            cap = row.iloc[5] if len(row) > 5 else np.nan
            if pd.notna(y) and pd.notna(m) and pd.notna(d):
                try:
                    dt = pd.to_datetime(f"{int(y)}-{m}-{int(d)}")
                    records.append({'Date': dt, 'Reservoir_Water_Level_ft': parse_ft_str(wl), 'Reservoir_Capacity_AcFt': parse_ft_str(cap)})
                except:
                    pass
    else:
        c_date = date_col_idx if date_col_idx is not None else 0
        c_wl = wl_col_idx if wl_col_idx is not None else 1
        c_cap = cap_col_idx if cap_col_idx is not None else 2
        for idx in range(0, len(df_raw)):
            row = df_raw.iloc[idx]
            dt_val = row.iloc[c_date]
            if pd.notna(dt_val) and not isinstance(dt_val, str) and isinstance(dt_val, (pd.Timestamp, datetime.datetime)):
                dt = pd.to_datetime(dt_val)
                records.append({'Date': dt, 'Reservoir_Water_Level_ft': parse_ft_str(row.iloc[c_wl]), 'Reservoir_Capacity_AcFt': parse_ft_str(row.iloc[c_cap]) if len(row) > c_cap else np.nan})
            elif pd.notna(dt_val):
                try:
                    dt = pd.to_datetime(dt_val)
                    if 1990 <= dt.year <= 2026:
                        records.append({'Date': dt, 'Reservoir_Water_Level_ft': parse_ft_str(row.iloc[c_wl]), 'Reservoir_Capacity_AcFt': parse_ft_str(row.iloc[c_cap]) if len(row) > c_cap else np.nan})
                except:
                    pass

df_water_clean = pd.DataFrame(records).drop_duplicates(subset=['Date']).sort_values('Date').reset_index(drop=True)
df_water_clean['Reservoir_Water_Level_ft'] = df_water_clean['Reservoir_Water_Level_ft'].ffill().bfill()

# Clean outliers in reservoir water level (e.g. capped at spill height ~21ft)
df_water_clean.loc[df_water_clean['Reservoir_Water_Level_ft'] > 30, 'Reservoir_Water_Level_ft'] = 21.0

# 4. Merge Historical Datasets on Date
df_unified = pd.merge(df_rain_clean, df_water_clean, on='Date', how='inner')

# 5. Synthesize Field Profile & IoT Sensor Variables
np.random.seed(42)
fields = ['F_001', 'F_002', 'F_003', 'F_004', 'F_005']
zones_map = {'F_001': 'Middle', 'F_002': 'Tail-End', 'F_003': 'Tail-End', 'F_004': 'Middle', 'F_005': 'Middle'}

df_expanded = []
for f_id in fields:
    df_temp = df_unified.copy()
    df_temp['Field_ID'] = f_id
    df_temp['Zone'] = zones_map[f_id]
    df_temp['Field_Size_acres'] = np.round(np.random.uniform(1.0, 5.0, len(df_temp)), 1)
    df_temp['Soil_Moisture_Pct'] = np.round(np.random.uniform(12.0, 80.0, len(df_temp)), 2)
    df_temp['Temperature_C'] = np.round(np.random.uniform(24.0, 36.0, len(df_temp)), 1)
    df_temp['Forecast_Rain_mm'] = np.round(np.random.uniform(0.0, 30.0, len(df_temp)), 1)
    
    # Ground truth water requirement formula (Target mm)
    base_req = np.maximum(0, (75.0 - df_temp['Soil_Moisture_Pct']) * 0.8 + (df_temp['Temperature_C'] - 25.0) * 0.5 - df_temp['Forecast_Rain_mm'] * 0.4)
    df_temp['Target_Water_Req_mm'] = np.round(base_req, 2)
    df_expanded.append(df_temp)

df_final = pd.concat(df_expanded, ignore_index=True)

# 6. Priority Urgency Score & Mode Selection Logic
def calculate_urgency_and_mode(row, dead_storage_limit=10.0):
    soil_moist = row['Soil_Moisture_Pct']
    zone = row['Zone']
    forecast_rain = row['Forecast_Rain_mm']
    water_level = row['Reservoir_Water_Level_ft']

    zone_weight = 1.5 if zone == 'Tail-End' else (1.2 if zone == 'Middle' else 1.0)
    urgency_score = ((100 - soil_moist) * 0.5) + (zone_weight * 20) - (forecast_rain * 0.3)
    urgency_score = max(0.0, round(urgency_score, 2))

    if water_level <= dead_storage_limit:
        mode = 'MODE_C_EMERGENCY_LOCKOUT'
    elif water_level < 18.0:
        mode = 'MODE_B_TAIL_END_PRIORITY'
    else:
        mode = 'MODE_A_FULL_ALLOCATION'

    return pd.Series([urgency_score, mode])

df_final[['Urgency_Score', 'Irrigation_Mode']] = df_final.apply(calculate_urgency_and_mode, axis=1)

# Save Cleaned Output to CSV & XLSX
df_final.to_csv('phase1_unified_dataset.csv', index=False)
df_final.to_excel('phase1_unified_dataset.xlsx', index=False)

print("SUCCESS: Phase 1 Data Cleaning finished!")
print("Outputs generated: 'phase1_unified_dataset.csv' and 'phase1_unified_dataset.xlsx'")
