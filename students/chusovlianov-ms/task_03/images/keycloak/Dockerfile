# Stage 1: grab `ip` binary + its shared libs from ubi-minimal
FROM registry.access.redhat.com/ubi9/ubi-minimal:9.3 AS tools

RUN microdnf install -y iproute && microdnf clean all

# Stage 2: Keycloak + ip
FROM quay.io/keycloak/keycloak:24.0

USER root

COPY --from=tools /usr/sbin/ip           /usr/sbin/ip
COPY --from=tools /usr/lib64/libbpf.so.1  /usr/lib64/libbpf.so.1
COPY --from=tools /usr/lib64/libelf.so.1  /usr/lib64/libelf.so.1
COPY --from=tools /usr/lib64/libmnl.so.0  /usr/lib64/libmnl.so.0
COPY --from=tools /usr/lib64/libcap.so.2  /usr/lib64/libcap.so.2
COPY --from=tools /usr/lib64/libz.so.1    /usr/lib64/libz.so.1
COPY --from=tools /usr/lib64/libzstd.so.1 /usr/lib64/libzstd.so.1

RUN ln -sf /usr/sbin/ip /usr/bin/ip

USER 1000
