require 'net/ping/icmp'

module PingHelper

  # @param [IPAddr] ip address to ping
  # @raise [RuntimeError] requires root privileges
  # @return [Boolean]
  def ping?(ip_address, timeout: 1)
    port = 0
    icmp = Net::Ping::ICMP.new(ip_address.to_s, port, timeout)
    icmp.ping?
  end

end
