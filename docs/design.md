# Design

Using a local-scope plugin allows the use of an etcd node running as a Docker container, by controlling the startup order of the Docker containers.

## Bootstrapping
The Docker node can be bootstrapped per the following process:

* Start the Docker Engine
* Start the Kontena Agent
  * Started as a systemd service
  * Runs as a Docker container using the host network
  * Controls the startup of the remaining components
* Start Weave Net
 * Runs as a Docker container using the host network
 * Uses the Kontena Agent provided peer node addresses to establish the overlay network mesh
 * Configure a statically allocated overlay network address for the host
 * Provides a network driver at `/run/docker/plugins/weavemesh`
* Start the etcd node
 * Runs as a Docker container using the host network
 * etcd uses the statically allocated overlay network address for peer communication
* Start the IPAM driver plugin
 * Runs as a Docker container using the host network
 * Uses the local etcd node at `http://localhost:2379/`
 * Provides an IPAM driver at `/run/docker/plugins/kontena-ipam`
* Start Service Containers using the Docker networks provided by the `weavemesh` and `kontena-ipam` drivers

## etcd Schema

### `/kontena/ipam/pools/kontena`

The pool subnet in `10.81.0.0/16` CIDR format.

### `/kontena/ipam/addresses/kontena/10.81.X.Y`

The address in `10.81.X.Y` format. Must match the address in the key.

## Requirements

* Register as a local scope driver
  * Uses etcd to share the IPAM configuration across Docker nodes
  * MUST support deferred etcd operations to delay any IPAM requests until the etcd cluster is available
  * The etcd cluster may not necessarily be immediately available on IPAM startup!
* Pool
  * Support automatic `RequestPool` allocation
    * Support a `--supernet` option giving a CIDR netmask
    * New subnets are allocated within the `--supernet`
    * Use some policy to determine the size of the allocated address pool size, based on the size of the `--supernet`
  * Support manual `RequestPool` allocation with an explicit pool
    * The explicit pool MAY be outside of the `--supernet`
  * #16 The same Docker network MAY be created on multiple Docker nodes
    * On the first node where the Docker network is created, the it should allocate a subnet and create a new etcd pool key.
    * On the other nodes where the same Docker network is created, it should return the subnet for the existing etcd pool key.
    * TODO: how is the Docker network identified?
      * Extend the IPAM driver API using a `docker network create --ipam-opt network=...` option?
    * Different nodes MUST use the same `--ip-range` etc configuration.
  * Correctly handle IPv4 vs IPv6 subnets
    * #10 Return an "IPv6 is unsupported" error
    * Weave does not support IPv6 anyways
