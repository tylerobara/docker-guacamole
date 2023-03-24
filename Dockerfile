### Dockerfile for guacamole
### Includes the mysql authentication module preinstalled

# Use phusion/baseimage as base image. To make your builds reproducible, make
# sure you lock down to a specific version, not to `latest`!
# See https://github.com/phusion/baseimage-docker/blob/master/Changelog.md for
# a list of version numbers.

##########################
### Get Guacamole Server
FROM guacamole/guacd:1.5.0 AS guacd

##########################################
### Build Guacamole Client
### Use official maven image for the build
FROM maven:3-jdk-8 AS client
ARG GUAC_VER=1.5.0

# Install chromium-driver for sake of JavaScript unit tests
RUN apt-get update && apt-get install -y chromium-driver

### Use args to build radius auth extension such as
### `--build-arg BUILD_PROFILE=lgpl-extensions`
ARG BUILD_PROFILE

# Build environment variables
ENV BUILD_DIR=/tmp/guacamole-docker-BUILD

ADD https://github.com/apache/guacamole-client/archive/${GUAC_VER}.tar.gz /tmp

RUN mkdir -p ${BUILD_DIR}                                && \
    tar -C /tmp -xzf /tmp/${GUAC_VER}.tar.gz             && \
    mv /tmp/guacamole-client-${GUAC_VER}/* ${BUILD_DIR}  && \
    mv /tmp/guacamole-client-${GUAC_VER}/.[!.]* ${BUILD_DIR}

WORKDIR ${BUILD_DIR}

### Add configuration scripts
RUN mkdir -p /opt/guacamole/bin && cp -R guacamole-docker/bin/* /opt/guacamole/bin/

### Run the build itself
RUN /opt/guacamole/bin/build-guacamole.sh "$BUILD_DIR" /opt/guacamole "$BUILD_PROFILE"

COPY cpexts.sh /opt/guacamole/bin
RUN chmod +x /opt/guacamole/bin/cpexts.sh  && /opt/guacamole/bin/cpexts.sh "$BUILD_DIR" /opt/guacamole


####################
### Build Main Image

###############################
### Build image without MariaDB
FROM alpine:latest AS nomariadb
LABEL version=1.5.0

ARG PREFIX_DIR=/opt/guacamole

### Set correct environment variables.
ENV HOME=/config
ENV LC_ALL=C.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US.UTF-8
ENV LD_LIBRARY_PATH=${PREFIX_DIR}/lib
ENV GUACD_LOG_LEVEL=info

### Copy build artifacts into this stage
COPY --from=guacd ${PREFIX_DIR} ${PREFIX_DIR}
COPY --from=client ${PREFIX_DIR} ${PREFIX_DIR}

ARG RUNTIME_DEPENDENCIES="  \
    openjdk8                \
    supervisor              \
    pwgen                   \
    ca-certificates         \
    ghostscript             \
    netcat-openbsd          \
    shadow                  \
    terminus-font           \
    ttf-dejavu              \
    ttf-liberation          \
    util-linux-login        \
    tzdata                  \
    procps                  \
    logrotate               \
    wget                    \
    bash                    \
    tini"


### Install packages and clean up in one command to reduce build size
RUN adduser -h /config -s /bin/false -u 99 -D abc                                                                                   &&\
    apk add --no-cache ${RUNTIME_DEPENDENCIES}                                                                                      && \
    xargs apk add --no-cache < ${PREFIX_DIR}/DEPENDENCIES                                                                           && \
    adduser -h /opt/tomcat -s /bin/false -D tomcat                                                                                  && \
    TOMCAT_VERSION=$(wget -qO- https://tomcat.apache.org/download-80.cgi | grep "8\.5\.[0-9]\+</a>" | sed -e 's|.*>\(.*\)<.*|\1|g') && \
    wget https://dlcdn.apache.org/tomcat/tomcat-8/v"$TOMCAT_VERSION"/bin/apache-tomcat-"$TOMCAT_VERSION".tar.gz                     && \
    tar -xf apache-tomcat-"$TOMCAT_VERSION".tar.gz                                                                                  && \
    mv apache-tomcat-"$TOMCAT_VERSION"/* /opt/tomcat                                                                                && \
    rmdir apache-tomcat-"$TOMCAT_VERSION"                                                                                           && \
    find /opt/tomcat -type d -print0 | xargs -0 chmod 700                                                                           && \
    chmod +x /opt/tomcat/bin/*.sh

ADD image /

### Link FreeRDP plugins into proper path
#RUN ${PREFIX_DIR}/bin/link-freerdp-plugins.sh ${PREFIX_DIR}/lib/freerdp2/libguac*.so

### Configure Service Startup
RUN mkdir -p /var/lib/tomcat/webapps /var/log/tomcat                                                                                                                                && \
    cp ${PREFIX_DIR}/guacamole.war /var/lib/tomcat/webapps/guacamole.war                                                                                                            && \
    ln -s /var/lib/tomcat/webapps/guacamole.war /var/lib/tomcat/webapps/ROOT.war                                                                                                    && \
    chmod +x /etc/firstrun/*.sh                                                                                                                                                     && \
    mkdir -p /config/guacamole /config/log/tomcat /var/lib/tomcat/temp /var/run/tomcat                                                                                              && \
    ln -s /opt/tomcat/conf /var/lib/tomcat/conf                                                                                                                                     && \
    ln -s /config/guacamole /etc/guacamole                                                                                                                                          && \
    ln -s /config/log/tomcat /var/lib/tomcat/logs                                                                                                                                   && \
    sed -i '/<\/Host>/i \        <Valve className=\"org.apache.catalina.valves.RemoteIpValve\"\n               remoteIpHeader=\"x-forwarded-for\" />' /opt/tomcat/conf/server.xml

EXPOSE 8080

VOLUME ["/config"]

CMD [ "/etc/firstrun/firstrun.sh" ]


############################
### Build image with MariaDB 
FROM nomariadb
LABEL version=1.5.0

RUN apk add mariadb mariadb-client

ADD image-mariadb /

RUN chmod +x /etc/firstrun/mariadb.sh

### END
### To make this a persistent guacamole container, you must map /config of this container
### to a folder on your host machine.
###
