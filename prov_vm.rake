desc <<-END_DESC
Task for finishing provisioning of VM - Example: foreman-rake 'prov_vm:prov_iface["test.prg.local","timestamp"]'
END_DESC

namespace :prov_vm do

  task :prov_iface, [:hostname, :timestamp] => :environment do |_, args|
    @ttimestamp = args[:timestamp]
    tlog "Task prov_vm:prov_iface #{args}"

    ## get object for specified foreman host
    @host = Host::Managed.find_by_name(args[:hostname])
    action = @host.params['kt_prov_iface_action']
    tlog "Action: #{action}"

    ## continue if host is associated with VM !!!
    applicable = @host.compute_resource_id && @host.uuid

    unless applicable
      tlog "Cannot proceed Task. Host is not associated with VM or is not a VM."
      next
    end

    ## get object for VM associated with foreman host (nil if it is not associated or it is a HW)
    @vm = @host.compute_resource.find_vm_by_uuid(@host.uuid)

    if @vm.nil?
      tlog "VM not found."
      next
    end

    case action
      when "remove"
        next unless prov_wait_for_host_build
        next unless prov_remove_prov_iface
        next unless prov_power_vm(:on)
        tlog "Sucessfuly finished."

      else
        tlog "Skipping this action: #{action}."
    end

  end


  def tlog(message)
    puts "[#{@host.respond_to?(:name) ? @host.name : 'NA'}, #{@ttimestamp}]: #{message}"
  end

  def prov_wait_for_host_build(timeout=3600, interval=10)
    i = 0
    while @host.build?
      i += 1
      sleep(interval)
      @host.reload
      tlog "Waiting for host #{@host.name} to be built for #{i * interval}/#{timeout} seconds."
      if (i * interval) >= timeout
        tlog "Host #{@host.name} have not been built in time. Timeout (#{timeout} seconds) reached."
        return false
      end
    end
    tlog "Host is built. Continue."
    return true
  end

  def prov_power_vm(state)
    ## if it is a VM then we power it on
    current_state = @vm.power_state.sub('powered', '').downcase
    if @host.compute_resource_id && @host.uuid
      if current_state != state
        tlog "Powering #{state} host #{@host.name}."
        @host.power.send(state.to_sym)
      else
        tlog "Host is already powered #{state}."
      end
    end
  end

  def prov_remove_prov_iface
    tlog "Trying to identify provisioning interface to be removed."

    ## get object for provisioning interface (nil if provisioining iface is not dedicated on separate nic)
    prov_if = @host.interfaces.find {|nic| nic.provision == true && nic.primary == false}

    ## remove this separated provisioning NIC from VM and foreman iface from foreman host
    if !prov_if.nil? && @host.compute_resource_id && @host.uuid
      prov_nic = @vm.interfaces.find { |nic| nic.mac == prov_if.mac }
      tlog "Trying to remove provisioning interface with MAC #{prov_nic.mac} (nic.key=#{prov_nic.key}) from VM."
      if @vm.interfaces.get(prov_nic.key).destroy["task_state"].to_s == "success"
        tlog "Removing provisioning interface with MAC #{prov_nic.mac} from Foreman host."
        @host.interfaces.find { |nic| nic.provision? }.provision = false
        @host.interfaces.find { |nic| nic.primary? }.provision = true
        @host.interfaces.find { |nic| nic.mac == prov_if.mac }.destroy
        tlog "Trying to update Foreman host."
        if @host.save
          tlog "Foreman host sucessfuly updated. Updating host parameter kt_prov_iface_action."
          @hp = @host.parameters.find {|p| p.name == "kt_prov_iface_action"}
          if @hp.nil?
            @hp = @host.parameters.new
            @hp.name = "kt_prov_iface_action"
          end
          @hp.value = "prov_iface_automatically_removed"
          return @hp.save
        else
          tlog "Unable to update Foreman host."
          return false
        end
      else
        tlog "Removing provisioning interface from VM failed."
        return false
      end
    else
      tlog "Cannot remove provisionig interface because either there is no dedicated prov iface or host is not associated with VM."
      return false
    end
  end

end
