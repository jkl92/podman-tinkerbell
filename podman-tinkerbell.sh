#!/bin/bash

ENV_FILE=.env
source $ENV_FILE

export TINKERBELL_TINK_SERVER_IMAGE=quay.io/tinkerbell/tink:sha-1b178dae
export TINKERBELL_TINK_CLI_IMAGE=quay.io/tinkerbell/tink-cli:sha-1b178dae
export TINKERBELL_TINK_BOOTS_IMAGE=quay.io/tinkerbell/boots:sha-ad742e11
export TINKERBELL_TINK_HEGEL_IMAGE=quay.io/tinkerbell/hegel:sha-c8a68311
export TINKERBELL_TINK_WORKER_IMAGE=quay.io/tinkerbell/tink-worker:sha-1b178dae


export TINKERBELL_POSTGRES_IMAGE=docker.io/library/postgres:10-alpine
export TINKBERBELL_NGINX_IMAGE=docker.io/library/nginx:alpine

DEPLOYDIR=$(pwd)/deploy
readonly DEPLOYDIR
readonly STATEDIR=$DEPLOYDIR/state


podman rm -f --ignore tink-server tink-server-migration tink-cli hegel nginx boots db
podman rm -f --ignore tink-server tink-server-migration tink-cli hegel nginx boots db

podman run --detach \
           --name db \
           --net host \
           --publish 5432:5432/tcp \
           --env POSTGRES_DB=tinkerbell \
           --env POSTGRES_PASSWORD=tinkerbell \
           --env POSTGRES_USER=tinkerbell \
           --volume postgres_data:/var/lib/postgresql/data:rw \
           ${TINKERBELL_POSTGRES_IMAGE}          

podman run --detach \
           --name tink-server-migration \
           --restart on-failure \
           --net host \
           --requires db \
           --volume $DEPLOYDIR/state/certs:/certs/${FACILITY:-onprem}:Z \
           --env ONLY_MIGRATION="true" \
           --env FACILITY={FACILITY:-onprem} \
           --env PGDATABASE=tinkerbell \
           --env PGHOST=${TINKERBELL_HOST_IP} \
           --env PGPASSWORD=tinkerbell \
           --env PGPORT=5432 \
           --env PGSSLMODE=disable \
           --env PGUSER=tinkerbell \
           --env TINKERBELL_GRPC_AUTHORITY=:42113 \
           --env TINKERBELL_HTTP_AUTHORITY=42114 \
           --env TINK_AUTH_USERNAME=${TINKERBELL_TINK_USERNAME} \
           --env TINK_AUTH_PASSWORD=${TINKERBELL_TINK_PASSWORD} \
           ${TINKERBELL_TINK_SERVER_IMAGE}

podman run --detach \
           --name tink-server \
           --net host \
           --restart unless-stopped \
           --publish 42113:42113/tcp \
           --publish 42114:42114/tcp \
           --requires db \
           --volume $DEPLOYDIR/state/certs:/certs/${FACILITY:-onprem}:Z \
           --env FACILITY=${FACILITY:-onprem} \
           --env PACKET_ENV=${PACKET_ENV:-testing} \
           --env PACKET_VERSION=${PACKET_VERSION:-ignored} \
           --env ROLLBAR_TOKEN=${ROLLBAR_TOKEN:-ignored} \
           --env ROLLBAR_DISABLE=${ROLLBAR_DISABLE:-1} \
           --env PGDATABASE=tinkerbell \
           --env PGHOST=${TINKERBELL_HOST_IP} \
           --env PGPASSWORD=tinkerbell \
           --env PGPORT=5432 \
           --env PGSSLMODE=disable \
           --env PGUSER=tinkerbell \
           --env TINKERBELL_GRPC_AUTHORITY=:42113 \
           --env TINKERBELL_HTTP_AUTHORITY=:42114 \
           --env TINK_AUTH_USERNAME=${TINKERBELL_TINK_USERNAME} \
           --env TINK_AUTH_PASSWORD=${TINKERBELL_TINK_PASSWORD} \
           ${TINKERBELL_TINK_SERVER_IMAGE}

