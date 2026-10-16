FROM python:3.12-slim

# libgl1, libglu1-mesa, libxrender1: `import OCP` (CadQuery's OpenCascade binding) fails without them.
# poppler-utils: pdftoppm and pdftotext for the drawing renderer.
RUN apt-get update \
    && apt-get install -y --no-install-recommends libgl1 libglu1-mesa libxrender1 poppler-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY . /app
RUN pip install --no-cache-dir -e "/app[dev]"

# CMD, not ENTRYPOINT: `docker run d2c pytest ...` must replace it.
CMD ["python", "-m", "d2c.server"]
