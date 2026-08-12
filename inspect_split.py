import pandas as pd
from sklearn.model_selection import train_test_split

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

print(f"Total Records: {len(df)}")
print(f"Training Set Rows: {len(X_train)} (80%)")
print(f"Testing Set Rows: {len(X_test)} (20%)\n")

train_sample = pd.concat([X_train, y_train], axis=1)
test_sample = pd.concat([X_test, y_test], axis=1)

print("=" * 60)
print("--- TRAINING SET SAMPLE (FIRST 10 ROWS) ---")
print("=" * 60)
print(train_sample.head(10).to_string())

print("\n" + "=" * 60)
print("--- TESTING SET SAMPLE (FIRST 10 ROWS) ---")
print("=" * 60)
print(test_sample.head(10).to_string())
