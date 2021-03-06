
module PacketThief
module Impl
  # PacketThief implemented using the Linux kernel's Netfilter.
  #
  # This is roughly equivalent to:
  #
  # echo 1 > /proc/sys/net/ipv4/ip_forward
  # iptables -t nat -A PREROUTING -p tcp --destination-port <DEST> -j REDIRECT --to-ports <LISTENER>
  #
  # Currently only implements IPv4.
  #
  # Note that the listening socket must have a blank hostname. If it is set to
  # 127.0.0.1, then the socket will only run on the loopback device, and
  # traffic that gets redirected from another device won't reach it.
  class Netfilter

    # Manages IPTablesRules. It actually runs the rule, and it tracks the rule
    # so it can be deleted later.
    module IPTablesRuleHandler
      attr_accessor :active_rules

      # Executes a rule and holds onto it for later removal.
      def run(rule)
        @active_rules ||= []

        args = ['/sbin/iptables', '-t', rule.table, '-A', rule.chain]

        args.concat rule.to_netfilter_command

        unless system(*args)
          raise "Command #{args.inspect} exited with error code #{$?.inspect}"
        end

        @active_rules << rule
      end

      # Reverts all executed rules that this handler knows about.
      def revert
        return if @active_rules == nil or @active_rules.empty?

        @active_rules.each do |rule|
          args = ['/sbin/iptables', '-t', rule.table, '-D', rule.chain]
          args.concat rule.to_netfilter_command

          unless system(*args)
            raise "Command #{args.inspect} exited with error code #{$?.inspect}"
          end
        end

        @active_rules = []
      end
    end
    extend IPTablesRuleHandler

    # Adds IPTables specific details to a Redirectrule.
    class IPTablesRule < RedirectRule

      attr_accessor :table
      attr_accessor :chain

      def initialize(handler, table, chain)
        super(handler)
        @table = table
        @chain = chain
      end

      def to_netfilter_command
        args = []

        if self.rulespec
          args << '-p' << self.rulespec[:protocol].to_s if self.rulespec.has_key? :protocol
          args << '--destination-port' << self.rulespec[:dest_port].to_s if self.rulespec.has_key? :dest_port
          args << '--in-interface' << self.rulespec[:in_interface].to_s if self.rulespec.has_key? :in_interface
        end

        if self.redirectspec
          args << '-j' << 'REDIRECT'
          args << '--to-ports' << self.redirectspec[:to_ports].to_s if self.redirectspec.has_key? :to_ports
        end

        args
      end

    end

    def self.redirect(args={})
      rule = IPTablesRule.new(self,'nat','PREROUTING')
      rule.redirect(args)
    end

    #/usr/include/linux/netfilter_ipv4.h:#define SO_ORIGINAL_DST 80
    SO_ORIGINAL_DST = 80

    # Returns the [port, host] for a socket or EM::Connection that whose
    # connection was redirected by netfilter
    def self.original_dest(socket)
      if socket.respond_to? :getsockopt
        sockname = socket.getsockopt(Socket::IPPROTO_IP, SO_ORIGINAL_DST)
      elsif socket.respond_to? :get_sock_opt
        sockname = socket.get_sock_opt(Socket::IPPROTO_IP, SO_ORIGINAL_DST)
      end
        Socket::unpack_sockaddr_in(sockname)
    end

  end

end
end
