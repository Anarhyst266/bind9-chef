package 'bind9' do
  case node[:platform]
  when 'centos', 'redhat', 'suse', 'fedora'
    package_name 'bind'
  when 'debian', 'ubuntu'
    package_name 'bind9'
  end
  action :install
end

case node[:platform]
when 'centos', 'redhat', 'suse', 'fedora'
  s_name = 'named'
when 'debian', 'ubuntu'
  s_name = 'bind9'
end

zones = begin
  search(:dns_zones)
rescue Net::HTTPServerException, Chef::Exceptions::InvalidDataBagPath
  nil
end

if zones
  template '/etc/bind/named.conf.options' do
    source 'named.conf.options.erb'
    owner 'root'
    group 'root'
    mode 0644
    notifies :run, 'execute[named-checkconf]', :immediately
    notifies :run, 'execute[failsafe-checkconf]', :immediately
  end

  if node.role?('bind-master')
    slaves = search(:node, 'role:bind-slave')
    template '/etc/bind/named.conf.local' do
      source 'named.conf.local.master.erb'
      owner 'root'
      group 'root'
      mode 0644
      notifies :run, 'execute[named-checkconf]', :delayed
      notifies :run, 'execute[failsafe-checkconf]', :delayed
      variables(zonefiles: zones,
                slaves: slaves)
    end
    directory '/etc/bind/zones' do
      owner 'root'
      group 'root'
      mode '0755'
      action :create
    end
  elsif node.role?('bind-slave')
    master = search(:node, 'role:bind-master')
    template '/etc/bind/named.conf.local' do
      source 'named.conf.local.slave.erb'
      owner 'root'
      group 'root'
      mode 0644
      notifies :run, 'execute[named-checkconf]', :delayed
      notifies :run, 'execute[failsafe-checkconf]', :delayed
      variables(zonefiles: zones,
                master: master)
    end
  end

  if node.role?('bind-master')
    zones.each do |zone|
      Chef::Resource.send(:include, Mybind::Helper)
      node.default[zone['domain']]['serial'] = 0
      template '/tmp/' + zone['domain'] do
        source 'zonefile.erb'
        owner 'root'
        group 'root'
        mode 0644
        variables(domain: zone['domain'],
                  soa: zone['zone_info']['soa'],
                  contact: zone['zone_info']['contact'],
                  serial: 0,
                  global_ttl: zone['zone_info']['global_ttl'],
                  nameserver: zone['zone_info']['nameserver'],
                  mail_exchange: zone['zone_info']['mail_exchange'],
                  records: zone['zone_info']['records'])
      end
      template '/etc/bind/zones/' + zone['domain'] do
        source 'zonefile.erb'
        owner 'root'
        group 'root'
        mode 0644
        notifies :run, 'execute[named-checkconf]', :delayed
        notifies :run, 'execute[failsafe-checkconf]', :delayed
        variables(domain: zone['domain'],
                  soa: zone['zone_info']['soa'],
                  contact: zone['zone_info']['contact'],
                  serial: (get_serial(zone['domain']).to_i + 1).to_s,
                  global_ttl: zone['zone_info']['global_ttl'],
                  nameserver: zone['zone_info']['nameserver'],
                  mail_exchange: zone['zone_info']['mail_exchange'],
                  records: zone['zone_info']['records'])
        only_if { update_needed?(zone['domain']) }
      end
    end
  end
end

directory '/var/log/bind' do
  owner 'root'
  group 'root'
  mode '0755'
  action :create
end

file '/var/log/bind/bind.log' do
  owner 'root'
  group 'root'
  mode '0777'
  action :create_if_missing
end

execute 'named-checkconf' do
  command '/usr/sbin/named-checkconf -z /etc/bind/named.conf'
  action :nothing
  notifies :enable, 'service[bind]', :immediately
  notifies :start, 'service[bind]', :immediately
  only_if { ::File.exist?('/usr/sbin/named-checkconf') }
end

execute 'failsafe-checkconf' do
  command 'true'
  action :nothing
  notifies :enable, 'service[bind]', :immediately
  notifies :start, 'service[bind]', :immediately
  not_if { ::File.exist?('/usr/sbin/named-checkconf') }
end

service 'bind' do
  service_name s_name
  supports reload: true, status: true
  action :nothing
  subscribes :reload, resources('template[/etc/bind/named.conf.local]'), :delayed
  subscribes :reload, resources('execute[named-checkconf]', 'execute[failsafe-checkconf]'), :delayed
  only_if { ::File.exist?('/etc/bind/named.conf.local') && ::File.exist?('/etc/bind/named.conf.options') }
end
