FROM ubuntu:26.04
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       bind9 bind9-utils dnsutils iproute2 procps \
    && install -d -o bind -g bind -m 0775 /run/named \
    && install -d -o bind -g bind -m 0770 /var/lib/bind/slaves \
    && rm -rf /var/lib/apt/lists/*
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 0755 /usr/local/bin/docker-entrypoint.sh
EXPOSE 53/tcp 53/udp
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/usr/sbin/named", "-g", "-u", "bind"]