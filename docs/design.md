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
* Pool
  * Support `RequestPool` with an empy Pool to automatically allocate new subnets
    * Support a `--supernet` option giving a CIDR netmask
    * New subnets are allocated within the `--supernet`
    * Using some policy to determine the size of the allocated address pool size, based on the size of the `--supernet`
 * Support `RequestPool` with an explicit pool
   * The explicit pool may be outside of the `--supernet`
   * Allow the same Docker network to be created on multiple Docker nodes
     * On the first node where the Docker network is created, the it should allocate a subnet and create a new etcd pool key.
     * On the other nodes where the same Docker network is created, it should return the subnet for the existing etcd pool key.
     * TODO: how is the Docker network identified?
       * The IPAM does not know the name of the Docker network.
       * Require a `docker network create --ipam-opt network=...` option?
* Addresses
  * Allow the reservation of addresses within a subnet
    * Reserved addresses are used for the statically allocated node addresses
    * Requried to bootstrap the node before the IPAM driver is running
    * For the default `kontena` network, these are the first `1..254` host addresses
    * Use `docker network create --aux-address ...`?
* Nodes
  * Retain allocated addresses across node failures
    * Do not automatically release any addresses allocated by node Containers
    * Expect that the node may return, and it will still have those addresses in use
  * Cleanup addresses allocated by a node that has been explciitly removed
    * `kontena node remove ...`
  * TODO: how are the node's addresses identified?
    * Store the `/kontena/ipam/addresses/$pool/$address {"Host": "..."}` node with the Host identifier?
    * Trigger some kind of kontena CLI -> Server -> Agent workflow where address nodes with a matching `Host` are deleted.
    * TODO: how does the Agent communicate these node-level operations to the IPAM driver?
    * TODO: does the Agent read/write to etcd directly?

# Alternatives

## Docker Swarm Mode
Docker Swarm Mode uses its own internal cluster store, and does not support external network drivers.
If you are using Docker Swarm Mode, use the Docker default IPAM with the overlay network driver.

## Docker Cluster Store

Using Docker's global-scope IPAM or network drivers requires that the Docker Engine is configured with a cluster store (`dockerd --cluster-store=etcd://...`).
However, this causes issues at boot, as the etcd cluster will not be available when Docker starts, and Docker will fail to restart containers using global-scope networks.
When restarting Docker, the etcd container may be stopped early, and Docker will be unable to clean up any container endpoints on global-scope networks.

## Weave IPAM
Weave Network has an IPAM driver using its own internal cluster store. However, it includes a number of constraints:

*  The Weave IPAM constrains the Docker Network subnets to a single `--ipalloc-range` supernet.

        $ docker network create --driver weavemesh --ipam-driver weavemesh --subnet 10.8.0.0/24 weave-8
        $ docker run --rm -it --net=weave-8 debian:jessie bash
        docker: Error response from daemon: IpamDriver.RequestAddress: 400 Bad Request: range 10.8.0.0/24 out of bounds: 10.32.0.0-10.47.255.255.

    However, the same external subnet does work with the Weave Router if using `weave attach` or an external IPAM.

* The Weave IPAM does not support automatic address pool allocation.

    `docker network create --driver weavemesh --ipam-driver weavemesh ...` without an explicit `--subnet` will create multiple Docker network using the same `--ipalloc-default-subnet` subnet.
