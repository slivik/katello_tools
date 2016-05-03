desc <<-END_DESC
Task for finishing provisioning of VM (v1.2) - Example: foreman-rake 'prov_vm:prov_iface["example.wn.intranet","timestamp", "action"]'
END_DESC

namespace :prov_vm do

  task :prov_iface, [:hostname, :timestamp, :action] => :environment do |_, args|
    @ttimestamp = args[:timestamp]
    tlog "Task prov_vm:prov_iface #{args}"

    ## count of prov_iface task runs
    ## iface addition invokes several actions that hooks this script so not every run should do something
    ## we need to know how many runs were there before we close the add action as sucessful
    ## three factors plays a role in this
    ##   - @host.params['kt_prov_iface_flag']
    ##   - @host.params['kt_prov_iface_run']
    ##   - whether primary iface has provisioning feature or not (if there are two separate interfaces)
    ## two runs - Cancel Build (remove action) and setBuild (add action)
    @t_number_of_runs = 3

    ## get object for specified foreman host
    @host = Host::Managed.find_by_name(args[:hostname])
    @action = args[:action]
    tlog "Action: #{@action}, kt_prov_iface_flag: #{@host.params['kt_prov_iface_flag']}"

    ## continue only if host is associated with VM !!!
    (tlog "Cannot proceed Task. Host is not associated with VM or is not a VM."; next) unless ( @host.compute_resource_id && @host.uuid )

    prov_save_host_param("kt_prov_iface_run", @host.params['kt_prov_iface_run'] ? @host.params['kt_prov_iface_run'].to_i + 1 : 1 )
    (tlog "Rebuilding host - skipping all actions."; next) if @host.params['kt_prov_iface_flag'] == 'rebuild'

    ## get object for VM associated with foreman host (nil if it is not associated or it is a HW)
    @vm = @host.compute_resource.find_vm_by_uuid(@host.uuid)
    (tlog "VM not found."; next) if @vm.nil?


    case @action
      when "remove"
        (tlog "Cannot remove provisioning interface. Provisioning feature is bound to primary interface." ;next) if @host.interfaces.primary.first.provision?

        next unless prov_wait_for_host_build
        next unless prov_wait_for_power_off
        next unless prov_remove_prov_iface
        prov_save_host_param("kt_prov_iface_flag", "removed")
        prov_save_host_param("kt_prov_iface_run", 0)
        prov_power_vm(:on)
        tlog "Sucessfuly finished."

      when "add"
        (tlog "Host has already separated prov iface. Will not add another one."; next) unless @host.interfaces.primary.first.provision?

        prov_power_vm(:off)
        next unless prov_wait_for_power_off
        next unless prov_save_host_param("kt_prov_iface_flag", "rebuild")

        tlog "Trying to call CancelBuild on host. Build fo host will be called automatically after that again."
        (tlog "CancelBuild was not sucessful."; next) unless @host.built

        next unless prov_add_prov_iface

        tlog "Trying to call Build again and waiting for required number of runs."
        ## @host.reload does not work
        @host = Host::Managed.find_by_name(args[:hostname])
        (tlog "Build was not sucessful."; next) unless @host.setBuild

        next unless prov_wait_for_prov_runs
        prov_save_host_param("kt_prov_iface_flag", "added")
        prov_save_host_param("kt_prov_iface_run", 0)
        tlog "Sucessfuly finished."

      else
        tlog "Undefined action, skipping: #{@action}."
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
        prov_save_host_param("kt_prov_iface_params", @host.interfaces.find { |nic| nic.provision? }.to_json.to_s)
        @host.interfaces.find { |nic| nic.provision? }.provision = false
        @host.interfaces.find { |nic| nic.primary? }.provision = true
        @host.interfaces.find { |nic| nic.mac == prov_if.mac }.destroy
        tlog "Trying to update Foreman host."
        (tlog "Unable to save Foreman host."; return false) unless @host.save
        tlog "Foreman host sucessfuly updated."
        return true
      else
        tlog "Removing provisioning interface from VM failed."
        return false
      end
    else
      tlog "Cannot remove provisionig interface because either there is no dedicated prov iface or host is not associated with VM."
      return false
    end
  end

  def prov_add_prov_iface
    tlog "Trying to add provisioning interface to the VM."

    ifparams = @host.params['kt_prov_iface_params'] ? JSON.parse(@host.params['kt_prov_iface_params']).to_hash['managed'] : nil?
    (tlog "Cannot add prov iface because no NIC parameters available in host.params['kt_prov_iface_params']."; return false) if ifparams.nil?

    vm_iface_mac = @vm.interfaces.create({ :network => ifparams['compute_attributes']['network'], :type => ifparams['compute_attributes']['type'] }).mac
    (tlog "Unable to create new virtual iface on VM."; return false) if vm_iface_mac.nil?

    ni = @host.interfaces.new
    ni.type = 'Nic::Managed'
    ni.provision = false
    ni.primary = false
    ni.managed = true
    ni.subnet_id = ifparams['subnet_id']
    ni.domain_id = ifparams['domain_id']
    ni.identifier = ifparams['identifier']
    ni.compute_attributes[:type] = ifparams['compute_attributes']['type']
    ni.compute_attributes[:network] = ifparams['compute_attributes']['network']
    ni.mac = vm_iface_mac
    (tlog "Unable to create interface in Foreman host."; return false) unless ni.save

    @host.interfaces.find { |nic| nic.provision? }.provision = false
    @host.interfaces.find { |nic| nic.mac == vm_iface_mac }.provision = true

    ip = ni.subnet.unused_ip
    (tlog "Unable to find free IP for prov iface."; return false) if ip.nil?
    @host.interfaces.find { |nic| nic.mac == vm_iface_mac }.ip = ip

    tlog "Trying to update Foreman host."
    (tlog "Unable to save Foreman host."; return false) unless @host.save
    return true
  end

  def tlog(message)
    puts "[#{@host.respond_to?(:name) ? @host.name : 'NA'}, #{@ttimestamp}, #{@action}, #{Time.zone.now.strftime("%Y-%d-%m %H:%M:%S %Z")}]: #{message}"
  end

  ## TODO: create reasonable universal method wait_for_...
  def prov_wait_for_prov_runs(timeout=900, interval=10)
    i = 0
    num_runs = @host.params['kt_prov_iface_run'].to_i
    tlog "Current value of kt_prov_iface_run is #{num_runs}..."
    while num_runs < @t_number_of_runs.to_i
      i += 1
      sleep(interval)
      ## @host.reload does not work
      thost = Host::Managed.find_by_name(@host.name)
      num_runs = thost.params['kt_prov_iface_run'].to_i
      tlog "Waiting for required number of runs for #{i * interval}/#{timeout} seconds."
      if (i * interval) >= timeout
        tlog "Required number of prof_iface tasks has not run in time. Timeout (#{timeout} seconds) reached."
        return false
      end
    end
    tlog "Required number of prof_iface tasks has run. Continue."
    return true
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

  def prov_wait_for_power_off(timeout=3600, interval=10)
    i = 0
    while @vm.power_state.sub('powered', '').downcase == "on"
      i += 1
      sleep(interval)
      @vm.reload
      tlog "Waiting for host #{@host.name} to be powered off for #{i * interval}/#{timeout} seconds."
      if (i * interval) >= timeout
        tlog "Host #{@host.name} have not been powered off in time. Timeout (#{timeout} seconds) reached."
        return false
      end
    end
    tlog "Host is powered off. Continue."
    return true
  end

  def prov_power_vm(state)
    @vm.reload
    current_state = @vm.power_state.sub('powered', '').downcase
    if current_state != state.to_s
      tlog "Powering #{state} host #{@host.name}."
      @host.power.send(state.to_sym)
    else
      tlog "Host is already powered #{state}."
    end
  end

  def prov_save_host_param(key,val)
    tlog "Updating host parameter #{key} with value of #{val}"
    hp = @host.parameters.find { |p| p.name == key }
    if hp.nil?
      hp = @host.parameters.new
      hp.name = key
    end
    hp.value = val.is_a?(String) ? val : val.to_s
    (tlog "Unable to update host parameter #{key}"; return false) unless hp.save
    tlog "Parameter #{key} updated."
    return true
  end

end
