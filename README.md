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

Create a network:

    $ docker network create --driver weavemesh --ipam-driver kontena-ipam --ipam-opt network=kontena kontena

The default kontena network should use the `10.81.0.0/16` subnet:

    $ docker network inspect kontena

```
[
    {
        "Name": "kontena",
        "Id": "a20f2fb2e7af333b3b30ce6d5091ef179489cd0dfff10224fffd944883c1c172",
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
                    "Gateway": "10.81.1.61/16"
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
