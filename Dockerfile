#################################################
#
# Iodine Dockerfile v1.5
# http://code.kryo.se/iodine/
#
# Based on https://github.com/FiloSottile/Dockerfiles/blob/master/iodine/Dockerfile
#
# Run with (least privilege, preferred):
# sudo docker run --device /dev/net/tun --cap-add NET_ADMIN \
#   -p 53:53/udp -e IODINE_HOST=t.example.com -e IODINE_PASSWORD=1234abc \
#   wingrunr21/iodine-docker
#
# NOTE: --privileged is not required. The container only needs the TUN device
# node and CAP_NET_ADMIN to create the tunnel interface; see README "Security
# Notes" for the threat model and for when --privileged is genuinely needed.
#
#################################################

# Use phusion/baseimage as base image, pinned to the digest published for
# the 0.9.16 tag on Docker Hub so builds are reproducible. Dependabot keeps
# this digest current (.github/dependabot.yml).
FROM phusion/baseimage@sha256:f55d261778d83def4a60d38939511cbed0268fcb91383c9e3edf2877ced289d9

LABEL maintainer="Stafford Brunk <stafford.brunk@gmail.com>"
LABEL org.opencontainers.image.title="iodine-docker"
LABEL org.opencontainers.image.description="Iodine DNS tunnel server packaged for Docker"
LABEL org.opencontainers.image.source="https://github.com/PreCogSecurity/iodine-docker"

# Set environment variables and regen SSH host keys
ENV HOME /root
RUN /etc/my_init.d/00_regen_ssh_host_keys.sh

# Install iodine
RUN apt-get update \
    && apt-get install -y --no-install-recommends net-tools iodine \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Add the runit iodine service
RUN mkdir -p /etc/service/iodined
COPY iodined.sh /etc/service/iodined/run
RUN chmod +x /etc/service/iodined/run

# Healthcheck: asks runit whether iodined is up and whether it has begun
# serving. The image must run as root (runit/my_init and the mknod of
# /dev/net/tun both require it), so no USER instruction is set here; the
# capability boundary is enforced by the run flags, not by a non-root user.
COPY healthcheck.sh /healthcheck.sh
RUN chmod +x /healthcheck.sh
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD ["/healthcheck.sh"]

# Expose the DNS port, remember to run -p 53:53/udp
EXPOSE 53/udp

# Use baseimage-docker's init system.
CMD ["/sbin/my_init"]