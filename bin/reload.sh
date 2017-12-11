#!/bin/bash

# Render Telegraf configuration template using values from Consul,
# but do not reload because Telegraf has't started yet
preStart() {
    # Do we have env vars for Triton discovery?
    # Copy creds from env vars to files on disk
    if [ -n ${!TRITON_CREDS_PATH} ] \
        && [ -n ${!TRITON_CA} ] \
        && [ -n ${!TRITON_CERT} ] \
        && [ -n ${!TRITON_KEY} ]
    then
        mkdir -p ${TRITON_CREDS_PATH}
        echo -e "${TRITON_CA}" | tr '#' '\n' > ${TRITON_CREDS_PATH}/ca.pem
        echo -e "${TRITON_CERT}" | tr '#' '\n' > ${TRITON_CREDS_PATH}/cert.pem
        echo -e "${TRITON_KEY}" | tr '#' '\n' > ${TRITON_CREDS_PATH}/key.pem
    fi

    # Are we on Triton? Do we _not_ have a user-defined DC?
    # Set the DC automatically from mdata
    if [ -n ${TRITON_DC} ] \
        && [ -f "/native/usr/sbin/mdata-get" ]
    then
        export TRITON_DC=$(/native/usr/sbin/mdata-get sdc:datacenter_name)
    fi

    # Create Telegraf config
    consul-template \
        -once \
        -dedup \
        -consul-addr ${CONSUL}:8500 \
        -template "/etc/telegraf.ctmpl:/etc/telegraf.conf"
}



# Render Telegraf configuration template using values from Consul,
# then gracefully reload Telegraf
onChange() {
    consul-template \
        -once \
        -dedup \
        -consul-addr ${CONSUL}:8500 \
        -template "/etc/telegraf.ctmpl:/etc/telegraf.conf:/usr/local/bin/reload.sh reloadConfig"
}



# SIGHUP to reload the Telegraf config
# However: if if we fire the SIGHUP to Telegraf before it has a chance to 
#   register the signal handler, then it will immediately exit.
#   This checks that Telgraf is listening on port 8094, which should only 
#   be true after the signal handler is loaded.
reloadConfig() {
    while :
    do
        netstat -ln | grep -q 8094 \
            && pkill -SIGHUP telegraf \
            && break
    done
}



help() {
    echo "Usage: ./reload.sh preStart  => first-run configuration for Telegraf"
    echo "       ./reload.sh onChange  => [default] update Telegraf config on upstream changes"
    echo "       ./reload.sh reloadConfig => reload Telegraf config on upstream changes"
}

until
    cmd=$1
    if [ -z "$cmd" ]; then
        onChange
    fi
    shift 1
    $cmd "$@"
    [ "$?" -ne 127 ]
do
    onChange
    exit
done
