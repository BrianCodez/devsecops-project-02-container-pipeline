FROM python:3.12-slim

LABEL org.opencontainers.image.description="Container pipeline demo application"

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt     && addgroup --system appgroup     && adduser --system --ingroup appgroup appuser

COPY app/ .
RUN chown -R appuser:appgroup /app

USER appuser
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3   CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/')"

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "app:app"]
