#!/bin/bash

ENV_FILE=.env

SCRATCH=$(mktemp -d -t tmp.XXXXXXXXXX)
readonly SCRATCH
function finish() (
	rm -rf "$SCRATCH"
)
trap finish EXIT

DEPLOYDIR=$(pwd)/deploy
readonly DEPLOYDIR
readonly STATEDIR=$DEPLOYDIR/state

if command -v tput >/dev/null && tput setaf 1 >/dev/null 2>&1; then
	# color codes
	RED="$(tput setaf 1)"
	GREEN="$(tput setaf 2)"
	YELLOW="$(tput setaf 3)"
	RESET="$(tput sgr0)"
fi

INFO="${GREEN:-}INFO:${RESET:-}"
ERR="${RED:-}ERROR:${RESET:-}"
WARN="${YELLOW:-}WARNING:${RESET:-}"
BLANK="      "
NEXT="${GREEN:-}NEXT:${RESET:-}"

get_distribution() (
	local lsb_dist=""
	# Every system that we officially support has /etc/os-release
	if [[ -r /etc/os-release ]]; then
		# shellcheck disable=SC1091
		lsb_dist="$(. /etc/os-release && echo "$ID")"
	fi
	# Returning an empty string here should be alright since the
	# case statements don't act unless you provide an actual value
	echo "$lsb_dist" | tr '[:upper:]' '[:lower:]'
)

get_distro_version() (
	local lsb_version="0"
	# Every system that we officially support has /etc/os-release
	if [[ -r /etc/os-release ]]; then
		# shellcheck disable=SC1091
		lsb_version="$(. /etc/os-release && echo "$VERSION_ID")"
	fi

	echo "$lsb_version"
)

is_network_configured() (
	# Require the provisioner interface have the host IP
	if ! ip addr show "$TINKERBELL_NETWORK_INTERFACE" |
		grep -q "$TINKERBELL_HOST_IP"; then
		return 1
	fi

	return 0
)


setup_network_forwarding() (
	# enable IP forwarding for docker
	if (($(sysctl -n net.ipv4.ip_forward) != 1)); then
		if [[ -d /etc/sysctl.d ]]; then
			echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-tinkerbell.conf
		elif [[ -f /etc/sysctl.conf ]]; then
			echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
		fi

		sudo sysctl net.ipv4.ip_forward=1
	fi
)


