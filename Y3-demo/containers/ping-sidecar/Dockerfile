FROM python:3.11-slim

RUN apt-get update && apt-get install -y \
    curl \
    gnupg \
    iputils-ping \
    && rm -rf /var/lib/apt/lists/*

RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl \
    && kubectl version --client

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY ping_sidecar.py .

CMD ["python", "ping_sidecar.py"]
