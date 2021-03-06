require 'backends/opennebula/base'

module Backends
  module Opennebula
    class Networkinterface < Base
      include Backends::Helpers::Entitylike
      include Backends::Helpers::AttributesTransferable
      include Backends::Helpers::MixinsAttachable
      include Backends::Helpers::ErbRenderer

      class << self
        # @see `served_class` on `Entitylike`
        def served_class
          Occi::Infrastructure::Networkinterface
        end

        # :nodoc:
        def entity_identifier
          Occi::Infrastructure::Constants::NETWORKINTERFACE_KIND
        end
      end

      # @see `Entitylike`
      def identifiers(filter = Set.new)
        logger.debug { "#{self.class}: Listing identifiers with filter #{filter.inspect}" }
        nis = Set.new
        pool(:virtual_machine, :info_mine).each do |vm|
          vm.each('TEMPLATE/NIC') do |nic|
            nis << Constants::Networkinterface::ATTRIBUTES_CORE['occi.core.id'].call([nic, vm])
          end
        end
        nis
      end

      # @see `Entitylike`
      def list(filter = Set.new)
        logger.debug { "#{self.class}: Listing instances with filter #{filter.inspect}" }
        coll = Occi::Core::Collection.new
        pool(:virtual_machine, :info_mine).each do |vm|
          vm.each('TEMPLATE/NIC') { |nic| coll << networkinterface_from(nic, vm) }
        end
        coll
      end

      # @see `Entitylike`
      def instance(identifier)
        logger.debug { "#{self.class}: Getting instance with ID #{identifier}" }
        matched = Constants::Networkinterface::ID_PATTERN.match(identifier)
        vm = pool_element(:virtual_machine, matched[:compute], :info)

        nic = nil
        vm.each("TEMPLATE/NIC[NIC_ID='#{matched[:nic]}']") { |vm_nic| nic = vm_nic }
        raise Errors::Backend::EntityNotFoundError, "NIC #{matched[:nic]} not found on #{vm['ID']}" unless nic

        networkinterface_from(nic, vm)
      end

      # @see `Entitylike`
      def create(instance)
        logger.debug { "#{self.class}: Creating instance from #{instance.inspect}" }
        vm = pool_element(:virtual_machine, instance.source_id, :info)
        nics = vm.count_xpath('TEMPLATE/NIC')

        client(Errors::Backend::EntityCreateError) { vm.nic_attach nic_from(instance, vm) }
        wait_for_attached_nic! vm, nics

        Constants::Networkinterface::ATTRIBUTES_CORE['occi.core.id'].call(
          [{ 'NIC_ID' => vm['TEMPLATE/NIC[last()]/NIC_ID'] }, vm]
        )
      end

      # @see `Entitylike`
      def delete(identifier)
        logger.debug { "#{self.class}: Deleting instance #{identifier}" }
        matched = Constants::Networkinterface::ID_PATTERN.match(identifier)
        vm = pool_element(:virtual_machine, matched[:compute])
        client(Errors::Backend::EntityActionError) { vm.nic_detach(matched[:nic].to_i) }
      end

      private

      # Converts a ONe NIC + virtual machine instance to a valid networkinterface instance.
      #
      # @param nic [Nokogiri::XMLElement] instance to transform
      # @param virtual_machine [OpenNebula::VirtualMachine] instance to transform
      # @return [Occi::Infrastructure::Networkinterface] transformed instance
      def networkinterface_from(nic, virtual_machine)
        networkinterface = instance_builder.get(self.class.entity_identifier)

        attach_mixins! nic, virtual_machine, networkinterface
        transfer_attributes!(
          [nic, virtual_machine], networkinterface,
          Constants::Networkinterface::TRANSFERABLE_ATTRIBUTES
        )
        # TODO: a better way to handle the following?
        fix_target! nic, networkinterface

        networkinterface
      end

      # Converts an OCCI networkinterface instance to a valid ONe virtual machine template NIC.
      #
      # @param storage [Occi::Infrastructure::Networkinterface] instance to transform
      # @param virtual_machine [OpenNebula::VirtualMachine] machine this interface will be attached to
      # @return [String] ONe template fragment
      def nic_from(networkinterface, virtual_machine)
        template_path = File.join(template_directory, 'compute_nic.erb')
        data = {
          instances: [networkinterface],
          security_groups: Constants::Securitygrouplink::ID_EXTRACTOR.call(virtual_machine).to_a
        }
        erb_render template_path, data
      end

      # :nodoc:
      def attach_mixins!(nic, virtual_machine, networkinterface)
        if nic['IP']
          networkinterface << find_by_identifier!(
            Occi::Infrastructure::Constants::IPNETWORKINTERFACE_MIXIN
          )
        end
        networkinterface << server_model.find_regions.first

        attach_optional_mixin!(
          networkinterface, virtual_machine['HISTORY_RECORDS/HISTORY[last()]/CID'],
          :availability_zone
        )

        logger.debug do
          "#{self.class}: Attached mixins #{networkinterface.mixins.inspect} to networkinterface##{networkinterface.id}"
        end
      end

      # :nodoc:
      def fix_target!(nic, networkinterface)
        tk = if ipreservation?(nic['NETWORK_ID'])
               networkinterface.target = URI.parse("/ipreservation/#{nic['NETWORK_ID']}")
               Occi::InfrastructureExt::Constants::IPRESERVATION_KIND
             else
               Occi::Infrastructure::Constants::NETWORK_KIND
             end

        logger.debug { "#{self.class}: Setting target kind on networkinterface##{networkinterface.id} to #{tk}" }
        networkinterface.target_kind = find_by_identifier!(tk)
      end

      # :nodoc:
      def ipreservation?(identifier)
        backend_proxy.ipreservation.identifiers.include?(identifier)
      end

      # :nodoc:
      def wait_for_attached_nic!(vm, nics)
        refresher = ->(obj) { client(Errors::Backend::EntityRetrievalError) { obj.info } }
        waiter = Backends::Opennebula::Helpers::Waiter.new(waitee: vm, logger: logger, refresher: refresher)
        states = [
          { state_str: 'ACTIVE', lcm_state_str: 'RUNNING' }, { state_str: 'POWEROFF' }
        ]

        waiter.wait_until(states) do |nvm|
          unless nvm.count_xpath('TEMPLATE/NIC') > nics
            logger.error { "Attaching VNET to VM[#{vm['ID']}] failed: #{vm['USER_TEMPLATE/ERROR']}" }
            raise Errors::Backend::RemoteError, 'Could not attach network to compute'
          end
        end
      end

      # :nodoc:
      def whereami
        __dir__
      end
    end
  end
end