setup_osie() (
	mkdir -p "$STATEDIR/webroot"
    OSIE_DOWNLOAD_LINK="https://tinkerbell-oss.s3.amazonaws.com/osie-uploads/osie-1790-23d78ea47f794d0e5c934b604579c26e5fce97f5.tar.gz"
	local osie_current=$STATEDIR/webroot/misc/osie/current
	local tink_workflow=$STATEDIR/webroot/workflow/
	if [[ ! -d $osie_current ]] || [[ ! -d $tink_workflow ]]; then
		mkdir -p "$osie_current"
		mkdir -p "$tink_workflow"
		pushd "$SCRATCH"

		if [[ -z ${TB_OSIE_TAR:-} ]]; then
			curl "${OSIE_DOWNLOAD_LINK}" -o ./osie.tar.gz
			tar -zxf osie.tar.gz
		else
			tar -zxf "$TB_OSIE_TAR"
		fi

		if pushd osie*/; then
			if mv workflow-helper.sh workflow-helper-rc "$tink_workflow"; then
				cp -r ./* "$osie_current"
			else
				echo "$ERR failed to move 'workflow-helper.sh' and 'workflow-helper-rc'"
				exit 1
			fi
			popd
		fi
	else
		echo "$INFO found existing osie files, skipping osie setup"
	fi
)


source $ENV_FILE


generate_certificates() (
	
	mkdir -p "$STATEDIR/certs"
	mkdir -p "$STATEDIR/webroot"

	if ! [[ -f "$STATEDIR/certs/ca.json" ]]; then
		jq \
			'.
			 | .names[0].L = $facility
			' \
			"$DEPLOYDIR/tls/ca.in.json" \
			--arg ip "$TINKERBELL_HOST_IP" \
			--arg facility "$FACILITY" \
			>"$STATEDIR/certs/ca.json"
	fi

	if ! [[ -f "$STATEDIR/certs/server-csr.json" ]]; then
		jq \
			'.
			| .hosts += [ $ip, "tinkerbell.\($facility).packet.net" ]
			| .names[0].L = $facility
			| .hosts = (.hosts | sort | unique)
			' \
			"$DEPLOYDIR/tls/server-csr.in.json" \
			--arg ip "$TINKERBELL_HOST_IP" \
			--arg facility "$FACILITY" \
			>"$STATEDIR/certs/server-csr.json"
	fi

	podman build --tag "tinkerbell-certs" "$DEPLOYDIR/tls" 
	podman run --rm \
		--volume "$STATEDIR/certs:/certs:Z" \
		localhost/tinkerbell-certs

	local certs_dir="/etc/containers/certs.d/$TINKERBELL_HOST_IP"

	# copy public key to NGINX for workers
	if ! cmp --quiet "$STATEDIR/certs/ca.pem" "$STATEDIR/webroot/workflow/ca.pem"; then
		cp "$STATEDIR/certs/ca.pem" "$STATEDIR/webroot/workflow/ca.pem"
	fi

	# update host to trust registry certificate
	if ! cmp --quiet "$STATEDIR/certs/ca.pem" "$certs_dir/tinkerbell.crt"; then
		if ! [[ -d "$certs_dir/" ]]; then
			# The user will be told to create the directory
			# in the next block, if copying the certs there
			# fails.
			sudo mkdir -p "$certs_dir" || true >/dev/null 2>&1
		fi
		if ! sudo cp "$STATEDIR/certs/ca.pem" "$certs_dir/tinkerbell.crt"; then
			echo "$ERR please copy $STATEDIR/certs/ca.pem to $certs_dir/tinkerbell.crt"
			echo "$BLANK and run $0 again:"

			if ! [[ -d $certs_dir ]]; then
				echo "sudo mkdir -p '$certs_dir'"
			fi
			echo "sudo cp '$STATEDIR/certs/ca.pem' '$certs_dir/tinkerbell.crt'"

			exit 1
		fi
	fi
)



#### Build our local container registry image with an embeded password from .env
build_registry_image() (
    #### Have to insert the full path to the registry that we are looking for
    sed -i 's|FROM .*|FROM docker.io/library/registry:2.7.1|' $DEPLOYDIR/registry/Dockerfile

    podman build \
            --build-arg=REGISTRY_USERNAME=$TINKERBELL_REGISTRY_USERNAME \
            --build-arg=REGISTRY_PASSWORD=$TINKERBELL_REGISTRY_PASSWORD \
            --tag localhost/tinkerbell-registry \
            --file $DEPLOYDIR/registry/Dockerfile

)


start_registry() (

    #### make registry directory
	mkdir -p $STATEDIR/registry

    podman run --detach \
               --name tinkerbell-registry \
               --publish 443:443 \
               --env REGISTRY_USERNAME=$TINKERBELL_REGISTRY_USERNAME \
               --env REGISTRY_PASSWORD=$TINKERBELL_REGISTRY_PASSWORD \
               --env REGISTRY_HTTP_ADDR=0.0.0.0:443 \
               --env REGISTRY_HTTP_TLS_CERTIFICATE=/certs/server.pem \
               --env REGISTRY_HTTP_TLS_KEY=/certs/server-key.pem \
               --env REGISTRY_AUTH=htpasswd \
               --env REGISTRY_AUTH_HTPASSWD_REALM="Registry Realm" \
               --env REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
               --volume $DEPLOYDIR/state/certs:/certs:Z \
               --volume $DEPLOYDIR/state/registry:/var/lib/registry:Z \
               localhost/tinkerbell-registry
)

podman_login() (
	echo -n "$TINKERBELL_REGISTRY_PASSWORD" | podman login -u="$TINKERBELL_REGISTRY_USERNAME" --password-stdin "$TINKERBELL_HOST_IP"
)


setup_network_forwarding
setup_osie
generate_certificates
build_registry_image
start_registry

podman_login


podman pull hello-world
podman tag hello-world ${TINKERBELL_HOST_IP}/hello-world
podman push ${TINKERBELL_HOST_IP}/hello-world
