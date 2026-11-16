# server.py
from flask import Flask, jsonify
import time
import threading
import random
app = Flask(__name__)

last_response_time = 0
response_lock = threading.Lock()

@app.route('/response', methods=['GET'])
def get_response():
    global last_response_time
    
    with response_lock:
        current_time = time.time()
        if current_time - last_response_time >= 10:  # 1 second interval
            last_response_time = current_time
            return jsonify({"message": "Hello from server!", "id": random.randint(1, 100)})
        else:
            return jsonify({"message": "Please wait for a second."}), 429  # Too Many Requests

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
