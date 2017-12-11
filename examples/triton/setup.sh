#!/bin/bash
set -e -o pipefail

help() {
    echo 'Usage ./setup.sh [-f docker-compose.yml] [-p project]'
    echo
    echo 'Checks that your Triton and Docker environment is sane and configures'
    echo 'an environment file to use.'
    echo
    echo 'Optional flags:'
    echo '  -f <filename>   use this file as the docker-compose config file'
    echo '  -p <project>    use this name as the project prefix for docker-compose'
}


# default values which can be overriden by -f or -p flags
export COMPOSE_PROJECT_NAME=telegraf
export COMPOSE_FILE=

# ---------------------------------------------------
# Top-level commands


# Check for correct configuration
check() {

    # check for Triton Docker CLI
    command -v triton-compose >/dev/null 2>&1 || {
        echo
        tput rev  # reverse
        tput bold # bold
        echo 'Triton Docker CLI tools are required, but do not appear to be installed.'
        tput sgr0 # clear
        echo 'See https://github.com/joyent/triton-docker-cli'
        exit 1
    }

    # check for Triton CLI tool (it should be installed, given the above, but...)
    command -v triton >/dev/null 2>&1 || {
        echo
        tput rev  # reverse
        tput bold # bold
        echo 'Error! Joyent Triton CLI is required, but does not appear to be installed.'
        tput sgr0 # clear
        echo 'See https://www.joyent.com/blog/introducing-the-triton-command-line-tool'
        exit 1
    }

    # set env vars for everything else that follows
    eval "$(triton env ${TRITON_PROFILE})"
    TRITON_DC=$(echo $SDC_URL | awk -F"/" '{print $3}' | awk -F'.' '{print $1}')
    TRITON_ACCOUNT_UUID=$(triton account get | awk -F": " '/id:/{print $2}')

    # make sure CNS is enabled
    local triton_cns_enabled=$(triton account get | awk -F": " '/cns/{print $2}')
    if [ ! "true" == "$triton_cns_enabled" ]; then
        echo
        tput rev  # reverse
        tput bold # bold
        echo 'Error! Triton CNS is required and not enabled.'
        tput sgr0 # clear
        echo
        exit 1
    fi



    echo '# Autopilot Pattern Telegraf configuration' > _env
    echo >> _env

    echo '# Telegraf output plugin: InfluxDB ' >> _env
    echo '# (uncomment to change defaults) ' >> _env
    echo '#INFLUXDB_HOST=influxdb # docker alias or real hostname' >> _env
    echo '#INFLUXDB_DATABASE=telegraf' >> _env
    echo '#INFLUXDB_DATA_ENGINE=tsm1' >> _env
    echo >> _env

    echo '# Triton Container Monitor (uses Prometheus input plugin in Telegraf)' >> _env
    echo TRITON_ACCOUNT_UUID=${TRITON_ACCOUNT_UUID} >> _env
    echo '# This works for Triton Public Cloud, but change it for other clouds:' >> _env
    echo TRITON_CNS_SUFFIX=.triton.zone >> _env
    echo '# Leave empty or unset and Autopilot Pattern Telegraf will automatically detect the DC:' >> _env
    echo '#TRITON_DC=' >> _env
    echo >> _env

    echo '# Triton Container Monitor authentication' >> _env
    TRITON_CREDS_PATH=/root/.triton
    echo TRITON_CREDS_PATH=${TRITON_CREDS_PATH} >> _env
    echo TRITON_CA=$(cat "${DOCKER_CERT_PATH}"/ca.pem | tr '\n' '#') >> _env
    echo TRITON_CA_PATH=${TRITON_CREDS_PATH}/ca.pem >> _env
    echo TRITON_KEY=$(cat "${DOCKER_CERT_PATH}"/key.pem | tr '\n' '#') >> _env
    echo TRITON_KEY_PATH=${TRITON_CREDS_PATH}/key.pem >> _env
    echo TRITON_CERT=$(cat "${DOCKER_CERT_PATH}"/cert.pem | tr '\n' '#') >> _env
    echo TRITON_CERT_PATH=${TRITON_CREDS_PATH}/cert.pem >> _env
    echo >> _env
}

# ---------------------------------------------------
# parse arguments

while getopts "f:p:h" optchar; do
    case "${optchar}" in
        f) export COMPOSE_FILE=${OPTARG} ;;
        p) export COMPOSE_PROJECT_NAME=${OPTARG} ;;
    esac
done
shift $(expr $OPTIND - 1 )

until
    cmd=$1
    if [ ! -z "$cmd" ]; then
        shift 1
        $cmd "$@"
        if [ $? == 127 ]; then
            help
        fi
        exit
    fi
do
    echo
done

# default behavior
check
