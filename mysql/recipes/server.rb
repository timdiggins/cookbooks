#
# Cookbook Name:: mysql
# Recipe:: default
#
# Copyright 2008-2009, Opscode, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe "mysql::client"

case node[:platform]
when "debian","ubuntu"
  def debian_cnf(key)
    `cat /etc/mysql/debian.cnf|grep #{key}|uniq`.split(' = ').last.chomp
  end

  def mysql(cmd)
    user = debian_cnf('user')
    password = debian_cnf('password')
    %(mysql --user=#{user} --password='#{password}' -e "#{cmd}")
  end

  execute "remove mysql root users" do
    command mysql("delete from mysql.user where user='root';FLUSH PRIVILEGES;")
    not_if { `#{mysql("select user from mysql.user where user='root';")} | wc -l`.chomp == "0" }
  end

  template "/etc/mysql/conf.d/character_set_collation.cnf" do
    source "character_set_collation.cnf.erb"
    variables(:character_set => 'utf8', :collation => 'utf8_general_ci')
    backup 0 #backups in conf.d would confuse mysql
    mode 0644
    owner "root"
    group "root"
    notifies :reload, resources(:service => "mysql")
  end

  template "/etc/mysql/conf.d/skip-networking" do
    owner "root"
    group "root"
    mode  0644
    source "skip-networking.cnf.erb"
    notifies :reload, resources(:service => "mysql")
    only_if { node[:mysql][:skip_networking] }
  end

  directory "/var/cache/local/preseeding" do
    owner "root"
    group "root"
    mode "755"
    recursive true
  end
  
  execute "preseed mysql-server" do
    command "debconf-set-selections /var/cache/local/preseeding/mysql-server.seed"
    action :nothing
  end

  template "/var/cache/local/preseeding/mysql-server.seed" do
    source "mysql-server.seed.erb"
    owner "root"
    group "root"
    mode "0600"
    notifies :run, resources(:execute => "preseed mysql-server"), :immediately
  end
end

package "mysql-server" do
  action :install
end

service "mysql" do
  service_name value_for_platform([ "centos", "redhat", "suse" ] => {"default" => "mysqld"}, "default" => "mysql")
  
  supports :status => true, :restart => true, :reload => true
  action :enable
end

template value_for_platform([ "centos", "redhat", "suse" ] => {"default" => "/etc/my.cnf"}, "default" => "/etc/mysql/my.cnf") do
  source "my.cnf.erb"
  owner "root"
  group "root"
  mode "0644"
  notifies :restart, resources(:service => "mysql"), :immediately
end

if (node[:ec2] && ! FileTest.directory?(node[:mysql][:ec2_path]))
  
  service "mysql" do
    action :stop
  end
  
  execute "install-mysql" do
    command "mv #{node[:mysql][:datadir]} #{node[:mysql][:ec2_path]}"
    not_if do FileTest.directory?(node[:mysql][:ec2_path]) end
  end
  
  link node[:mysql][:datadir] do
   to node[:mysql][:ec2_path]
  end
  
  service "mysql" do
    action :start
  end
  
end
