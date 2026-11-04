# Comparison of different outbound modes for FortiGate clusters in GCP

There are multiple ways to handle outbound IPv4 connections (connections initiated by workloads behind FortiGate in Google Cloud targeted at public Internet) in Google Cloud:

- Cloud NAT
- external pass-through Network Load Balancer 
- directly attached external IP addresses

This article provides comparison between the above. You should choose the one matching your technical requirements while minimizing the cost for your individual use-case. Mind that sometimes the cost difference will be minimal (eg. $3 per month) and sometimes in thousands per month depending on the characteristics of your traffic. Note that this write-up is not about the egress flow of a connections initiated by client in the Internet towards services in Google Cloud where your flexibility of choice is limited (however some cost calculations still apply).

### Premium vs Standard network tier

Unless you're running a low-volume (below 1 TiB per month) deployment, a significant part of your egress cost will depend on the traffic volume and destination. Google Cloud offers Standard and Premium tiers. Research your traffic patterns, answer questions about the destination locations (traffic between North America, Europe and big part of Asia is half the price of traffic between to China) to choose the solution matching your needs and budget. Tiers are selected per public IP which allows you to mix them in a single deployment. Mind that Standard Tier offers SLA of 99.9%

## Directly-attached external IP addresses

This method leverages external IP addresses attached to each of the active FortiGates in the cluster. It might be a single address moved between peers in an SDN connector-based FGCP cluster (active-passive), individual IP addresses attached to each member of active-passive cluster or individual addresses attached to each member of active-active (FGSP-based) cluster.

### Infrastructure setup

VM instances have external IP address attached to one of the interfaces. Typically it will be port1 (nic0). In terraform code this is indicated by presence of `access_config {}` block under VM's `network_interface {}`:

```
resource "google_compute_instance" "fortigate" {
    network_interface {
        access_config {}
    }
}
```

External IP addresses can be reserved (address assignment can survive re-deployment of VM) or ephemeral (might change after instance stop/start or redeployment). Both types generate the same cost when in use.

### FortiGate configuration

Outbound traffic should be source-NATted by FortiGate to the interface private IP. It will be source-NATted again by GCP networking into the attached external (public) IP address

```
config firewall policy
  edit 0
    set nat enable
  next
end
```

### Should I choose it?

#### Cost:

Per-hour cost of IPv4 external address attached to a VM is relatively low and costs $0.005 / hour / address (or ~$131 per year for a 3-instance active-active cluster).

Data transfer rate applies as for all egress methods ranging between $0.08-$0.19 per gibibyte depending on source and destination locations and on total monthly volume per account. Switch to *Standard Tier* network to lower the data transfer costs.

Monthly cost of this solution for a 3-node active-active cluser for transfering 1GiB of data: $10.8

Monthly cost of this solution for a 3-node active-active cluser for transfering 10TiB of data: $660.8


