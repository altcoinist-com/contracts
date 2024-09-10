FROM ghcr.io/foundry-rs/foundry:latest
RUN apk add supervisor curl
COPY supervisord.conf /etc/supervisord.conf
WORKDIR /tmp/contracts
COPY . .
ENTRYPOINT ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]

