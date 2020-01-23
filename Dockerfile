#
# Base install step (done first for caching purposes).
#
FROM ubuntu:bionic as base

ENV TZ="UTC"

# Run base build process
COPY ./util/docker/web/ /bd_build

RUN chmod a+x /bd_build/*.sh \
    && /bd_build/prepare.sh \
    && /bd_build/add_user.sh \
    && /bd_build/setup.sh \
    && /bd_build/cleanup.sh \
    && rm -rf /bd_build

# SFTPGo build stage
FROM golang:stretch as sftpgo
LABEL maintainer="nicola.murino@gmail.com"

RUN go get -d github.com/drakkan/sftpgo
WORKDIR /go/src/github.com/drakkan/sftpgo

ARG build_commit="8e604f888a3a3c324500ba261cd1789ee8d80f0d"

# uncomment the next line to get the latest stable version instead of the latest git
# RUN git checkout `git rev-list --tags --max-count=1`
RUN go build -i -ldflags "-s -w -X github.com/drakkan/sftpgo/utils.commit=`git describe --always --dirty` -X github.com/drakkan/sftpgo/utils.date=`date -u +%FT%TZ`" -o sftpgo

#
# Main build stage
#
FROM base

COPY --from=sftpgo /go/src/github.com/drakkan/sftpgo/sftpgo /usr/local/sbin/sftpgo

#
# START Operations as `azuracast` user
#
USER azuracast

WORKDIR /var/azuracast/www

COPY --chown=azuracast:azuracast ./composer.json ./composer.lock ./
RUN composer install \
    --no-dev \
    --no-ansi \
    --no-autoloader \
    --no-interaction \
    --no-scripts

COPY --chown=azuracast:azuracast . .

RUN composer dump-autoload --optimize --classmap-authoritative \
    && touch /var/azuracast/.docker

VOLUME ["/var/azuracast/www", "/var/azuracast/backups", "/etc/letsencrypt", "/var/azuracast/sftpgo/persist"]

#
# END Operations as `azuracast` user
#
USER root

EXPOSE 80 443 2022

# Nginx Proxy environment variables.
ENV VIRTUAL_HOST="azuracast.local" \
    HTTPS_METHOD="noredirect"

# Sensible default environment variables.
ENV APPLICATION_ENV="production" \
    MYSQL_HOST="mariadb" \
    MYSQL_PORT=3306 \
    MYSQL_USER="azuracast" \
    MYSQL_PASSWORD="azur4c457" \
    MYSQL_DATABASE="azuracast" \
    PREFER_RELEASE_BUILDS="false" \
    COMPOSER_PLUGIN_MODE="false" \
    ADDITIONAL_MEDIA_SYNC_WORKER_COUNT=0

# Entrypoint and default command
ENTRYPOINT ["dockerize",\
    "-wait","tcp://mariadb:3306",\
    "-wait","tcp://influxdb:8086",\
    "-timeout","40s"]
CMD ["/usr/local/bin/my_init"]
