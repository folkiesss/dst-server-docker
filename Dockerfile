FROM debian:stable-slim

ENV DEPOT_DOWNLOADER_VERSION=3.4.0

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    unzip \
    libcurl3t64-gnutls \
    libstdc++6 \
    libgcc-s1 \
    && rm -rf /var/lib/apt/lists/*

# Install 64-bit DepotDownloader for volume game installation and updates
WORKDIR /opt/depotdownloader
RUN curl -sSL "https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_${DEPOT_DOWNLOADER_VERSION}/DepotDownloader-linux-x64.zip" -o depotdownloader.zip \
    && unzip depotdownloader.zip \
    && rm depotdownloader.zip \
    && chmod +x DepotDownloader \
    && ln -s /opt/depotdownloader/DepotDownloader /usr/local/bin/DepotDownloader

# Set up steam user (UID 1000)
RUN useradd -u 1000 -m -s /bin/bash steam

# Copy configuration templates
COPY templates/ /etc/dst-templates/

COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER steam
WORKDIR /dst/bin64

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
