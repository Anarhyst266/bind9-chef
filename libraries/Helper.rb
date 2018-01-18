module Mybind
  module Helper
    include Chef::Mixin::ShellOut

    def update_needed?(domain)
      shell_out!("cp /etc/bind/zones/#{domain} /tmp/tmp_#{domain}&& sed -i '/Serial/d' /tmp/tmp_#{domain} && cp /tmp/#{domain} /tmp/tmp2_#{domain}&& sed -i '/Serial/d' /tmp/tmp2_#{domain}", returns: [0, 1, 2])
      cmd = shell_out!("diff -q /tmp/tmp_#{domain} /tmp/tmp2_#{domain}", returns: [0, 1])
      shell_out!("rm -f /tmp/tmp_#{domain} && rm -f /tmp/tmp2_#{domain}", returns: [0, 1])
      cmd.stderr.empty? && (cmd.stdout =~ /differ/)
    end

    def get_serial(domain)
      cmd = shell_out!("grep Serial /etc/bind/zones/#{domain}|awk -F ';' {'print $1'}|awk '{print $1}'", returns: [0, 1])
      cmd.stdout
    end
  end
end
