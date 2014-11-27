require 'spec_helper'
require 'yaml'

describe Backends::Ec2Backend do
  let(:dalli) { Dalli::Client.new }
  let(:aws_creds) { ::Aws::Credentials.new('a', 'b') }
  let(:ec2_dummy_client) { ::Aws::EC2::Client.new(credentials: aws_creds, stub_responses: true) }
  let(:instance_statuses_stub) { YAML.load_file("#{Rails.root}/spec/lib/backends/ec2_stubs/instance_statuses_stub.yml") }
  let(:reservations_stub) { YAML.load_file("#{Rails.root}/spec/lib/backends/ec2_stubs/reservations_stub.yml") }
  let(:reservation_stub) { YAML.load_file("#{Rails.root}/spec/lib/backends/ec2_stubs/reservation_stub.yml") }
  let(:volumes_stub) { YAML.load_file("#{Rails.root}/spec/lib/backends/ec2_stubs/volumes_stub.yml") }
  let(:vpcs_stub) { YAML.load_file("#{Rails.root}/spec/lib/backends/ec2_stubs/vpcs_stub.yml") }
  let(:vpc_stub) { YAML.load_file("#{Rails.root}/spec/lib/backends/ec2_stubs/vpc_stub.yml") }
  let(:subnet_stub) { YAML.load_file("#{Rails.root}/spec/lib/backends/ec2_stubs/subnet_stub.yml") }
  let(:empty_struct_stub) { YAML.load_file("#{Rails.root}/spec/lib/backends/ec2_stubs/empty_struct_stub.yml") }
  let(:internet_gateway_stub) { YAML.load_file("#{Rails.root}/spec/lib/backends/ec2_stubs/internet_gateway_stub.yml") }
  let(:terminating_instances_stub) { YAML.load_file("#{Rails.root}/spec/lib/backends/ec2_stubs/terminating_instances_stub.yml") }
  let(:terminating_instances_single_stub) { YAML.load_file("#{Rails.root}/spec/lib/backends/ec2_stubs/terminating_instances_single_stub.yml") }
  let(:ec2_backend_instance) do
    instance = Backends::Ec2Backend.new nil, nil, nil, nil, dalli
    instance.instance_variable_set(:@ec2_client, ec2_dummy_client)

    instance
  end
  let(:default_options) { ec2_backend_instance.instance_variable_get(:@options) }

  before(:each) { dalli.flush }
  after(:all) { Dalli::Client.new.flush }

  context 'compute' do
    describe 'compute_list_ids' do
      it 'runs with empty list' do
        expect(ec2_backend_instance.compute_list_ids).to eq([])
      end

      it 'Receives compute instance list correctly' do
        ec2_dummy_client.stub_responses(:describe_instance_status, instance_statuses:instance_statuses_stub)
        expect(ec2_backend_instance.compute_list_ids).to eq(["ID", "ID2"])
      end
    end

    describe '.compute_list' do
      it 'runs with empty list' do
        expect(ec2_backend_instance.compute_list).to eq([])
      end

      it 'Receives compute instance list correctly with nil storage description' #do