* Addresses
  * #15 Allow a subset of the subnet addresses to be reserved for static allocation
    * Support `docker network create --ipam-driver kontena-ipam --subnet 10.81.0.0/16 --ip-range=10.81.128.0/17`
    * Using support for `RequestAddress` `{"SubPool": ...}` #9
    * Addresses for containers are dynamically allocated from the remainder of the subnet
    * Requried to bootstrap the node before the IPAM driver is running
    * For the default `kontena` network, these are the first `1..254` host addresses
    * Optionally use `docker network create --aux-address ...` (#6) or `--gateway` (#13) to also reserve the static addresses?
  * Allow dynamic allocation of addresses within a pool
    * #11 Do not rely on `ReleaseAddress` to clean out unused address from the pool
      * The Docker IPAM `ReleaseAddress` operations is not reliable
      * Particularly in the case of the IPAM driver running as a Docker container (#14)
      * A node being restarted and requesting new addresses for containers should not pollute the address pool with stale addresses
      * Without automatic address cleanup, the pool may eventually fill up, given enough node churn
    * Allocated addresses must owned by a Node
      * TODO: how are the node's addresses identified?
      * Store the `/kontena/ipam/addresses/$pool/$address {"Host": "..."}` node with the Host identifier?
  * Allow allocation of specific addresses
    * The addresses may be outside of the `SubPool` range reserved for dynamic allocations
    * This is used for:
      * #13 `--gateway` address allocations
      * #6 `--aux-address` allocations
      * Migration of existing containers with `io.kontena.container.overlay_cidr` addresses assigned by the Kontena Master
      * Potential future usage, such as virtual service addresses
  * Do not allow duplicate allocation of addresses
    * #4 Use etcd's consistency primitives
* Nodes
  * #11 Handle node partitions, restarts and crashes
    * Retain allocated addresses across temporary node partitions
      * Expect that the node may return, and it will still have those addresses in use
      * Avoid conflicts where the addresses were released and re-allocated elsewhere during the partition
      * Rules out the use of TTL expiry
    * A restarting node should attempt to release any addresses
      * Unless retaining them for reallocation?
    * A crashed node must be able to automatically cleanup any previously allocated addresses upon recovery
      * This means that address cleanup must not rely only on `ReleaseAddress` operations
  * #11 Cleanup addresses allocated by a node that has been explicitly removed
    * `kontena node remove ...`
    * TODO: Trigger some kind of kontena CLI -> Server -> Agent workflow where address nodes with a matching `Host` are deleted.
      * How does the Agent communicate these node-level operations to the IPAM driver?
      * Does the Agent read/write to etcd directly?

# Alternatives

## Docker Swarm Mode
Docker Swarm Mode uses its own internal cluster store, and does not support external network drivers.
If you are using Docker Swarm Mode, use the Docker default IPAM with the overlay network driver.

## Docker Cluster Store

Using Docker's global-scope IPAM or network drivers requires that the Docker Engine is configured with a cluster store (`dockerd --cluster-store=etcd://...`).
However, this causes issues at boot if the etcd cluster is not available when Docker starts, as Docker will fail to restart containers using global-scope networks.
This is particularly likely to happen if the etcd cluster store is running as a local Docker container.
When restarting Docker, the etcd container may be stopped early, and Docker will be unable to clean up any container endpoints on global-scope networks.

While this kind of "cluster store in a container" configuration is somewhat supported (https://github.com/docker/docker/pull/22561), there are also issues with the global-scope IPAM driver related to unclean shutdown / unreachable cluster-stores.

* https://github.com/docker/docker/issues/20398
* https://github.com/docker/docker/issues/23302

In particular, this can lead to a situation where the global libnetwork datastore contains stale container endpoints, which prevent starting new containers using previously allocated names:

```
$ docker rm test-1
test-1
$ docker run --name test-1 --net kontena -it debian:jessie
docker: Error response from daemon: service endpoint with name test-1 already exists.
$ docker network inspect kontena
[
    {
        "Name": "kontena",
        "Id": "b26456ff3fc6c61dabfc0f35ea61ad52097e99202266130941bc5fa5c3fd8c89",
        "Scope": "global",
        "Driver": "weave",
        "EnableIPv6": false,
        "IPAM": {
            "Driver": "default",
            "Options": {},
            "Config": [
                {
                    "Subnet": "10.81.0.0/16",
                    "IPRange": "10.81.128.0/17",
                    "Gateway": "10.81.0.1"
                }
            ]
        },
        "Internal": false,
        "Containers": {
            "c3f42fed8951907e806e46569cab03704e906fc1ddab08137638c512fb7b012b": {
                "Name": "test-2",
                "EndpointID": "d94615e1d6cbd81b12b75b1d8048946eeb0e3131745be59701ba1437e66c1b7f",
                "MacAddress": "",
                "IPv4Address": "",
                "IPv6Address": ""
            },
            "ep-1fdca69e3fb2948feb0e35c0c0b1fc35e21b3b5f3a33a1fa7e94e0254066b6e7": {
                "Name": "test-1",
                "EndpointID": "1fdca69e3fb2948feb0e35c0c0b1fc35e21b3b5f3a33a1fa7e94e0254066b6e7",
                "MacAddress": "",
                "IPv4Address": "10.81.128.0/16",
                "IPv6Address": ""
            }
        },
        "Options": {},
        "Labels": {}
    }
]
$ docker network rm kontena
Error response from daemon: network kontena has active endpoints
```

Apparently, Docker is not going to fix these issues, and will instead deprecate the external `--cluster-store` support in favor of Swarm Mode: https://github.com/docker/docker/issues/20398#issuecomment-243616886

>  this issue is not applicable to the overlay networking in swarm-mode since the Service Discovery doesn't use the KV-Store any more for its operation. **We will soon deprecate the --cluster-store configurations** and hence I recommend to close this issue **and recommend using swarm-mode**

## Weave IPAM
Weave Network has an IPAM driver using its own internal cluster store. However, it includes a number of constraints:

*  The Weave IPAM constrains the Docker Network subnets to a single `--ipalloc-range` supernet.

        $ docker network create --driver weavemesh --ipam-driver weavemesh --subnet 10.8.0.0/24 weave-8
        $ docker run --rm -it --net=weave-8 debian:jessie bash
        docker: Error response from daemon: IpamDriver.RequestAddress: 400 Bad Request: range 10.8.0.0/24 out of bounds: 10.32.0.0-10.47.255.255.

    However, the same external subnet does work with the Weave Router if using `weave attach` or an external IPAM.

* The Weave IPAM does not support automatic address pool allocation.

    `docker network create --driver weavemesh --ipam-driver weavemesh ...` without an explicit `--subnet` will create multiple Docker network using the same `--ipalloc-default-subnet` subnet.
