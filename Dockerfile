FROM postgres:17

# Устанавливаем зависимости для сборки расширений и Python
RUN apt-get update && apt-get install -y \
    postgresql-plpython3-17 \
    postgresql-17-pgvector \
    python3-pip \
    make \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Ставим нужные библиотеки Python глобально
RUN pip3 install --break-system-packages groq requests
RUN pip3 install --break-system-packages --extra-index-url https://download.pytorch.org/whl/cpu groq requests sentence-transformers torch

# Директория для сборки нашего расширения
WORKDIR /pg_extension
