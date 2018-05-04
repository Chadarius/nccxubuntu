# -*- mode: ruby -*-
# vi: set ft=ruby :
Vagrant.configure("2") do |config|
  config.vm.box = "bstoots/xubuntu-16.04-desktop-amd64"
  config.vm.provider "virtualbox" do |v|
    v.name = "NCC Xubuntu 16.04 LTS"
    v.customize ["modifyvm", :id, "--memory", "4096"]
  end
  config.vm.provision "shell" do |s|
    s.path "src/nccxubuntu.sh"
  end
end