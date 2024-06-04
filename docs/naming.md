# Naming conventions used in the module

It is important to follow a clear maning convention for cloud resources. This module uses the rules below when naming resources it creates:
- each resource name is prepended with a customizable prefix configurable using `prefix` input variable. According to Google Cloud naming recommendations your prefix should include tokens like **Company name**. **Business unit**. **Application code**, **Environment**. Default setting of "*fgtaa*" is used if variable is not set. Set the var.prefix to "" to not have any prefix prepended to names
- resource names include short version of resource type (e.g VM instance->"vm", unmanaged instance group->"umig", backend service->"bes")
- repeated resources are indexed using numbers starting from 1 (eg. fgt1, fgt2, fgt3)
- resources repeated for multiple network ports / subnets include FortiGate port name in the name (eg. fgtaa-fw-healthcheck-allow-port2)
- resources specific for each FortiGate instance include "fgt" and instance index in the name (eg. fgtaa-addr-mgmt-fgt1)
- regional and zonal resources have a short version of region/zone name appended at the end of their name. Region names are shortened to a 3-letter acronym composed from 2 letters of megaregion (e.g europe->eu, australia->au, etc.) and a single letter indicating "side" (eg. west->w, central->c, etc.) with the number added as the 4th character. Zones have appended zone indication to the shortened region name. All hyphens are removed from region and zone short names. Adding region to resource names enables using the same prefix for multi-regional deployments.

### Examples

The following are examples of names of the resources created by the module with default prefix in us-central1 region:
- fgtaa-vm-fgt1-usc1a
