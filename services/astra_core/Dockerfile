FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt
COPY shared /app/shared
COPY services /app/services
ENV PYTHONPATH=/app
EXPOSE 8000
CMD ["uvicorn", "services.astra_core.main:app", "--host", "0.0.0.0", "--port", "8000"]