podman run --detach \
           --name tink-cli \
           --net host \
           --restart unless-stopped \
           --requires db \
           --requires tink-server \
           --env TINKERBELL_GRPC_AUTHORITY=127.0.0.1:42113 \
           --env TINKERBELL_CERT_URL=http://127.0.0.1:42114/cert \
           ${TINKERBELL_TINK_CLI_IMAGE}

podman run --detach \
           --name hegel \
           --net host \
           --restart unless-stopped \
           --requires db \
           --env ROLLBAR_TOKEN=${ROLLBAR_TOKEN-ignored} \
           --env ROLLBAR_DISABLE=1 \
           --env PACKET_ENV=testing \
           --env PACKET_VERSION=${PACKET_VERSION:-ignored} \
           --env GRPC_PORT=42115 \
           --env HEGEL_FACILITY=${FACILITY:-onprem} \
           --env HEGEL_USE_TLS=0 \
           --env TINKERBELL_GRPC_AUTHORITY=127.0.0.1:42113 \
           --env TINKERBELL_CERT_URL=http://127.0.0.1:42114/cert \
           --env DATA_MODEL_VERSION=1 \
           --env CUSTOM_ENDPOINTS='{"/metadata":""}' \
           ${TINKERBELL_TINK_HEGEL_IMAGE}

podman run --detach \
           --name boots \
           --publish 80:80/tcp \
           --publish 67:67/udp \
           --publish 69:69/udp \
           --net host \
           --env API_AUTH_TOKEN=${PACKET_API_AUTH_TOKEN:-ignored} \
           --env API_CONSUMER_TOKEN=${PACKET_CONSUMER_TOKEN:-ignored} \
           --env FACILITY_CODE=${FACILITY:-onprem} \
           --env PACKET_ENV=${PACKET_ENV:-testing} \
           --env PACKET_VERSION=${PACKET_VERSION:-ignored} \
           --env ROLLBAR_TOKEN=${ROLLBAR_TOKEN:-ignored} \
           --env ROLLBAR_DISABLE=${ROLLBAR_DISABLE:-1} \
           --env MIRROR_HOST=${TINKERBELL_HOST_IP:-127.0.0.1}:8080 \
           --env DNS_SERVERS=8.8.8.8 \
           --env PUBLIC_IP=$TINKERBELL_HOST_IP \
           --env BOOTP_BIND=$TINKERBELL_HOST_IP:67 \
           --env HTTP_BIND=$TINKERBELL_HOST_IP:80 \
           --env SYSLOG_BIND=$TINKERBELL_HOST_IP:514 \
           --env TFTP_BIND=$TINKERBELL_HOST_IP:69 \
           --env DOCKER_REGISTRY=$TINKERBELL_HOST_IP \
           --env REGISTRY_USERNAME=$TINKERBELL_REGISTRY_USERNAME \
           --env REGISTRY_PASSWORD=$TINKERBELL_REGISTRY_PASSWORD \
           --env TINKERBELL_GRPC_AUTHORITY=$TINKERBELL_HOST_IP:42113 \
           --env TINKERBELL_CERT_URL=http://$TINKERBELL_HOST_IP:42114/cert \
           --env ELASTIC_SEARCH_URL=$TINKERBELL_HOST_IP:9200 \
           --env DATA_MODEL_VERSION=1 \
           ${TINKERBELL_TINK_BOOTS_IMAGE} -dhcp-addr 0.0.0.0:67 -tftp-addr $TINKERBELL_HOST_IP:69  -http-addr $TINKERBELL_HOST_IP:80 -log-level DEBUG

podman run --detach \
           --name nginx \
           --tty \
           --publish 8080:80/tcp \
           --volume ${DEPLOYDIR}/state/webroot:/usr/share/nginx/html:Z \
           ${TINKBERBELL_NGINX_IMAGE}
