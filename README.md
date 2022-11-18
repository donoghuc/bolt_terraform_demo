## Metdata

This gist is a draft for re-vamping [the bolt and terraform blog](https://puppet.com/blog/cloud-provisioning-terraform-and-bolt/) this work is being tacked with [BOLT-1605](https://tickets.puppetlabs.com/browse/BOLT-1605). The main goals for the refactor are:

1. Update to incorporate the terraform plugin (inventory plugins and command wrapper)
2. Update to latest bolt best practices
3. Provide example of interacting with hosts provisioned AFTER inventory is resolved. 


# Cloud provisioning with Terraform and Bolt
[Terraform](https://developer.hashicorp.com/terraform/intro) is a cloud provisioning tool that's great at managing low-level infrastructure components such as compute instances, storage, and networking.

[Bolt](https://puppet.com/docs/bolt/latest/bolt.html) is an open source remote task runner that can run commands, scripts, and puppet code across your infrastructure with a few keystrokes. It's available with RBAC and more enterprise features in Puppet Enterprise. Bolt combines the declarative Puppet language model with familiar and convenient imperative code, making it easy to learn and effective for both one-off tasks and long-term configuration management.

I want to demonstrate how powerful using these tools together is, and how they each enable you to quickly get the cloud resources you need and provision them with minimal setup and code. We'll orchestrate the provisioning of a [Google Compute Engine VM instance](https://cloud.google.com/compute/docs/instances/) instance with Terraform and Bolt. 

Note: If you want to follow along or see a more complete example all my code is available on [github](https://github.com/donoghuc/bolt_terraform_demo).

### Bolt project setup

Start with initializing a bolt project, this can be accomplished with the `bolt project init` command. This will create a configuration file and an inventory file. 
```
(base) ➜  bolt_terraform_demo bolt project init
(base) ➜  bolt_terraform_demo ls
bolt-project.yaml inventory.yaml
```
Bolt comes with a `terraform` module that will contain all the module code needed for this example. 
```
(base) ➜  bolt_terraform_demo bolt task show | grep terraform
  terraform::apply                          Apply an HCL manifest
  terraform::destroy                        Destroy resources managed with Terraform
  terraform::initialize                     Initialize a Terraform project directory
  terraform::output                         JSON representation of Terraform outputs
```


### Terraform HCL manifests

I have created a very simple terraform manifest for this demo. The terraform code is stored in a dedicated `terraform` directory in my particular bolt project. This is where manifest code, variable refs and terraform state will be stored. 

The main terraform manifest `main.tf` contains the declaration of terraform resources to provision some VMs in GCP. 
```
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.40.0"
    }
  }
}

provider "google" {
  project = var.project
  region  = var.region
  zone    = var.zone
}

data "google_compute_subnetwork" "subnet" {
  name    = var.subnet
  region  = var.region
  project = var.subnet_project
}

locals {
  network = data.google_compute_subnetwork.subnet.network
  metadata = {
    "ssh-keys" = "${var.user}:${file(var.ssh_key)}"
  }
}

resource "google_compute_instance" "terraform_instance" {
  name         = "terraform-instance-${count.index}"
  count        = var.num_instances
  machine_type = "e2-micro"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  metadata = local.metadata

  network_interface {
    network            = local.network
    subnetwork         = var.subnet
    subnetwork_project = var.subnet_project
  }
}
```

The variables used to populate the manifest values are stored in `variables.tf`

```
variable "project" {
  description = "Name of GCP project"
  type        = string
  default     = "team-skeletor-scratchpad"
}

variable "region" {
  description = "GCP region that will be targeted for infrastructure deployment"
  type        = string
  default     = "us-west1"
}

variable "zone" {
  description = "GCP zone that will be targeted for infrastructure deployment"
  type        = string
  default     = "us-west1-b"
}

variable "user" {
  description = "User name associated with GCP"
  type        = string
  default     = "cas.donoghue"
}

variable "ssh_key" {
  description = "Public ssh key to access GCP VMs"
  type        = string
  default     = "/Users/cas.donoghue/.ssh/id_rsa-gcloud.pub"
}

variable "subnet" {
  description = "The subnet your project is on"
  type        = string
  default     = "team-skeletor-scratchpad"
}

variable "subnet_project" {
  description = "The name of the subnet project"
  type        = string
  default     = "itsysopsnetworking"
}

variable "num_instances" {
  description = "The number of VMs to provision"
  type        = number
  default     = 2
}
```

Once we have these files saved we can initialize the terraform project with `terraform init`

```
(base) ➜  bolt_terraform_demo cd terraform
(base) ➜  terraform terraform init

Initializing the backend...

Initializing provider plugins...
- Finding hashicorp/google versions matching "4.40.0"...
- Installing hashicorp/google v4.40.0...
- Installed hashicorp/google v4.40.0 (signed by HashiCorp)

Terraform has created a lock file .terraform.lock.hcl to record the provider
selections it made above. Include this file in your version control repository
so that Terraform can guarantee to make the same selections by default when
you run "terraform init" in the future.

Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.

If you ever set or change modules or backend configuration for Terraform,
rerun this command to reinitialize your working directory. If you forget, other
commands will detect it and remind you to do so if necessary.
```

### Use bolt to apply the terraform manifest

Now we are ready to use bolt to apply the terraform manifest using the `terraform::apply` plan:
```
(base) ➜  bolt_terraform_demo bolt plan run terraform::apply dir=terraform
```

Once we have provisioned new VMs we can use the terraform plugin to dynamically create bolt targets. The terraform module shipped with bolt contains [reference plugins](https://puppet.com/docs/bolt/latest/supported_plugins.html#reference-plugins) that support looking up information for terraform state to construct targets. 

In the terraform directory a new `terraform.tfstate` file has been created (as a result of running the `terraform::apply` plan). Some relevant snippets from the (rather large) `terraform.tfstate` file:
```
      "mode": "managed",
      "type": "google_compute_instance",
      "name": "terraform_instance",
      "provider": "provider[\"registry.terraform.io/hashicorp/google\"]",
      "instances": [...]
```
The relevant sections under the `instances` key are:
```
            "name": "terraform-instance-0",
            "network_interface": [
              {
                "network_ip": "10.253.20.66"
              }
            ],
```

Bolt manages target information in an `inventory.yaml` file. [inventory reference](https://puppet.com/docs/bolt/latest/inventory_files.html)

In order to connect to the newly provisioned nodes we organize them into a `group` called `terraform_vms`. For resolving the targets in this group we use the `terraform` reference plugin. The `dir` parameter is the path to the `terraform` directory where our `terraform.tfstate` is located (or if you are managing a remote tfstate, the information for collecting current state). The `resource_type` shows how we index into the relevant section of the `terraform.tfstate` (snippets above). In this case we are interested in the `terraform_instance` of the `google_compute_instance` resource. Within this `terraform_instance` resource there are several (by default 2) instances. We can map these to targets with the `target_mapping` key. We will set the target `name` to the name of the particular instance (for example, from the `tfstate` file snippet above `name` will resolve to  `terraform-instance-0`), and the `host` to the `network_ip` (note how indexing syntax works here, the `network_interface` key points to a list where we take the first value `0` and look up the `network_ip` which will resolve to `10.253.20.66` based on the `tfstate` snippet).

We set the ssh transport config via the `config` key (this will apply to any group in the inventory), in this case I set the username and private key as well as some other information about the ssh session (dont require host key verification and run any commands as the `root` user). 

```
groups:
  - name: terraform_vms
    targets:
      - _plugin: terraform
        dir: './terraform'
        resource_type: 'google_compute_instance.terraform_instance'
        target_mapping:
          name: name
          host: network_interface.0.network_ip

config:
  ssh:
    run-as: root
    host-key-check: false
    user: cas.donoghue
    private-key: ~/.ssh/id_rsa-gcloud
```

Now that we have our inventory saved we can see what targets are resolved with the `bolt inventory` command. 

```
(base) ➜  bolt_terraform_demo bolt inventory show --detail
terraform-instance-0
  name: terraform-instance-0
  uri: 10.253.20.66
  alias: []
  config:
    transport: ssh
    ssh:
      batch-mode: true
      cleanup: true
      connect-timeout: 10
      disconnect-timeout: 5
      load-config: true
      login-shell: bash
      tty: false
      host-key-check: false
      private-key: "/Users/cas.donoghue/.ssh/id_rsa-gcloud"
      run-as: root
      user: cas.donoghue
  vars: {}
  features: []
  facts: {}
  plugin_hooks:
    puppet_library:
      plugin: puppet_agent
      stop_service: true
  groups:
  - terraform_vms
  - all

terraform-instance-1
  name: terraform-instance-1
  uri: 10.253.20.65
  alias: []
  config:
    transport: ssh
    ssh:
      batch-mode: true
      cleanup: true
      connect-timeout: 10
      disconnect-timeout: 5
      load-config: true
      login-shell: bash
      tty: false
      host-key-check: false
      private-key: "/Users/cas.donoghue/.ssh/id_rsa-gcloud"
      run-as: root
      user: cas.donoghue
  vars: {}
  features: []
  facts: {}
  plugin_hooks:
    puppet_library:
      plugin: puppet_agent
      stop_service: true
  groups:
  - terraform_vms
  - all

Inventory source
  /Users/cas.donoghue/bolt-projects/bolt_terraform_demo/inventory.yaml

Target count
  2 total, 2 from inventory, 0 adhoc

Additional information
  Use the '--targets', '--query', or '--rerun' option to view specific targets
```

This config looks correct, so we can now try running a command on the newly provisioned hosts:
```
(base) ➜  bolt_terraform_demo bolt command run "hostname -f" --targets terraform_vms
Started on terraform-instance-0...
Started on terraform-instance-1...
Finished on terraform-instance-1:
  terraform-instance-1.c.team-skeletor-scratchpad.internal
Finished on terraform-instance-0:
  terraform-instance-0.c.team-skeletor-scratchpad.internal
Successful on 2 targets: terraform-instance-0,terraform-instance-1
Ran on 2 targets in 1.41 sec
```

At this point you can control the configuration of those provisioned GCP VMs using all the power of Bolt!

For the purpose of this demo workflow we are done with this set of resources so we can use the `terraform::destroy` plan to delete the VMs from GCP. 

```
bolt plan run terraform::destroy dir=terraform
```

## Orchestration of provisioning

One of the most powerful bolt features is the ability to run plans. Sometimes you want to provision new targets and configure them within the context of a single plan. In order to do this we can leverage the reference plugin to dynamically add targets to the inventory in the context of a plan run. This can be achieved with the [resolve_references plan function](https://puppet.com/docs/bolt/latest/plan_functions.html#resolve-references). We write a plan called `bolt_terraform_demo::dynamic_inventory_example` which will use terraform to provision some new VMs, add those newly provisioned targets to the inventory, wait for them to come online, run a command on them and finally destroy them. 

```
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

  # Destroy the newly provisioned hosts
  run_plan('terraform::destroy', dir => 'terraform')
}
```
You can see from the output of the plan that new VMs were provisioned, acted on by bolt and finally destroyed!

```
(base) ➜  bolt_terraform_demo bolt plan run bolt_terraform_demo::dynamic_inventory_example
Starting: plan bolt_terraform_demo::dynamic_inventory_example
Starting: plan terraform::apply
Starting: task terraform::apply on localhost
Finished: task terraform::apply with 0 failures in 16.06 sec
Finished: plan terraform::apply in 16.7 sec
Starting: wait until available on terraform-instance-0, terraform-instance-1
Finished: wait until available with 0 failures in 9.07 sec
Starting: command 'hostname -f' on terraform-instance-0, terraform-instance-1
Finished: command 'hostname -f' with 0 failures in 0.72 sec
[
  {
    "target": "terraform-instance-0",
    "action": "command",
    "object": "hostname -f",
    "status": "success",
    "value": {
      "stdout": "terraform-instance-0.c.team-skeletor-scratchpad.internal\n",
      "stderr": "",
      "merged_output": "terraform-instance-0.c.team-skeletor-scratchpad.internal\n",
      "exit_code": 0
    }
  },
  {
    "target": "terraform-instance-1",
    "action": "command",
    "object": "hostname -f",
    "status": "success",
    "value": {
      "stdout": "terraform-instance-1.c.team-skeletor-scratchpad.internal\n",
      "stderr": "",
      "merged_output": "terraform-instance-1.c.team-skeletor-scratchpad.internal\n",
      "exit_code": 0
    }
  }
]
Starting: plan terraform::destroy
Starting: task terraform::destroy on localhost
Finished: task terraform::destroy with 0 failures in 24.52 sec
Finished: plan terraform::destroy in 24.52 sec
Finished: plan bolt_terraform_demo::dynamic_inventory_example in 51.76 sec
Plan completed successfully with no result
```

## Conclusion

This example shows a practical workflow for provisioning nodes with the terraform plugin and interacting with them using Bolt's reference plugins. The ability of bolt to both interact with terraform actions such as `apply` and `destroy` coupled with the ability to look up data from the terraform state provide a powerful combination of tools to provision and manage cloud resources. 

If you want to talk about bolt or your use case for the terraform plugin come find us in #bolt on the [Puppet Community slack](https://slack.puppet.com/) to chat with Bolt developers and the community. 