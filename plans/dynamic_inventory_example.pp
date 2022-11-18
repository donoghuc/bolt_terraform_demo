plan bolt_terraform_demo::dynamic_inventory_example(){
  # Provision VMs
  run_plan('terraform::apply', dir => 'terraform')

  # Define a reference to look up (in this case it matches inventory.yaml)
  $terraform_vms_ref = {
    '_plugin' => 'terraform',
    'dir' => 'terraform',
    'resource_type' => 'google_compute_instance.terraform_instance',
    'target_mapping' => {
      'name' => 'name',
      'uri' => 'network_interface.0.network_ip'
    }
  }
  # Look up the data and create new targets
  $terraform_vm_targets = resolve_references($terraform_vms_ref).map |$target| {
    Target.new($target)
  }
  # Wait for newly create hosts to be available over SSH
  wait_until_available($terraform_vm_targets)

  # Run a command on the new targets
  $command_results = run_command('hostname -f', $terraform_vm_targets)
  out::message($command_results)

  # Destroy the newly provisoned hosts
  run_plan('terraform::destroy', dir => 'terraform')
}
