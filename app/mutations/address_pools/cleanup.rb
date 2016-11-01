module AddressPools
  class Cleanup < Mutations::Command
    include Logging

    def execute
      AddressPool.list.each do |pool|
        if pool.orphaned?
          info "Deleting orphaned address pool: #{pool}"

          pool.delete!
        end
      end
    end
  end
end
