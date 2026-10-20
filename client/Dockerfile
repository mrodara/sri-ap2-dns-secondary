FROM ubuntu:26.04
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       dnsutils iproute2 iputils-ping \
    && rm -rf /var/lib/apt/lists/*
CMD ["sleep", "infinity"]