#        ec2_dummy_client.stub_responses(:describe_instances, reservations_stub)
#        expect(ec2_backend_instance.compute_list).to eq(["ID", "ID2"])
#      end

      it 'Receives compute instance list correctly' do
        ec2_dummy_client.stub_responses(:describe_instances, reservations_stub)
        ec2_dummy_client.stub_responses(:describe_volumes, volumes_stub)
        ec2_dummy_client.stub_responses(:describe_vpcs, vpcs_stub)
        returned = ""
        ec2_backend_instance.compute_list.each { |resource| returned = "#{returned}#{resource.to_text}\n" }

        expected = File.open("spec/lib/backends/ec2_samples/compute_list.expected","rt").read
        
        expect(returned).to eq expected
      end
    end

    describe '.compute_get' do
      it 'copes with non-existent id' do
        expect(ec2_backend_instance.compute_get("someID")).to eq nil
      end

      it 'gets compute instance description correctly' do
        ec2_dummy_client.stub_responses(:describe_instances, reservations_stub)
        ec2_dummy_client.stub_responses(:describe_volumes, volumes_stub)
        ec2_dummy_client.stub_responses(:describe_vpcs, vpcs_stub)
        returned = ec2_backend_instance.compute_get("i-22af91c7").to_text
        F = File.open("spec/lib/backends/ec2_samples/compute_list_single_instance.expected","wt")
        F.write(returned)
        F.close
        expected = File.open("spec/lib/backends/ec2_samples/compute_list_single_instance.expected","rt").read
        expect(returned).to eq expected
      end
    end

    describe '.compute_create' do
      it 'reports correctly on missing os_tpl mixin' do
        compute = Occi::Infrastructure::Compute.new
        expect{ec2_backend_instance.compute_create(compute)}.to raise_exception(Backends::Errors::ResourceNotValidError)
      end

      it 'creates compute resource correctyly' do
        ec2_dummy_client.stub_responses(:run_instances, reservation_stub)

        ostemplate = Occi::Core::Mixin.new("http://occi.localhost/occi/infrastructure/os_tpl#", "ami-6e7bd919")
        ostemplate.depends=[Occi::Infrastructure::OsTpl.mixin]
        restemplate = Occi::Core::Mixin.new("http://schemas.ec2.aws.amazon.com/occi/infrastructure/resource_tpl#", "t2_micro")
        restemplate.depends=[Occi::Infrastructure::ResourceTpl.mixin]
        compute = Occi::Infrastructure::Compute.new
        compute.mixins << ostemplate
        compute.mixins << restemplate
        expect(ec2_backend_instance.compute_create(compute)).to eq "i-5a8cb7bf"
      end
    end


    describe '.compute_delete_all' do
      it 'deletes all instances' do
        ec2_dummy_client.stub_responses(:terminate_instances, terminating_instances_stub)
        ec2_dummy_client.stub_responses(:describe_instance_status, instance_statuses:instance_statuses_stub)
        expect(ec2_backend_instance.compute_delete_all()).to be true
      end
    end


    describe '.compute_delete' do
      it 'deletes the given instance' do
        ec2_dummy_client.stub_responses(:terminate_instances, terminating_instances_single_stub)
        ec2_dummy_client.stub_responses(:describe_instance_status, instance_statuses:instance_statuses_stub)
        expect(ec2_backend_instance.compute_delete("i-5a8cb7bf")).to be true
      end

      it 'copes with invalid ID' do
        ec2_dummy_client.stub_responses(:terminate_instances, Aws::EC2::Errors::InvalidInstanceIDMalformed)
        ec2_dummy_client.stub_responses(:describe_instance_status, instance_statuses:instance_statuses_stub)
        expect{ec2_backend_instance.compute_delete("xxxxxxxxxx")}.to raise_exception{Backends::Errors::IdentifierNotValidError}
      end
    end

  end


  context 'network' do

    after(:each) { ec2_backend_instance.instance_variable_set(:@options, default_options) }

    describe '.network_create' do
      it 'creates a network instance' do
        ec2_dummy_client.stub_responses(:create_vpc, vpc_stub)
        ec2_dummy_client.stub_responses(:create_subnet, subnet_stub)
        ec2_dummy_client.stub_responses(:create_tags, empty_struct_stub)
        ec2_dummy_client.stub_responses(:create_internet_gateway, internet_gateway_stub)
        ec2_dummy_client.stub_responses(:attach_internet_gateway, empty_struct_stub)

        network = Occi::Infrastructure::Network.new
        network.address='10.0.0.0/24'
        opts=ec2_backend_instance.instance_variable_get(:@options)
        opts.network_create_allowed=true
        ec2_backend_instance.instance_variable_set(:@options, opts)
        expect(ec2_backend_instance.network_create(network)).to eq "vpc-a08b44c5"
      end

      it 'refuses creation on missing permissions' do
        expect{ec2_backend_instance.network_create(Occi::Infrastructure::Network.new)}.to raise_exception(Backends::Errors::UserNotAuthorizedError)
      end

      it 'throws exception if address unspecified' do
        opts=ec2_backend_instance.instance_variable_get(:@options)
        opts.network_create_allowed=true
        ec2_backend_instance.instance_variable_set(:@options, opts)
        expect{ec2_backend_instance.network_create(Occi::Infrastructure::Network.new)}.to raise_exception(Backends::Errors::ResourceNotValidError)
      end
    end

    describe '.network_get' do
      it 'gets network detail' do
        ec2_dummy_client.stub_responses(:describe_vpcs, vpcs_stub)
        expected = File.open("spec/lib/backends/ec2_samples/network_get.expected","rt").read
        expect(ec2_backend_instance.network_get("vpc-7d884a18").to_text).to eq expected
      end
    end

    describe '.network_list_ids' do
      it 'lists network IDs' do
        ec2_dummy_client.stub_responses(:describe_vpcs, vpcs_stub)
        expect(ec2_backend_instance.network_list_ids()).to eq ["vpc-7d884a18", "public", "private"]
      end
    end
  end

end
