# Générateur de données factices (peuplement_velo.py), utilisé par docker-compose.
FROM python:3.12-slim

WORKDIR /app
ENV PYTHONUNBUFFERED=1

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY peuplement_velo.py .

CMD ["python", "peuplement_velo.py", "--si-vide"]