*See the [VPC pricing](https://cloud.google.com/vpc/network-pricing?hl=en#virtual-private-cloud) for more details*.

#### Pros:
- simple setup
- low cost

#### Cons:
- in active-active scenario outbound IP address changes depending on the cluster member
- only one address available per network interface
- FortiGates are reachable from Internet

Choose directly attached external IP address if your workloads send a lot of traffic to global Internet locations and you don't care about controlling the SNAT IP addresses. Standard Tier will lower your data transfer cost but will limit some networking capabilities (eg. IPv6 stack requires Premium Tier). Note that this method can be combined with ELB for better control of the addresses.

## Cloud NAT

The Cloud NAT method leverages [Public Cloud NAT](https://docs.cloud.google.com/nat/docs/public-nat) service to streamline SNAT from FortiGate private addresses to public address. While the service used to be free of charge at the beginning of its existence while its featureset grew, so did the cost of using it.

### Infrastructure setup

Cloud NAT leverages a Cloud Router resource. When deployed to be used together with FortiGates it would apply to all connections from the external FortiGate subnet. Consult Google documentation for details on deployment using terraform or web console: [Set up Public NAT](https://docs.cloud.google.com/nat/docs/set-up-manage-network-address-translation#create-nat-gateway).

### FortiGate configuration

Outbound traffic should be source-NATted by FortiGate to the interface private IP. It will be source-NATted again by Cloud NAT to external (public) IP addresses. Possibility to use different public IP addresses depending on connection characteristics is currently in preview (see [source-based rules](https://docs.cloud.google.com/nat/docs/nat-rules-overview#source) for more details).

```
config firewall policy
  edit 0
    set nat enable
  next
end
```

### Should I choose it?

Per-hour cost of attached IP addresses is the same as for directly-attached external IP address (**$0.005** / hour / address), however in most cases you will use only one address instead of one per FortiGate instance making an **$~88** annual difference between 3-VM active-active cluster and Cloud NAT.

Additional per-hour cost of using Cloud NAT: $0.0014 / hour

Data transfer rate applies as for all egress methods ranging between $0.08-$0.19 per gibibyte depending on source and destination locations and on total monthly volume per account. Switch to *Standard Tier* network to lower the data transfer costs.

Data processing cost is added for both ingress and egress traffic processed by Cloud NAT: $0.045 / GiB

Monthly cost of this solution for a 3-node active-active cluser for transfering 1GiB of data: **$4.73**

Monthly cost of this solution for a 3-node active-active cluser for transfering 10TiB of data: **$1131-$2411** (depending on standard vs premium tier and locations)

Pros:
- FortiGates not directly available on Internet
- low cost for low volume

Cons:
- elevated cost for high volume of traffic (even if using Standard Tier)

This is the preferred choice if your outbound volume is relatively low. Note that high volume of traffic (especially when using Premium Tier for Cloud NAT) will highly increase your cost.

## External Network Load Balancer

This most flexible, but also potentially most costly method leverages properties of the network load balancer in Google Cloud using it not only for inbound but also for outbound traffic.

### Infrastructure setup

Typical *load balancer sandwich* architecture already includes an external pass-through Network Load Balancer (ELB). Unlike in some other cloud platforms, it does not require any special changes in order to be used for outbound traffic. FortiGate appliances can be added as pool-based backend or instance group backend type (both managed and unmanaged groups) to leverage the feature (recommended is unmanaged group-based backend). Mind that outbound traffic must (reverse) match the forwarding rule configuration in order to be allowed (eg. for a TCP connection with source port 2345 and destination 443 the forwarding rule must include TCP connections to port 2345). Recommended setup for the forwarding rule is `L3_DEFAULT` allowing all TCP, UDP, ICMP, ESP, AH, SCTP connections on all ports.

### FortiGate configuration

In order to pass traffic through a pass-through network load balancer FortiGate must translate the source address of the connection to the external IP address assigned to one of the load balancer's forwarding rules. In FortiGate you would configure it by creating an IP Pool with external IP address of the ELB and assigning it to NAT in the firewall policy. Mind that you will most likely also have the same IP address added as secondary IP to respond to the health probes (usually automatically configured by terraform module). Using this method requires session sync between all active FortiGate peers because ELB will randomly distribute reply flows across the healthy instances. Due to this, it cannot be used for local-out traffic in active-active clusters.

### Should I choose it?

Per-hour cost of running a load balancer is calculated based on the number of forwarding rules for all load balancers is **$0.025 / hour** for first 5 forwarding rules and **$0.01 / hour** for each additional one. When using `L3_DEFAULT` protocol number of forwarding rules will equal number of external IP addresses. Static (reserved) IPv4 addresses attached to ELB do not generate additional cost visible in Cloud NAT and directly-attached external IP address methods.

Data transfer rate applies as for all egress methods ranging between $0.08-$0.19 per gibibyte depending on source and destination locations and on total monthly volume per account. Switching to *Standard Tier* network can lower the data transfer costs but will affect inbound connections.

Data processing cost is added for both ingress and egress traffic: **$0.008 / 1GiB**

Monthly cost of this solution for a 3-node active-active cluser for transfering 1GiB of data: **$18.19**

Monthly cost of this solution for a 3-node active-active cluser for transfering 10TiB of data: **up to $1636** (depending on destination location, Premium Tier)

Pros:
- full control over addresses used for outbound traffic using FortiGate policy
- multiple IP addresses
- supports same address for inbound and outbound connections

Cons:
- elevated cost for high volume of traffic (but lower than for Cloud NAT)
- requires additional configuration on FortiGate
- not supported for local-out traffic in older FortiGate versions (<7.4) or in active-active clusters

Good choice for high-flexibility networking leveraging Premium Tier, giving full control on address choice to the FortiGate admins.


## Module choice logic

This module directs outbound traffic via port1 and via management port. By default management port is set to **port1** and is exposed via public IP addresses making local-out traffic and forwarded traffic NATted to interface address to leave through **public management IP addresses**.

If `var.mgmt_subnet` is set to a subnet different than attached to port1, a Cloud NAT will be added to the cluster to allow the local-out traffic to leave via port1. Port indicated as management port will be configured to route to all destinations mentioned in `var.admin_acl`. If `admin_acl` is left to 0.0.0.0 (default) route via port1 and Cloud NAT will take precedence due to lower priority number.

