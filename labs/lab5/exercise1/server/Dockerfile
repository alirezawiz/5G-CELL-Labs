# Use the official Ubuntu 22.04 image as the base
FROM ubuntu:22.04

# Install Python and other necessary packages
RUN apt-get update && apt-get install -y python3 python3-pip && rm -rf /var/lib/apt/lists/*

# Set the working directory
WORKDIR /app

# Copy the server code into the container
COPY server.py .

# Run the server
CMD ["python3", "server.py"]

