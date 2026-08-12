import pandas as pd
import numpy as np
import joblib
import matplotlib.pyplot as plt
import matplotlib.dates as mdates

# Set high resolution aesthetic style
plt.style.use('seaborn-v0_8-whitegrid' if 'seaborn-v0_8-whitegrid' in plt.style.available else 'default')

# Load data and trained model
df = pd.read_excel('reservoir_data_with_lag_features.xlsx')
model = joblib.load('water_release_model.pkl')

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

# Sort by Date if available
if 'Date' in df.columns:
    df['Date'] = pd.to_datetime(df['Date'])
    df = df.sort_values('Date').reset_index(drop=True)

X = df[features]
y_actual = df[target]

# Predict across full timeline
y_pred = model.predict(X)
df['Predicted_Release'] = y_pred

# Create Figure
fig, ax = plt.subplots(figsize=(14, 6), dpi=300)

if 'Date' in df.columns:
    ax.plot(df['Date'], y_actual, label='Actual Water Release (Acft/Day)', color='#1f77b4', linewidth=1.8, alpha=0.9)
    ax.plot(df['Date'], df['Predicted_Release'], label='Predicted Water Release (RF)', color='#ff7f0e', linestyle='--', linewidth=1.5, alpha=0.95)
    ax.xaxis.set_major_formatter(mdates.DateFormatter('%Y-%m'))
    ax.xaxis.set_major_locator(mdates.MonthLocator(interval=4))
    plt.xticks(rotation=0)
else:
    ax.plot(df.index, y_actual, label='Actual Water Release (Acft/Day)', color='#1f77b4', linewidth=1.8, alpha=0.9)
    ax.plot(df.index, df['Predicted_Release'], label='Predicted Water Release (RF)', color='#ff7f0e', linestyle='--', linewidth=1.5, alpha=0.95)

# Titles and Formatting
ax.set_title('Random Forest Water Release Prediction Validation', fontsize=16, fontweight='bold', pad=15)
ax.set_xlabel('Date', fontsize=12, fontweight='bold', labelpad=10)
ax.set_ylabel('Water Release (Acft/Day)', fontsize=12, fontweight='bold', labelpad=10)

# Legend
ax.legend(loc='upper left', frameon=True, facecolor='white', framealpha=0.9, fontsize=11, shadow=True)

# Grid style
ax.grid(True, linestyle=':', alpha=0.6)

plt.tight_layout()

# Save plot image
plot_file = 'water_release_prediction_plot.png'
plt.savefig(plot_file, dpi=300, bbox_inches='tight')
print(f"Successfully generated plot image: '{plot_file}'")
