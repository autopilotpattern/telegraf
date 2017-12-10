#!/bin/bash

SERVICE_NAME=${SERVICE_NAME:-telegraf}
CONSUL=${CONSUL:-consul}

# Render Telegraf configuration template using values from Consul,
# but do not reload because Telegraf has't started yet
preStart() {
    # sleep 5 # give some time for other containerpilots to start before rendering config
    consul-template \
        -once \
        -dedup \
        -consul ${CONSUL}:8500 \
        -template "/etc/telegraf.ctmpl:/etc/telegraf.conf"
}

# Render Telegraf configuration template using values from Consul,
# then gracefully reload Telegraf
onChange() {
    consul-template \
        -once \
        -dedup \
        -consul ${CONSUL}:8500 \
        -template "/etc/telegraf.ctmpl:/etc/telegraf.conf:/usr/local/bin/reload.sh reloadConfig"
}

# Telegraf reload th SIGHUP
# Note: if we fire SIGHUP vs node before it has a chance to register the
#   signal handler, then it will immediately exit. This ensures that
#   the process is listening on port 8094 which should only be the
#   case after we have the signal handler loaded.
reloadConfig() {
    while :
    do
        netstat -ln | grep -q 8094 && pkill -SIGHUP telegraf && break
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
