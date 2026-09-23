#################################################
#
# Iodine Dockerfile v1.4
# http://code.kryo.se/iodine/
#
# Based on https://github.com/FiloSottile/Dockerfiles/blob/master/iodine/Dockerfile
#
# Run with:
# sudo docker run --privileged -p 53:53/udp -e IODINE_HOST=t.example.com -e IODINE_PASSWORD=1234abc wingrunr21/iodine
#
#################################################

# Use phusion/baseimage as base image, pinned to the digest published for
# the 0.9.16 tag on Docker Hub so builds are reproducible.
FROM phusion/baseimage@sha256:f55d261778d83def4a60d38939511cbed0268fcb91383c9e3edf2877ced289d9

LABEL maintainer="Stafford Brunk <stafford.brunk@gmail.com>"

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

# Expose the DNS port, remember to run -p 53:53/udp
EXPOSE 53/udp

# Use baseimage-docker's init system.
CMD ["/sbin/my_init"]
