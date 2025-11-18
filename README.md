# Quick Start

This is a conceptual Demo Scenario that will help you to bring highly available and secured connectivity with dynamic routing between Cloud and On-Prem using regular Internet circuits.

>Key idea of this scenario based on limitations coming from On-Prem side which as two Internet circuits (Main and Backup where Backup is the `Radio Bridge`)

The materials from this repository will help you quickly build from the scratch the following network topology:

[Target Topology](img/topology.svg)

To prepare your admin workstation (desktop, laptop or maybe something else) follow these steps:

1. Prepare your VK Cloud project (enable CLI and API access): [URL](https://cloud.vk.com/docs/en/tools-for-using-services/api/rest-api/enable-api)
2. Create and upload your SSH key into the cloud admin account: [URL](https://cloud.vk.com/docs/tools-for-using-services/vk-cloud-account/instructions/account-manage/keypairs#importing_existing_key)
3. Install Terraform components depending on your OS: [URL](https://cloud.vk.com/docs/en/tools-for-using-services/terraform/quick-start)
4. Install Ansible components depending on your OS: [URL](https://docs.ansible.com/projects/ansible/latest/installation_guide/intro_installation.html#pipx-install)
5. Install GIT components and copy this repo onto your admin workstation

Additional Steps:

- Use you private SSH key within Terraform and Ansible
- Use proper account credentials within Terraform

# Under the Hood

>Main part of thies scenario related to the routers (a pair of IaaS Virtual Machines (`IaaS Routers`) converted into traditional routers with advanced functionoality)

**Terraform**

Provisions a pair of `IaaS Routers` with internal and external ports. Includes supplimentary Shell script (which is a part of Terraform manifest) to maintain configuration across reboots.

**Ansible**

Configure `IaaS Routers` using role-based playbooks controlled via the [Inventory File](ansible/inventory.ini)

**Additional Software Used:**

- strongSwan (to manage IPsec)
- FRR (to manage BGP)
- Keepalived (VRRP)

[Private and Public Ports](img/ports.svg)

Each IaaS Router will use two secured connections to On-Prem environment through the Internet:

- IPsec Site-to-Site in Transport Mode (to protect GRE Tunnels)
- GRE Tunnel (to transfer a data)

[Secured Connections](img/connections.svg)

GRE Tunnels topology clearly ecxplained in the following diagram:

[GRE Tunnels](img/tunnels.svg)

**High Availability Design**

BGP peering eliminates single points of failure on the Cloud side through:

- Bidirectional eBGP sessions from each `IaaS Router` to On-Premises
- Optimized route metrics reflecting circuit priority (Primary/Backup)
- Automatic failover during circuit failures (including Cloud Availability Zone failures)
- Asymmetric routing prevention via MED and Local Preference configuration

[BGP Peering](img/bgp.svg)