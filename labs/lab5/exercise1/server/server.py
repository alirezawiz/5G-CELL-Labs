import socket

def start_server(host='0.0.0.0', port=Port_Value):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as server_socket:
        server_socket.bind((host, port))
        print(f"Server listening on {host}:{port}")
        while True:
            data, addr = server_socket.recvfrom(1024)
            message = data.decode()
            print(f"Received '{message}' from {addr}", flush=True)
            if message == "Check_Client_Message_Value":
                server_socket.sendto(b'Server_Response_Message', addr)

if __name__ == "__main__":
    start_server()
