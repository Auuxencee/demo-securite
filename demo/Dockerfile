# Dockerfile de démonstration VOLONTAIREMENT mal configuré :
#   - image de base ancienne (paquets système vulnérables) -> Trivy image
#   - aucune instruction USER : le conteneur tourne en root  -> Trivy config
#   - pas de HEALTHCHECK                                     -> Trivy config
FROM python:3.9-slim-bullseye

WORKDIR /app

COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ .

EXPOSE 8080
CMD ["python", "app.py"]
