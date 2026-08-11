import pandas as pd
import numpy as np
import joblib
import json
import os
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestRegressor, GradientBoostingRegressor
from sklearn.metrics import mean_squared_error, r2_score, mean_absolute_error

DATA_FILE = 'reservoir_data_with_lag_features.xlsx'
MODEL_FILE = 'water_release_model.pkl'
FEATURES_FILE = 'model_features.json'

FEATURE_COLUMNS = [
    'Reservoir Water Level',
    'Reservoir Capacity',
    'Rainfall (Nachchaduwa)',
    'prev_day_level',
    'prev_day_release',
    'rainfall_3day_sum',
    'rainfall_7day_sum',
    'level_change'
]
TARGET_COLUMN = 'Previous Water Release'


def train_water_release_model():
    print(f"Loading data from {DATA_FILE}...")
    df = pd.read_excel(DATA_FILE)
    
    # Fill missing values if any
    for col in FEATURE_COLUMNS + [TARGET_COLUMN]:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors='coerce').fillna(0.0)
            
    X = df[FEATURE_COLUMNS]
    y = df[TARGET_COLUMN]
    
    # Train test split (80-20)
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)
    
    # Train Random Forest Regressor
    model = RandomForestRegressor(n_estimators=150, max_depth=12, random_state=42)
    model.fit(X_train, y_train)
    
    # Evaluate
    y_pred = model.predict(X_test)
    rmse = float(np.sqrt(mean_squared_error(y_test, y_pred)))
    mae = float(mean_absolute_error(y_test, y_pred))
    r2 = float(r2_score(y_test, y_pred))
    
    print("\n--- Model Evaluation ---")
    print(f"R² Score: {r2:.4f}")
    print(f"MAE: {mae:.4f}")
    print(f"RMSE: {rmse:.4f}")
    
    # Save trained model
    joblib.dump(model, MODEL_FILE)
    print(f"\nSaved model to '{MODEL_FILE}'")
    
    # Save metadata & feature list
    metadata = {
        'target_column': TARGET_COLUMN,
        'feature_columns': FEATURE_COLUMNS,
        'metrics': {
            'r2_score': round(r2, 4),
            'mae': round(mae, 4),
            'rmse': round(rmse, 4)
        },
        'feature_importances': {
            feat: round(float(imp), 4)
            for feat, imp in zip(FEATURE_COLUMNS, model.feature_importances_)
        }
    }
    
    with open(FEATURES_FILE, 'w', encoding='utf-8') as f:
        json.dump(metadata, f, indent=2)
        
    print(f"Saved feature metadata to '{FEATURES_FILE}'")
    return model, metadata


if __name__ == '__main__':
    train_water_release_model()
