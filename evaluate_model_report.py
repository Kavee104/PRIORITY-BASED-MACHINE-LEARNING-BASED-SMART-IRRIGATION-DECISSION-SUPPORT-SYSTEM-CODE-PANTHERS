import pandas as pd
import numpy as np
import json
import joblib
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestRegressor
from sklearn.metrics import mean_squared_error, r2_score, mean_absolute_error

# Load dataset
df = pd.read_excel('reservoir_data_with_lag_features.xlsx')

features = [
    'Reservoir Water Level',
    'Reservoir Capacity',
    'Rainfall (Nachchaduwa)',
    'prev_day_level',
    'prev_day_release',
    'rainfall_3day_sum',
    'rainfall_7day_sum',
    'level_change'
]
target = 'Previous Water Release'

for col in features + [target]:
    df[col] = pd.to_numeric(df[col], errors='coerce').fillna(0.0)

X = df[features]
y = df[target]

X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

model = RandomForestRegressor(n_estimators=150, max_depth=12, random_state=42)
model.fit(X_train, y_train)

y_pred = model.predict(X_test)

mae = mean_absolute_error(y_test, y_pred)
rmse = np.sqrt(mean_squared_error(y_test, y_pred))
r2 = r2_score(y_test, y_pred)

report = f"""
==================== EVALUATION RESULTS ====================
Model: Random Forest Regressor (with lag features)
Total Records: {len(df)}
Training Dataset Size: {len(X_train)} (80%)
Testing Dataset Size: {len(X_test)} (20%)
Mean Absolute Error (MAE): {mae:.4f} (Release units - Acft/Day)
Root Mean Squared Error (RMSE): {rmse:.4f} (Release units - Acft/Day)
Accuracy (R2 Score): {r2 * 100:.2f}%
============================================================
"""

print(report)

# Save to text file
with open('evaluation_report.txt', 'w', encoding='utf-8') as f:
    f.write(report.strip())

print("Report saved to 'evaluation_report.txt'!")
