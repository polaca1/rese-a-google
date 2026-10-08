FROM debian:13-slim
ENV container=docker
RUN apt-get update && apt-get install -y --no-install-recommends systemd-sysv iproute2 python3 python3-venv python3-tk curl ca-certificates polkitd pkexec unattended-upgrades xvfb xauth && rm -rf /var/lib/apt/lists/*
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
