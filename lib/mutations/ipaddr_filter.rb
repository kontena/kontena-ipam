module Mutations
  class IPAddrFilter < Mutations::InputFilter
    @default_options = {
        :nils => false, # true allows an explicit nil to be valid. Overrides any other options
        :discard_empty => false, # If the param is optional, discard_empty: true drops empty fields.
    }

    def filter(data)
      return [data, :nils] if data.nil?
      return [data, nil] if data.is_a? IPAddr
      return [data, :empty] if data.empty?

      ipaddr = IPAddr.new(data)

      return [ipaddr, nil]

    rescue IPAddr::InvalidAddressError => error
      return [data, :invalid]
    end
  end

  HashFilter.register_additional_filter(IPAddrFilter, 'ipaddr')
  ArrayFilter.register_additional_filter(IPAddrFilter, 'ipaddr')
end
