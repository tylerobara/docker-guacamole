### Dockerfile for guacamole
### Includes the mysql authentication module preinstalled

# https://github.com/apache/guacamole-server
ARG GUAC_VER=1.6.0

# https://github.com/apache/tomcat
ARG TOMCAT_VERSION=9.0.121

########################
### Get Guacamole Server
FROM guacamole/guacd:${GUAC_VER} AS server

########################
### Get Guacamole Client
FROM guacamole/guacamole:${GUAC_VER} AS client


####################
### Build Main Image

###############################
### Build image without MariaDB
FROM alpine:3.24 AS nomariadb
ARG GUAC_VER
ARG TOMCAT_VERSION
LABEL version=$GUAC_VER

ARG PREFIX_DIR=/opt/guacamole

### Set correct environment variables.
ENV HOME=/config
ENV LC_ALL=C.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US.UTF-8
ENV LD_LIBRARY_PATH=${PREFIX_DIR}/lib
ENV GUACD_LOG_LEVEL=info
ENV LOGBACK_LEVEL=info
ENV GUACAMOLE_HOME=/config/guacamole

### Copy build artifacts into this stage
COPY --from=server ${PREFIX_DIR} ${PREFIX_DIR}
COPY --from=client ${PREFIX_DIR} ${PREFIX_DIR}

### ponytail: guacd libs link against OpenSSL 1.1, removed from Alpine >= 3.21; vendor the .so files (found via LD_LIBRARY_PATH)
COPY --from=server /lib/libssl.so.1.1 /lib/libcrypto.so.1.1 ${PREFIX_DIR}/lib/

ARG RUNTIME_DEPENDENCIES="  \
    ca-certificates         \
    ghostscript             \
    netcat-openbsd          \
    shadow                  \
    terminus-font           \
    ttf-dejavu              \
    ttf-liberation          \
    util-linux-login        \
    openjdk11-jre-headless  \
    supervisor              \
    pwgen                   \
    tzdata                  \
    procps                  \
    logrotate               \
    wget                    \
    bash                    \
    tini"

ADD image /

### Install packages and clean up in one command to reduce build size

RUN apk add --no-cache ${RUNTIME_DEPENDENCIES}                                                                                                                                      && \
    grep -vx -e libssl1.1 -e libcrypto1.1 ${PREFIX_DIR}/DEPENDENCIES | xargs apk add --no-cache                                                                                                                   && \
    adduser -h /config -s /bin/nologin -u 99 -D abc                                                                                                                                 && \
    adduser -h /opt/tomcat -s /bin/false -D tomcat                                                                                                                                  && \
    # TOMCAT_VERSION=$(curl -s "https://api.github.com/repos/apache/tomcat/tags?per_page=2000" | jq -r '[.[] | select(.name | startswith("10."))][0].name')                                                 && \
    # wget https://dlcdn.apache.org/tomcat/tomcat-$(echo "$TOMCAT_VERSION" | awk -F'.' '{print $1}')/v"$TOMCAT_VERSION"/bin/apache-tomcat-"$TOMCAT_VERSION".tar.gz                                                                     && \
    wget https://dlcdn.apache.org/tomcat/tomcat-9/v"$TOMCAT_VERSION"/bin/apache-tomcat-"$TOMCAT_VERSION".tar.gz                                                                    && \
    tar -xf apache-tomcat-"$TOMCAT_VERSION".tar.gz                                                                                                                                  && \
    mv apache-tomcat-"$TOMCAT_VERSION"/* /opt/tomcat                                                                                                                                && \
    rmdir apache-tomcat-"$TOMCAT_VERSION"                                                                                                                                           && \
    find /opt/tomcat -type d -print0 | xargs -0 chmod 700                                                                                                                           && \
    chmod +x /opt/tomcat/bin/*.sh                                                                                                                                                   && \
    mkdir -p /var/lib/tomcat/webapps /var/log/tomcat                                                                                                                                && \
    ln -s ${PREFIX_DIR}/webapp/guacamole.war /var/lib/tomcat/webapps/ROOT.war                                                                                                        && \
    chmod +x /etc/firstrun/*.sh                                                                                                                                                     && \
    mkdir -p /config/guacamole /config/log/tomcat /var/lib/tomcat/temp /var/run/tomcat                                                                                              && \
    ln -s /opt/tomcat/conf /var/lib/tomcat/conf                                                                                                                                     && \
    ln -s /config/log/tomcat /var/lib/tomcat/logs                                                                                                                                   && \
    sed -i '/<\/Host>/i \        <Valve className=\"org.apache.catalina.valves.RemoteIpValve\"\n               remoteIpHeader=\"x-forwarded-for\" />' /opt/tomcat/conf/server.xml                                                                                                  && \
    apk update && apk upgrade

### ponytail: guacamole 1.6.0 ships vulnerable nested jars with no newer release; swap in fixed versions from Maven Central
COPY patch-deps.py /tmp/patch-deps.py
RUN python3 /tmp/patch-deps.py && rm /tmp/patch-deps.py

EXPOSE 8080

VOLUME ["/config"]

CMD [ "/etc/firstrun/firstrun.sh" ]


############################
### Build image with MariaDB 
FROM nomariadb
ARG GUAC_VER
LABEL version=$GUAC_VER

RUN apk add mariadb mariadb-client

ADD image-mariadb /

RUN chmod +x /etc/firstrun/mariadb.sh

### END
### To make this a persistent guacamole container, you must map /config of this container
### to a folder on your host machine.
###
