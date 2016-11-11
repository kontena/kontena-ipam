describe DockerClient do
  subject do
    described_class.new
  end

  describe '#ipam_networks_addresses' do
    it 'collects all docker address' do
      expect(Docker::Network).to receive(:all).and_return(
        [
          instance_double(Docker::Network, json: JSON.parse('{
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
          }')),
          instance_double(Docker::Network, json: JSON.parse('{
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
          }')),
        ]
      )

      expect{|block| subject.ipam_networks_addresses(&block)}.to yield_with_args('kontena', 'kontena', [
          IPAddr.new('10.81.128.2/16'),
      ])
    end
  end
end
