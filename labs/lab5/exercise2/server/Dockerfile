FROM ubuntu:22.04

RUN apt-get update && apt-get install -y python3 python3-pip sqlite3
WORKDIR /app
COPY server.py /app/
RUN pip3 install flask
CMD ["python3", "server.py"]

