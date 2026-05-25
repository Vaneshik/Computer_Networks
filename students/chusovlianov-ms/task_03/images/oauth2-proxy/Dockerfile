FROM quay.io/oauth2-proxy/oauth2-proxy:v7.6.0 AS src

FROM alpine:3.19

RUN apk add --no-cache \
    iproute2 \
    ca-certificates \
    curl \
    busybox-extras

COPY --from=src /bin/oauth2-proxy /bin/oauth2-proxy

ENTRYPOINT ["/bin/sh"]
