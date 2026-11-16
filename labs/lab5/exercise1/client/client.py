
import socket
import time

def start_client(server_host='server', server_port=Port_Value):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client_socket:
        while True:
            client_socket.sendto(b'Message_to_be_send', (server_host, server_port))
            print("Sent 'Message_to_be_send'")
            data, _ = client_socket.recvfrom(1024)
            print(f"Received '{data.decode()}'", flush=True)
            time.sleep(1)  # Wait for 1 second before sending the next ping

if __name__ == "__main__":
    start_client()
