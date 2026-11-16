from flask import Flask, request, jsonify
import sqlite3
import os

app = Flask(__name__)

DATABASE = os.getenv('DATABASE_PATH', '/data/db.sqlite3')

def query_database(imsi, key):
    conn = sqlite3.connect(DATABASE)
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM credentials WHERE imsi=? AND key=?", (imsi, key))
    result = cursor.fetchone()
    conn.close()
    return result

@app.route('/authenticate', methods=['POST'])
def authenticate():
    data = request.get_json()
    imsi = data.get('imsi')
    key = data.get('key')

    if query_database(imsi, key):
        return jsonify({"message": "Accepted"}), 200
    else:
        return jsonify({"message": "Declined"}), 401

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=9090)

