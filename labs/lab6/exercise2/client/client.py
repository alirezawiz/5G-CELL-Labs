# client.py
import requests
import time

SERVER_URL = "http://flask-server:5000/response"

def main():
    while True:  # Continuously send requests
        response = requests.get(SERVER_URL)
        response_data = response.json()
        
        if response.status_code == 200:
            print(f"Response: {response_data}", flush=True)  # Successful response
        else:
            print(f"Response: {response_data['message']}",flush=True)  # Rate limit message

        time.sleep(0.5)  # Small delay to avoid overwhelming the server

if __name__ == "__main__":
    main()
