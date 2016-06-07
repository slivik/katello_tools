<%#
kind: snippet
name: /etc/mcollective/facts_cron.yaml
desc: Part of Puppet & MCollective setup (KS_WN_puppet_mco_setup)
oses:
    - CentOS 6
    - CentOS 7
    - RHEL 6
    - RHEL 7
    - SLES 11 SP 3
%>#!/usr/bin/env ruby
require 'rubygems'
require 'facter'
require 'yaml'
rejected_facts = ["sshdsakey", "sshrsakey"]
custom_facts_location = "/var/lib/puppet/facts"
outputfile = "/etc/mcollective/facts_cron.yaml"

Facter.search(custom_facts_location)
facts = Facter.to_hash.reject { |k,v| rejected_facts.include? k }
File.open(outputfile, "w") { |fh| fh.write(facts.to_yaml) }
