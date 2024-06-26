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


### Configuration

#### Firmware version and choosing base image

Selecting base image for VM deployment is crucial, but complicated task. The image depends on three factors: version, licensing (BYOL or PAYG) and VM hardware architecture (Intel or ARM). This module supports multiple ways to select the image using `var.image` object:

- Default: by default image will be selected to match a recent mature firmware version. It will not be the newest version. Licensing will be automatically set to PAYG unless you add license files or flex tokens to the module variables
- select by version: provide the exact version (eg. "7.4.4") in `var.image.version`. You can also provide only the major version (eg. "7.4") to let the template pick the latest available firmware from the indicated branch
- select by family: add the image family name (eg. "fortigate-72-byol") in `var.image.family` to select the latest available firmware from indicated branch and license type
- select by name: this option is useful if you deploy using custom images. You can set the image name using `var.image.name` and project name using `var.image.project`

**Remember to use HCL notation when providing object values. Example *var.image.version="7.4.4"* value provided above should be written as**

```
image = {
  version = "7.4.4"
}
```

PAYG and BYOL deployments use different base images. Be careful to not deploy PAYG image if you have purchased a license from Fortinet channel partner as you will be charged twice. While this module by default deploys PAYG images it will automatically switch to BYOL if you add FortiFlex tokens or license files to the configuration. You can also enforce properly licensed image manually by setting `var.image.lic` variable to licensing option (in lowercase). Eg.:

```
image = {
    lic = "byol"
}
```

If deploying using ARM-based machine types you have to indicate a proper image compiled for this architecture using `var.image.arch` variable.

#### FGSP

FGSP (FortiGate Session Life Support Protocol) is used to sync connection tables in active-active deployments. It can be also used to redirect asymmetric flows for IPS/AV inspection between members of FGSP group. This module will enable session sync including connectionless and nat sessions using the following code:

```
config system ha
    set session-pickup enable
    set session-pickup-connectionless enable
    set session-pickup-nat enable
end
```

...and add proper tag-based firewall rules to Cloud Firewall.

We recommend to assign a dedicated port for FGSP sync. By default this role will be assigned to the last port (last subnet on the var.subnets list). You can modify the default behavior:

- to not use any port as dedicated for FGSP and use the **port1** for both production traffic and FGSP sync: set `var.fgsp_port` to `null`
- to use a different port as dedicated for FGSP (it will not be linked to any load balancer and access will be restricted): set `var.fgsp_port` to the name of FortiGate port (eg. "port2")

**NOTE: do NOT set dedicated fgsp_port to port1**

#### Management access

All deployed FortiGate VM instances can be accessed and managed individually using their private or (optionally) public IP address. The default setting enables public IP addresses on the FGSP port. Although it is a convenient setting, it is not the most secure one. Make sure you adapt settings to your local deployment and use private connectivity for administrative access whenever possible. The following variables can be set to modify the default configuration for management port:

- set `var.mgmt_port` to your desired FortiGate port name (eg. "port1") to enable management on that port. Leaving this variable to default will use the FGSP port
- set `var.mgmt_port_public` to `false` to disable external IP addresses for management

The default *admin* passwords will be set to instance ID (and written to `fgt_passwords` output) and will have to be changed upon the first login.

#### FortiManager integration

Deployed FortiGates can be optionally linked to FortiManager during bootstraping. To enable this feature use var.fortimanager variable and set it to object including the following properties:

- `ip` - IP address or FQDN name of FortiManager
- `serial` - serial number of FortiManager. Note that missing serial number will cause the connection to fail.