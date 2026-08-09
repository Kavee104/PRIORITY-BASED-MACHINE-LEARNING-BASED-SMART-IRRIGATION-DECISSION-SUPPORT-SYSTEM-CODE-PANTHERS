import joblib
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestRegressor
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.model_selection import train_test_split

print("Starting Phase 2: ML Model Training Process...")

# 1. Load Unified Dataset generated in Phase 1
df = pd.read_csv('phase1_unified_dataset.csv')

# 2. Select Features (X) and Target (y)
features = [
    'Historical_Rainfall_mm',
    'Reservoir_Water_Level_ft',
    'Field_Size_acres',
    'Soil_Moisture_Pct',
    'Temperature_C',
    'Forecast_Rain_mm',
]

X = df[features]
# Convert categorical Zone column into One-Hot Encoded variables
X = pd.concat(
    [X, pd.get_dummies(df['Zone'], prefix='Zone', drop_first=True)], axis=1
)
y = df['Target_Water_Req_mm']

# 3. Train-Test Split (80% Train, 20% Test)
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42
)

# 4. Train Random Forest Regressor
print('Training Random Forest Regressor Model...')
rf_model = RandomForestRegressor(n_estimators=100, max_depth=15, random_state=42)
rf_model.fit(X_train, y_train)

# 5. Model Evaluation
y_pred = rf_model.predict(X_test)
mae = mean_absolute_error(y_test, y_pred)
rmse = np.sqrt(mean_squared_error(y_test, y_pred))
r2 = r2_score(y_test, y_pred)

print('\n================ MODEL EVALUATION RESULTS ================')
print(f'Total Records           : {len(df)}')
print(f'Training Dataset Size   : {len(X_train)}')
print(f'Testing Dataset Size    : {len(X_test)}')
print(f'Mean Absolute Error (MAE): {mae:.4f} mm')
print(f'Root Mean Squared Error : {rmse:.4f} mm')
print(f'Accuracy (R2 Score)     : {r2 * 100:.2f}%')
print('==========================================================')

# 6. Save Trained Model to .pkl file for Flask Backend Integration
model_filename = 'rf_water_requirement_model.pkl'
joblib.dump(rf_model, model_filename)
print(f"SUCCESS: Trained model saved as '{model_filename}'")