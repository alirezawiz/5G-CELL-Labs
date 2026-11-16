FROM ubuntu:22.04

RUN apt-get update && apt-get install -y python3 python3-pip
WORKDIR /app
COPY client.py /app/
RUN pip3 install requests
CMD ["python3", "client.py"]

