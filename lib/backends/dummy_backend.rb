module Backends
  class DummyBackend
    API_VERSION = '0.0.1'
    FIXTURES = [:compute, :network, :storage, :os_tpl, :resource_tpl].freeze

    def initialize(delegated_user, options, server_properties, logger, dalli_cache)
      @delegated_user = Hashie::Mash.new(delegated_user)
      @options = Hashie::Mash.new(options)
      @server_properties = Hashie::Mash.new(server_properties)
      @logger = logger || Rails.logger
      @dalli_cache = dalli_cache

      path = @options.fixtures_dir || ''
      read_fixtures(path)
    end

    def read_fixtures(base_path)
      @logger.debug "[Backends] [DummyBackend] Reading fixtures from #{base_path.to_s.inspect}"
      FIXTURES.each { |name| send "read_#{name.to_s}_fixtures", base_path }
    end

    def read_compute_fixtures(path = '')
      compute = Rails.env.test? ? @compute : @dalli_cache.get('dummy_compute')

      unless compute
        path = path_for_fixture_file(path, :compute)
        @logger.debug "[Backends] [DummyBackend] Reloading compute fixtures from #{path.inspect}"
        compute = File.readable?(path) ? read_from_json(path).resources : Occi::Core::Resources.new
        save_compute_fixtures(compute)
      end

      compute
    end

    def save_compute_fixtures(compute)
      Rails.env.test? ? @compute = compute : @dalli_cache.set('dummy_compute', compute)
    end

    def drop_compute_fixtures(lite = true)
      if lite
        save_compute_fixtures(Occi::Core::Resources.new)
      else
        Rails.env.test? ? @compute = nil : @dalli_cache.delete('dummy_compute')
      end
    end

    def read_network_fixtures(path = '')
      network = Rails.env.test? ? @network : @dalli_cache.get('dummy_network')

      unless network
        path = path_for_fixture_file(path, :network)
        @logger.debug "[Backends] [DummyBackend] Reloading network fixtures from #{path.inspect}"
        network = File.readable?(path) ? read_from_json(path).resources : Occi::Core::Resources.new
        save_network_fixtures(network)
      end

      network
    end

    def save_network_fixtures(network)
      Rails.env.test? ? @network = network : @dalli_cache.set('dummy_network', network)
    end

    def drop_network_fixtures(lite = true)
      if lite
        save_network_fixtures(Occi::Core::Resources.new)
      else
        Rails.env.test? ? @network = nil : @dalli_cache.delete('dummy_network')
      end
    end

    def read_storage_fixtures(path = '')
      storage = Rails.env.test? ? @storage : @dalli_cache.get('dummy_storage')

      unless storage
        path = path_for_fixture_file(path, :storage)
        @logger.debug "[Backends] [DummyBackend] Reloading storage fixtures from #{path.inspect}"
        storage = File.readable?(path) ? read_from_json(path).resources : Occi::Core::Resources.new
        save_storage_fixtures(storage)
      end

      storage
    end

    def save_storage_fixtures(storage)
      Rails.env.test? ? @storage = storage : @dalli_cache.set('dummy_storage', storage)
    end

    def drop_storage_fixtures(lite = true)
      if lite
        save_storage_fixtures(Occi::Core::Resources.new)
      else
        Rails.env.test? ? @storage = nil : @dalli_cache.delete('dummy_storage')
      end
    end

    def read_os_tpl_fixtures(path = '')
      os_tpl = Rails.env.test? ? @os_tpl : @dalli_cache.get('dummy_os_tpl')

      unless os_tpl
        path = path_for_fixture_file(path, :os_tpl)
        @logger.debug "[Backends] [DummyBackend] Reloading os_tpl fixtures from #{path.inspect}"
        os_tpl = File.readable?(path) ? read_from_json(path).mixins : Occi::Core::Mixins.new
        save_os_tpl_fixtures(os_tpl)
      end

      os_tpl
    end

    def save_os_tpl_fixtures(os_tpl)
      Rails.env.test? ? @os_tpl = os_tpl : @dalli_cache.set('dummy_os_tpl', os_tpl)
    end

    def read_resource_tpl_fixtures(path = '')
      resource_tpl = Rails.env.test? ? @resource_tpl : @dalli_cache.get('dummy_resource_tpl')

      unless resource_tpl
        path = path_for_fixture_file(path, :resource_tpl)
        @logger.debug "[Backends] [DummyBackend] Reloading resource_tpl fixtures from #{path.inspect}"
        resource_tpl = File.readable?(path) ? read_from_json(path).mixins : Occi::Core::Mixins.new
        save_resource_tpl_fixtures(resource_tpl)
      end

      resource_tpl
    end

    def save_resource_tpl_fixtures(resource_tpl)
      Rails.env.test? ? @resource_tpl = resource_tpl : @dalli_cache.set('dummy_resource_tpl', resource_tpl)
    end

    def path_for_fixture_file(path, fixture_type)
      return path if path && path.to_s.end_with?('.json')
      path = @options.fixtures_dir if path.blank?

      fail Backends::Errors::ResourceRetrievalError, "Unable to read fixtures " \
           "from an unspecified directory!" if path.blank?
      fail Backends::Errors::ResourceRetrievalError, "Unable to read fixtures " \
           "for #{fixture_type.to_s.inspect}!" unless FIXTURES.include? fixture_type

      File.join(path, "#{fixture_type.to_s}.json")
    end

    # load helpers for JSON -> Collection conversion
    include Backends::Helpers::JsonCollectionHelper

    # hide internal stuff
    private :read_fixtures
    private :read_storage_fixtures
    private :read_network_fixtures
    private :read_compute_fixtures
    private :read_os_tpl_fixtures
    private :read_resource_tpl_fixtures
    private :save_storage_fixtures
    private :save_network_fixtures
    private :save_compute_fixtures
    private :save_os_tpl_fixtures
    private :save_resource_tpl_fixtures
    private :drop_storage_fixtures
    private :drop_network_fixtures
    private :drop_compute_fixtures
    private :read_from_json
    private :path_for_fixture_file

    # load API implementation
    include Backends::Dummy::Compute
    include Backends::Dummy::Network
    include Backends::Dummy::Storage
    include Backends::Dummy::OsTpl
    include Backends::Dummy::ResourceTpl
  end
end
