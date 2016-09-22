# Autopilot telegraf
Containerized telegraf server, based on the official telegraf/1.0 Docker image, adding [ContainerPilot](https://www.joyent.com/containerpilot) to announce this container's telegraf service to a Service Discovery layer, such as Consul or etcd.

### Usage
Include this image in your Docker Compose project, query Consul for it's IP address and use it in your configurations, easily done via [Consul-Template](https://github.com/hashicorp/consul-template). The default ContainerPilot configuration talks to Consul and assumes the IP address to access consul is passed to the container in an envrionment varible, $CONSUL (or via docker link consul)

Configuration of telegraf is managed via ContainerPilot `preStart` or `onChange` handlers.

Telegraf output is convigured with InfluxDB output plugin. By default telegraf is looking for InfluxDB container started in the same cluster, but it's possible to point Telegraf to remove InfluxDB server by uncommenting and setting up INFLUXDB_HOST variable in env.telegraf file

Telegraf input sources configured with prometheus input plugin and represent a list of urls pointing to container-pilot telemetry endpoints (http://container-ip:9090/metrics). Input sources reloaded automatically with `onChange` event handler.

### Hello world example

1. [Get a Joyent account](https://my.joyent.com/landing/signup/) and [add your SSH key](https://docs.joyent.com/public-cloud/getting-started).
1. Install the [Docker Toolbox](https://docs.docker.com/installation/mac/) (including `docker` and `docker-compose`) on your laptop or other environment, as well as the [Joyent Triton CLI](https://www.joyent.com/blog/introducing-the-triton-command-line-tool) (`triton` replaces our old `sdc-*` CLI tools).
1. [Configure Docker and Docker Compose for use with Joyent.](https://docs.joyent.com/public-cloud/api-access/docker)

Check that everything is configured correctly by running `./setup.sh`. This will check that your environment is setup correctly and will create an `_env` file that includes injecting an environment variable for the Consul hostname into the Telegraf and Nginx containers so we can take advantage of [Triton Container Name Service (CNS)](https://www.joyent.com/blog/introducing-triton-container-name-service).

Start everything:

```bash
docker-compose build
docker-compose up -d
```
In result we'll have 4 containers running:
- consul 
- telegraf_nginx_1 - nginx web-server is used just for demo purposes to scale and provide telemetry
- influxdb - currently running locally, but it's possible to connect with existing influxdb server
- telegraf

To verify telegraf container status you can check container log (there should be a list of records, which indicate attempts to join new input source):
```bash
docker logs telegraf 2>&1 | grep EventMemberJoin
```
it should display a list of members(input sources) recently added.

Also you check the list of input source urls for telemetry currently used by telegraf with the following command:
```bash
docker exec -i -t telegraf /bin/grep :9090 /etc/telegraf.conf
```
the list of urls includes consul container(first one in outout), telegraf container(localhost) and all other urls are nginx-container urls.
So you can check the number of urls in output, substruct 2 and it should give you a number of nginx containers


Lets scale up number of nginx containers to 3, wait for 15 seconds (give some time to telegraf to reconfigure itself) and check the number of input urls (or EventMemberJoin events in logs)
```bash
docker-compose scale nginx=3
sleep 15

# check source urls
docker exec -i -t telegraf /bin/grep :9090 /etc/telegraf.conf

# check logs
docker logs telegraf 2>&1 | grep EventMemberJoin
```

Lets scale down number of nginx containers to 1, wait for 15 seconds and check the number of input urls again:
```bash
docker-compose scale nginx=1
sleep 15

# check source urls
docker exec -i -t telegraf /bin/grep :9090 /etc/telegraf.conf
```

Finally you can check actual result of telemery aggregation(via telegraf) on InfluxDB server.
You have to open InfluxDB UI with the following command:
```bash
open "http://$(triton ip influxdb):8083/"
```
choose 'telegraf' database in dropdown located on the top-right corner, type and execute a query
```
SHOW MEASUREMENTS
```
there should be a record like 'nginx_connections_load' which represents data coming from nginx telemetry.
And the following query should display a list of nginx specfic telemetry recorods collected during last 5 minutes:
```
SELECT * FROM nginx_connections_load WHERE time > now() - 5m
```
