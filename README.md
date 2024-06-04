# FortiGate Terraform module:
## HA active-active cluster (FGSP in load balancer sandwich)

### Hot to use this module

We assume you have a working root module with proper Google provider configuration. If you don't - start by reading [Google Provider Configuration Reference](https://registry.terraform.io/providers/hashicorp/google/latest/docs/guides/provider_reference).

1. Create before you start (or define in your root terraform module) 4 VPC networks with one subnet in each. All subnets must be in the region where you want to deploy FortiGates and their CIDRs cannot overlap
1. Copy license files (*.lic) to the root module folder if you plan to deploy BYOL version. If using BYOL version you also have to change the `image_family` or `image_name` variable (see [examples/licensing-byol](./examples/licensing-byol) for details)
1. Reference this module in your code (eg. main.tf) to use it, eg.:
    ```
    module "fgt-ha" {  
      source = "git::github.com/40net-cloud/terraform-google-fortigate-aa-fgsp"  
    }
    ```
1. In the above module block provide the variables described in `variables.tf`. Only 2 variables are obligatory:
    - `region` - name of the region to deploy to (zones will be selected automatically); it also indicates subnets to use
    - `subnets` - list of 4 names of subnets already existing in the region to be used as external, internal, heartbeat and management networks.

    but you might want to provide values also to some others:
    - `zones` - list of 2 zones for FortiGate VMs. Always match these to your production workloads to avoid [inter-zone traffic fees](https://cloud.google.com/vpc/network-pricing). You can skip for proof-of-concept deployments and let the module automatically detect zones in the region.
    - `license_files` - list of paths to 2 license (.lic) files to be applied to the FortiGates. If skipped, VMs will be deployed without license and you will have to apply them manually upon first connection. It is highly recommended to apply BYOL licenses during deployment.
    - `prefix` - prefix to be added to the names of all created resources (defaults to "**fgt**")
    - `labels` - map of [Google Cloud labels](https://cloud.google.com/compute/docs/labeling-resources) to be applied to VMs, disks and forwarding rules
    - `admin_acl` - list of CIDRs allowed to access FortiGates' management interfaces (defaults to [0.0.0.0/0])
    - `machine-type` - type of VM to use for deployment. Defaults to **e2-standard-4** which is a good (cheaper) choice for evaluation, but offers lower performance than n2 or c2 families.
    - `image_family` or `image_name` - for selecting different firmware version or different licensing model. Defaults to newest 7.2 image with PAYG licensing (fortigate-72-payg)
    - `frontends` - list of names to be used to create ELB frontends and EIPs. By default no frontends are created. Resource names will be prepended with the `var.prefix` and resource type.
1. Run the deployment using the tool of your choice (eg. `terraform init; terraform apply` from command line)

Examples can be found in [examples](examples) directory.

Terraform module for deploying Active-Active FGSP cluster of FortiGates


## Configuration

#### FGSP

FGSP (FortiGate Session Life Support Protocol) is used to sync connection tables in active-active deployments. It can be also used to redirect asymmetric flows for IPS/AV inspection between members of FGSP group. This module will enable session sync including connectionless and nat sessions using the following code:

```
config system ha
    set session-pickup enable
    set session-pickup-connectionless enable
    set session-pickup-nat enable
end
```

We recommend to assign a dedicated port for FGSP sync. By default this role will be assigned to the last port (last subnet on the var.subnets list). You can modify the default behavior:

- to not use any port as dedicated for FGSP and use the **port1** for both production traffic and FGSP sync: set var.fgsp_port to null
- to use a different port as dedicated for FGSP (it will not be linked to any load balancer and access will be restricted): set var.fgsp_port to the name of FortiGate port (eg. "port2")

**NOTE: do NOT set fgsp_port to port1**