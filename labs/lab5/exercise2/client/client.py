import requests
import os

# Get IMSI and Key from environment variables
IMSI = os.getenv('IMSI')
KEY = os.getenv('KEY')

def send_credentials(imsi, key):
    url = 'http://server:9090/authenticate'
    data = {
        "imsi": imsi,
        "key": key
    }
    response = requests.post(url, json=data)
    if response.status_code == 200:
        print(response.json().get('message'))
    else:
        print(response.json().get('message'))

if __name__ == "__main__":
    if IMSI and KEY:
        send_credentials(IMSI, KEY)
    else:
        print("IMSI and KEY must be provided")

