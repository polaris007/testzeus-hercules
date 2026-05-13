# Use an official Python 3.11 image based on Ubuntu
#FROM python:3.11-slim
FROM python:3.11-slim-bookworm 

ENV http_proxy=http://172.29.0.1:7890
ENV https_proxy=http://172.29.0.1:7890

# Install build tools and system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    python3-dev \
    build-essential \
    curl \
    wget \
    unzip \
    ca-certificates \
    fonts-liberation \
    libasound2 \
    libatk-bridge2.0-0 \
    libdrm2 \
    libxcomposite1 \
    libxdamage1 \
    libxrandr2 \
    libgbm1 \
    libxkbcommon0 \
    libxss1 \
    && rm -rf /var/lib/apt/lists/*

# Set the working directory in the container
WORKDIR /testzeus-hercules

# Copy the project files (needed for building the local package)
COPY . /testzeus-hercules

# Install UV
RUN pip install uv

# Install dependencies (no dev dependencies)
RUN uv sync --frozen --no-dev

# Install Playwright browsers (without system deps - they'll be installed at runtime if needed)
RUN uv run playwright install

# 3. 安装浏览器二进制文件
RUN uv run playwright install chromium
# 或
# RUN playwright install chromium
# 取决于你的环境配置

# 4. （可选但推荐）用 Playwright 验证依赖
RUN uv run playwright install-deps

RUN mkdir -p /testzeus-hercules/.cache/browser/chromium/extension && \
    wget -O /testzeus-hercules/.cache/browser/chromium/extension/uBlock0_1.61.0.chromium.zip \
    "https://github.com/gorhill/uBlock/releases/download/1.61.0/uBlock0_1.61.0.chromium.zip" && \
    cd /testzeus-hercules/.cache/browser/chromium/extension && \
    unzip -o uBlock0_1.61.0.chromium.zip -d uBlock0_1.61.0.chromium/

#RUN mkdir -p /root/.cache/hercules/extensions/chromium && \
#    wget -O /root/.cache/hercules/extensions/chromium/uBlock0_1.61.0.chromium.zip \
#    "https://github.com/gorhill/uBlock/releases/download/1.61.0/uBlock0_1.61.0.chromium.zip" && \
#    cd /root/.cache/hercules/extensions/chromium && \
#    unzip -o uBlock0_1.61.0.chromium.zip -d uBlock0_1.61.0.chromium/

ENV http_proxy=
ENV https_proxy=

# Make entrypoint executable
RUN chmod +x /testzeus-hercules/entrypoint.sh

# Define the entrypoint
ENTRYPOINT ["/testzeus-hercules/entrypoint.sh"]

