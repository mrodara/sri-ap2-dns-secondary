#!/bin/sh
set -eu
install -d -o bind -g bind -m 0775 /run/named
install -d -o bind -g bind -m 0770 /var/lib/bind/slave
exec "$@"