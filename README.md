# Kontena IPAM

A Docker/libnetwork IPAM driver plugin, using etcd for cluster storage.

## Design

Allow the overlay network, etcd node and IPAM driver to be run as Docker containers.

See the [Design doc](/docs/design.md) for further details.

## Build

    docker build -t kontena-ipam .

## Usage

Run the plugin:

    docker run --rm --name kontena-ipam --net host -v /run/docker/plugins:/run/docker/plugins kontena-ipam

### Configuration

The kontena-ipam plugin uses the following environment variables for configuration:

#### `LOG_LEVEL=`

Configure the logging level. Use `LOG_LEVEL=0` for DEBUG logging.

#### `NODE_ID=$(hostname)`

Unique identifier for this Docker machine within the shared etcd store.

Used to track allocated addresses and requested address pools.

The default hostname value should work if running within the `--net host` namespace, assuming each Docker machine has an unique hostname.

#### `ETCD_ENDPOINT=http://localhost:2379`

Connect to etcd.

#### `KONTENA_IPAM_SUPERNET=10.80.0.0/12`

Allocate dynamic pool subnets from within this supernet.

#### `KONTENA_IPAM_SUBNET_LENGTH=24`

Allocate dynamic pool subnets of this CIDR prefix length.

### Create a static network

Create a statically configured network:

    $ docker network create --driver weavemesh --ipam-driver kontena-ipam --ipam-opt network=kontena --subnet 10.81.0.0/16 --ip-range 10.81.128.0/17 kontena

The default kontena network should use the `10.81.0.0/16` subnet:

    $ docker network inspect kontena

```
[
    {
        "Name": "kontena",
        "Id": "ce3b07064ccdbb1fd89b687de6278dc6e5d1105dd08613e16f1fde99b76da699",
        "Scope": "local",
        "Driver": "weavemesh",
        "EnableIPv6": false,
        "IPAM": {
            "Driver": "kontena-ipam",
            "Options": {
                "network": "kontena"
            },
            "Config": [
                {
                    "Subnet": "10.81.0.0/16",
                    "IPRange": "10.81.128.0/17"
                }
            ]
        },
        "Internal": false,
        "Containers": {
            "9d54ade90bde6f3c3fc0b7942d5e472fa2d44392b0bf9a1ea950efea412b945d": {
                "Name": "furious_hypatia",
                "EndpointID": "8af23a216a6694db947624b6b0cea92a032666a8dc19916f4944dba73740f95a",
                "MacAddress": "a2:65:de:f5:7f:8a",
                "IPv4Address": "10.81.128.25/16",
                "IPv6Address": ""
            }
        },
        "Options": {},
        "Labels": {}
    }
]
```

### Create a dynamic network

Create a dynamically configured network, letting the IPAM allocate a subnet from within the `KONTENA_IPAM_SUPERNET`:

    $ docker network create --driver weavemesh --ipam-driver kontena-ipam --ipam-opt network=kontena0 kontena0

The new kontena0 network should use a `KONTENA_IPAM_SUBNET_LENGTH=24` subnet within the `KONTENA_IPAM_SUPERNET=10.80.0.0/12`:

    $ docker network inspect kontena0
```
[
    {
        "Name": "kontena0",
        "Id": "1b9332d35ae8f278ba1f6ee6d742a84dfc41af7e407cfe338c8ed8c61d0c0b1a",
        "Scope": "local",
        "Driver": "weavemesh",
        "EnableIPv6": false,
        "IPAM": {
            "Driver": "kontena-ipam",
            "Options": {
                "network": "kontena0"
            },
            "Config": [
                {
                    "Subnet": "10.80.0.0/24",
                    "Gateway": "10.80.0.1/24"
                }
            ]
        },
        "Internal": false,
        "Containers": {},
        "Options": {},
        "Labels": {}
    }
]
```

### Cleanup

The IPAM plugin should operate in normal conditions with zero maintenance.
However, exceptional events such as Docker daemon restarts, node failures and rare race conditions may leave orphaned configuration nodes in etcd.
Use the `bin/kontena-ipam-cleanup` script to handle these situations:

    $ docker run --rm --name kontena-ipam-cleanup --net host -v /run/docker/plugins:/run/docker/plugins -v /var/run/docker.sock:/var/run/docker.sock kontena-ipam bin/kontena-ipam-cleanup

The cleanup script will:

* List the local Docker networks
* List the local container endpoints within Docker networks using the kontena-ipam
* Delete any etcd addresses allocated by the current node that are not known by Docker
* Delete any orphaned etcd address pools that are not in use on any node
