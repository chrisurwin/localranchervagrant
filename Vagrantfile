# -*- mode: ruby -*-
# vi: set ft=ruby :
require_relative 'vagrant_rancheros_guest_plugin.rb'
require 'ipaddr'
require 'yaml'

x = YAML.load_file('config.yaml')
puts "Config: #{x.inspect}\n\n"

# Local Catalog Configuration
$local_catalog_repo_dir = "/Users/joliver/Workspace/llparse"
$catalog_json = '{"catalogs":{"community":{"url":"http://172.22.101.100:4000/community-catalog","branch":"master"},"library":{"url":"http://172.22.101.100:4000/rancher-catalog","branch":"master"}}}'

$private_nic_type = x.fetch('net').fetch('private_nic_type')

Vagrant.configure(2) do |config|

  config.vm.define "master" do |master|
    c = x.fetch('master')
    master.vm.box = "williamyeh/ubuntu-trusty64-docker"
    master.vm.guest = :ubuntu
    master.vm.network :private_network, ip: x.fetch('ip').fetch('master'), nic_type: $private_nic_type    
    master.vm.provider :virtualbox do |v|
      v.cpus = c.fetch('cpus')
      v.memory = c.fetch('memory')
      v.name = "master"
    end
    master.vm.provision "shell", path: "scripts/master.sh"
    if x.fetch('catalog').fetch('enabled') == "true"
      master.vm.synced_folder x.fetch('catalog').fetch('host_repo_dirs'), "/var/git"
    end
  end

  server_ip = IPAddr.new(x.fetch('ip').fetch('server'))
  (1..x.fetch('server').fetch('count')).each do |i|
    c = x.fetch('server')
    hostname = "server-%02d" % i
    config.vm.define hostname do |server|
      server.vm.box= "MatthewHartstonge/RancherOS"
      server.vm.guest = :linux
      server.vm.provider :virtualbox do |v|
        v.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
        v.cpus = c.fetch('cpus')
        v.memory = c.fetch('memory')
        v.name = hostname
      end
      server.vm.network :private_network, ip: IPAddr.new(server_ip.to_i + i - 1, Socket::AF_INET).to_s, nic_type: $private_nic_type
      server.vm.hostname = hostname
      server.vm.provision "shell", path: "scripts/configure_rancher_server.sh", args: [x.fetch('ip').fetch('master'), x.fetch('orchestrator'), i, x.fetch('version'), x.fetch('catalog').fetch('json')]
    end
  end

  node_ip = IPAddr.new(x.fetch('ip').fetch('node'))
  (1..x.fetch('node').fetch('count')).each do |i|
    c = x.fetch('node')
    hostname = "node-%02d" % i
    config.vm.define hostname do |node|
      node.vm.box   = "MatthewHartstonge/RancherOS"
      node.vm.guest = :linux
      node.vm.provider "virtualbox" do |v|
        v.cpus = c.fetch('cpus')
        v.memory = c.fetch('memory')
        v.name = hostname
      end
      node.vm.network :private_network, ip: IPAddr.new(node_ip.to_i + i - 1, Socket::AF_INET).to_s, nic_type: $private_nic_type
      node.vm.hostname = hostname
      node.vm.provision "shell", path: "scripts/configure_rancher_node.sh", args: [x.fetch('ip').fetch('master'), x.fetch('orchestrator')]
    end
  end

end
