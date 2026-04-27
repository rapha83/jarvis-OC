FROM python:3.11-slim
ARG CERT_CN=localhost
ARG CERT_SAN=DNS:localhost,IP:127.0.0.1

RUN apt-get update && apt-get install -y \
    build-essential \
    ffmpeg \
    openssl \
    libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Generate self-signed cert for HTTPS
RUN openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
    -keyout /app/server.key \
    -out /app/server.crt \
    -subj "/CN=${CERT_CN}" \
    -addext "subjectAltName=${CERT_SAN}" 2>/dev/null

COPY server.py .
COPY static/ static/

EXPOSE 8765

CMD ["python", "server.py"]
