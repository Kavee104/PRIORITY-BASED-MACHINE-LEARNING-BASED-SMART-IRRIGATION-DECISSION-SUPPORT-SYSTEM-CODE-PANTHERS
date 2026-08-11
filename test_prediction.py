import json
import joblib
import pandas as pd
import realtime_fetcher

def test_local_prediction():
    print("--- 1. Testing Local Model & Realtime Fetcher ---")
    payload, meta = realtime_fetcher.get_realtime_feature_payload('Nachchaduwa')
    print("Fetched Metadata:", json.dumps(meta, indent=2))
    print("Fetched Features:", json.dumps(payload, indent=2))
    
    model = joblib.load('water_release_model.pkl')
    with open('model_features.json', 'r') as f:
        meta_info = json.load(f)
        
    df_in = pd.DataFrame([payload])[meta_info['feature_columns']]
    pred = model.predict(df_in)[0]
    print(f"\n=> PREDICTED WATER RELEASE (Nachchaduwa): {pred:.4f} Acft/Day")
    assert pred >= 0, "Prediction should be non-negative"
    print("[SUCCESS] Local prediction verified!")

def test_mahakandarawa_prediction():
    print("\n--- 2. Testing Mahakandarawa Reservoir Realtime Lookup ---")
    payload, meta = realtime_fetcher.get_realtime_feature_payload('Mahakandarawa')
    print("Fetched Metadata:", json.dumps(meta, indent=2))
    print("Fetched Features:", json.dumps(payload, indent=2))
    
    model = joblib.load('water_release_model.pkl')
    with open('model_features.json', 'r') as f:
        meta_info = json.load(f)
        
    df_in = pd.DataFrame([payload])[meta_info['feature_columns']]
    pred = model.predict(df_in)[0]
    print(f"\n=> PREDICTED WATER RELEASE (Mahakandarawa): {pred:.4f} Acft/Day")
    assert pred >= 0, "Prediction should be non-negative"
    print("[SUCCESS] Mahakandarawa prediction verified!")

if __name__ == '__main__':
    test_local_prediction()
    test_mahakandarawa_prediction()
