describe DockerClient do
  subject do
    described_class.new
  end

  describe '#networks_addresses' do
    let :docker_networks do
      JSON.parse('
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
          "2e354fb4ee65d96642ce3dc634b89e606d873573ddf0586ffdb0ce9d05683f0f": {
              "Name": "gigantic_franklin",
              "EndpointID": "a354a71d0f02c8b8859fe25d18a6507e00841cd8b109b1ef3970aed57b9c7823",
              "MacAddress": "ea:b2:ee:a2:d8:83",
              "IPv4Address": "10.81.128.2/16",
              "IPv6Address": ""
          }
      },
      "Options": {},
      "Labels": {}
  },
  {
      "Name": "bridge",
      "Id": "7033784ad3834a0d6df58618dac4c5ab71543e62a73316c05fe92c52523b707a",
      "Scope": "local",
      "Driver": "bridge",
      "EnableIPv6": false,
      "IPAM": {
          "Driver": "default",
          "Options": null,
          "Config": [
              {
                  "Subnet": "172.18.0.0/16",
                  "Gateway": "172.18.0.1"
              }
          ]
      },
      "Internal": false,
      "Containers": {
          "0f42b43d051ff859c0db756cdfc7535ae1f47dc751da2540ec58fcebd436f459": {
              "Name": "lonely_raman",
              "EndpointID": "161fce272ca8eebc2764797541caec447f532688c1cc089dfb12867fdcdbad74",
              "MacAddress": "02:42:ac:12:00:02",
              "IPv4Address": "172.18.0.2/16",
              "IPv6Address": ""
          }
      },
      "Options": {
          "com.docker.network.bridge.default_bridge": "true",
          "com.docker.network.bridge.enable_icc": "true",
          "com.docker.network.bridge.enable_ip_masquerade": "true",
          "com.docker.network.bridge.host_binding_ipv4": "0.0.0.0",
          "com.docker.network.bridge.name": "docker0",
          "com.docker.network.driver.mtu": "1500"
      },
      "Labels": {}
  }
]
      ')
    end

    it 'collects all docker address' do
      expect(Docker::Network).to receive(:all) {
        docker_networks.map{|json| instance_double(Docker::Network, json: json) }
      }

      expect{|block| subject.networks_addresses(&block)}.to yield_with_args('kontena', 'kontena', [
          IPAddr.new('10.81.128.2/16'),
      ])
    end
  end

  describe '#containers_addresses' do
    let :docker_containers do
      JSON.parse('
[
     {
      "Image" : "debian:jessie",
      "Status" : "Up 3 minutes",
      "Command" : "/bin/bash",
      "Id" : "3cf03c1c75d129157342860354c7763f413f3fc62260867b753d1a0415a2d44a",
      "NetworkSettings" : {
         "Networks" : {
            "bridge" : {
               "GlobalIPv6Address" : "",
               "Gateway" : "172.18.0.1",
               "IPAddress" : "172.18.0.2",
               "Aliases" : null,
               "EndpointID" : "128f80f44d3d2972e37e3eecc65dbb295dc558adc5bc517074bf6808e6f61162",
               "NetworkID" : "a604da5458232099f2f1ff25a8efa954e925bb4424006ab0d6b81b7d40aeb4bf",
               "IPv6Gateway" : "",
               "Links" : null,
               "IPPrefixLen" : 16,
               "IPAMConfig" : null,
               "MacAddress" : "02:42:ac:12:00:02",
               "GlobalIPv6PrefixLen" : 0
            }
         }
      },
      "Created" : 1479139603,
      "State" : "running",
      "Ports" : [],
      "Names" : [
         "/stoic_kowalevski"
      ],
      "HostConfig" : {
         "NetworkMode" : "default"
      },
      "Labels" : {
         "io.kontena.container.overlay_cidr" : "10.81.1.100/16",
         "io.kontena.container.overlay_network" : "kontena"
      },
      "Mounts" : [],
      "ImageID" : "sha256:031143c1c662878cf5be0099ff759dd219f907a22113eb60241251d29344bb96"
   },
   {
      "Status" : "Up 4 hours",
      "Image" : "kontena/etcd:2.3.3",
      "NetworkSettings" : {
         "Networks" : {
            "host" : {
               "IPPrefixLen" : 0,
               "Links" : null,
               "IPv6Gateway" : "",
               "IPAMConfig" : null,
               "MacAddress" : "",
               "GlobalIPv6PrefixLen" : 0,
               "EndpointID" : "9c791be46384a3b0c333590048575fc4449ccf8cef499a93f3c5a6f112f4b1fe",
               "Aliases" : null,
               "IPAddress" : "",
               "Gateway" : "",
               "GlobalIPv6Address" : "",
               "NetworkID" : "56946400b3f0aa69ce7af20d6bc1740953f386147f25831b032e3665789c8b36"
            }
         }
      },
      "Id" : "94f1e7137ab1096885b071de518b3b14a9ac9e2d383fa46115d6fdb716bde86f",
      "Created" : 1473929669,
      "Command" : "/usr/bin/etcd --name node-1 --data-dir /var/lib/etcd --listen-client-urls http://127.0.0.1:2379,http://10.81.0.1:2379,http://172.17.0.1:2379 --initial-cluster node-1=http://10.81.0.1:2380,node-2=http://10.81.0.2:2380 --listen-client-urls http://127.0.0.1:2379,http://10.81.0.1:2379,http://172.18.0.1:2379 --listen-peer-urls http://10.81.0.1:2380 --advertise-client-urls http://10.81.0.1:2379 --initial-advertise-peer-urls http://10.81.0.1:2380 --initial-cluster-token development --initial-cluster-state new",
      "Names" : [
         "/kontena-etcd"
      ],
      "Ports" : [],
      "State" : "running",
      "HostConfig" : {
         "NetworkMode" : "host"
      },
      "ImageID" : "sha256:d2b9aeb6045c22d90b0fa7d9e907a22ef37ca2809c814f8f124e47b1065a1c83",
      "Labels" : {},
      "Mounts" : [
         {
            "Source" : "/var/lib/docker/volumes/f324d8e405a85742bf886f8b751bcb754213b954e3fb5e238ff9d32d6e0c8f61/_data",
            "Propagation" : "",
            "RW" : true,
            "Driver" : "local",
            "Name" : "f324d8e405a85742bf886f8b751bcb754213b954e3fb5e238ff9d32d6e0c8f61",
            "Destination" : "/data",
            "Mode" : ""
         },
         {
            "Mode" : "",
            "Driver" : "local",
            "Destination" : "/var/lib/etcd",
            "Name" : "a0690b1a54b53276d74beb93e8e88c762dc5fdb6f3bb5460fa14d0098c0d072f",
            "RW" : true,
            "Source" : "/var/lib/docker/volumes/a0690b1a54b53276d74beb93e8e88c762dc5fdb6f3bb5460fa14d0098c0d072f/_data",
            "Propagation" : ""
         }
      ]
   }
]
      ')
    end

    it "collects all Docker container addresses" do
      expect(Docker::Container).to receive(:all) {
        docker_containers.map{|info| instance_double(Docker::Container, info: info)}
      }

      expect{|block| subject.containers_addresses('io.kontena.container.overlay_network', 'io.kontena.container.overlay_cidr', &block)}.to yield_with_args('kontena', [
          IPAddr.new('10.81.1.100/16'),
      ])
    end
  end
end
