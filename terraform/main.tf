data "vkcs_images_image" "ubuntu24" {
  visibility  = "public"
  most_recent = true
  properties = {
    mcs_os_distro  = "ubuntu"
    mcs_os_version = "24.04"
  }
}

data "vkcs_networking_network" "extnet" {
  name = "internet"
  sdn = "sprut"
}

# LAN Network
resource "vkcs_networking_network" "lan_net" {
  name           = "router-lan-net"
  sdn            = "sprut"
  admin_state_up = true
}

resource "vkcs_networking_subnet" "lan_subnet" {
  network_id = vkcs_networking_network.lan_net.id
  name       = "router-lan-subnet"
  cidr       = "10.200.10.0/24"
  gateway_ip = "10.200.10.1"
  dns_nameservers = ["8.8.8.8", "1.1.1.1"]
  sdn        = "sprut"

  allocation_pool {
    start = "10.200.10.100"
    end   = "10.200.10.200"
  }
}

# Security Groups
resource "vkcs_networking_secgroup" "router_sg" {
  name = "router-sg"
  sdn  = "sprut"
}

resource "vkcs_networking_secgroup" "private_sg" {
  name = "private-sg"
  sdn  = "sprut"
} 

# Private SG rules
resource "vkcs_networking_secgroup_rule" "from_rfc_net192_in" {
  direction         = "ingress"
  remote_ip_prefix  = "192.168.0.0/16"
  security_group_id = vkcs_networking_secgroup.private_sg.id
  sdn               = "sprut"
}

resource "vkcs_networking_secgroup_rule" "from_rfc_net172_in" {
  direction         = "ingress"
  remote_ip_prefix  = "172.16.0.0/12"
  security_group_id = vkcs_networking_secgroup.private_sg.id
  sdn               = "sprut"
}

resource "vkcs_networking_secgroup_rule" "from_rfc_net10_in" {
  direction         = "ingress"
  remote_ip_prefix  = "10.0.0.0/8"
  security_group_id = vkcs_networking_secgroup.private_sg.id
  sdn               = "sprut"
}

# Router SG rules
resource "vkcs_networking_secgroup_rule" "router_ssh" {
  direction         = "ingress"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = vkcs_networking_secgroup.router_sg.id
  sdn               = "sprut"
}

resource "vkcs_networking_secgroup_rule" "router_icmp" {
  direction         = "ingress"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = vkcs_networking_secgroup.router_sg.id
  sdn               = "sprut"
}

resource "vkcs_networking_secgroup_rule" "router_ipsec_ike" {
  direction         = "ingress"
  protocol          = "udp"
  port_range_min    = 500
  port_range_max    = 500
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = vkcs_networking_secgroup.router_sg.id
  sdn               = "sprut"
}

resource "vkcs_networking_secgroup_rule" "router_ipsec_nat_t" {
  direction         = "ingress"
  protocol          = "udp"
  port_range_min    = 4500
  port_range_max    = 4500
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = vkcs_networking_secgroup.router_sg.id
  sdn               = "sprut"
}

# Router LAN Ports
resource "vkcs_networking_port" "lan_port1" {
  name               = "router1-lan-port"
  network_id         = vkcs_networking_network.lan_net.id
  admin_state_up     = true
  port_security_enabled = false
  full_security_groups_control = true
  security_group_ids = []
  sdn                = "sprut"
  fixed_ip {
    subnet_id  = vkcs_networking_subnet.lan_subnet.id
    ip_address = "10.200.10.254"
  }
}

resource "vkcs_networking_port" "lan_port2" {
  name               = "router2-lan-port"
  network_id         = vkcs_networking_network.lan_net.id
  admin_state_up     = true
  port_security_enabled = false
  full_security_groups_control = true
  security_group_ids = []
  sdn                = "sprut"
  fixed_ip {
    subnet_id  = vkcs_networking_subnet.lan_subnet.id
    ip_address = "10.200.10.253"
  }
}

resource "vkcs_compute_instance" "router1" {
  name              = "router1"
  image_id          = data.vkcs_images_image.ubuntu24.id
  flavor_name       = "STD3-4-4"
  availability_zone = "ME1"
  key_pair          = var.ssh_key_name

  security_group_ids = [
    vkcs_networking_secgroup.router_sg.id,
    "d479b4d7-55b3-4ff1-bf8d-24d826a38f11"
  ]

  config_drive = true
  
  # Configure persistent networking using script
  user_data = file("${path.module}/scripts/network-init.sh")

  # WAN: dynamically created port
  network {
    uuid = data.vkcs_networking_network.extnet.id
  }

  # LAN: pre-created port
  network {
    port = vkcs_networking_port.lan_port1.id
  }

  block_device {
    uuid                  = data.vkcs_images_image.ubuntu24.id
    source_type           = "image"
    volume_size           = 20
    boot_index            = 0
    destination_type      = "volume"
    volume_type           = "ceph-ssd"
    delete_on_termination = true
  }
}

resource "vkcs_compute_instance" "router2" {
  name              = "router2"
  image_id          = data.vkcs_images_image.ubuntu24.id
  flavor_name       = "STD3-4-4"
  availability_zone = "ME1"
  key_pair          = var.ssh_key_name

  security_group_ids = [
    vkcs_networking_secgroup.router_sg.id,
    "d479b4d7-55b3-4ff1-bf8d-24d826a38f11"
  ]

  config_drive = true
  
  # Configure persistent networking using script
  user_data = file("${path.module}/scripts/network-init.sh")

  # WAN: dynamically created port
  network {
    uuid = data.vkcs_networking_network.extnet.id
  }

  # LAN: pre-created port
  network {
    port = vkcs_networking_port.lan_port2.id
  }

  block_device {
    uuid                  = data.vkcs_images_image.ubuntu24.id
    source_type           = "image"
    volume_size           = 20
    boot_index            = 0
    destination_type      = "volume"
    volume_type           = "ceph-ssd"
    delete_on_termination = true
  }
}

resource "vkcs_compute_instance" "priv_srv_01" {
  name              = "Priv-SRV-01"
  image_id          = data.vkcs_images_image.ubuntu24.id
  flavor_name       = "STD3-4-4"
  availability_zone = "ME1"
  key_pair          = var.ssh_key_name

  security_group_ids = [
    vkcs_networking_secgroup.private_sg.id,
    "d479b4d7-55b3-4ff1-bf8d-24d826a38f11"
  ]

  network {
    uuid = vkcs_networking_network.lan_net.id
  }

  block_device {
    uuid                  = data.vkcs_images_image.ubuntu24.id
    source_type           = "image"
    volume_size           = 20
    boot_index            = 0
    destination_type      = "volume"
    volume_type           = "ceph-ssd"
    delete_on_termination = true
  }

}

resource "vkcs_compute_instance" "priv_srv_02" {
  name              = "Priv-SRV-02"
  image_id          = data.vkcs_images_image.ubuntu24.id
  flavor_name       = "STD3-4-4"
  availability_zone = "ME1"
  key_pair          = var.ssh_key_name

  security_group_ids = [
    vkcs_networking_secgroup.private_sg.id,
    "d479b4d7-55b3-4ff1-bf8d-24d826a38f11"
  ]

  network {
    uuid = vkcs_networking_network.lan_net.id
  }

  block_device {
    uuid                  = data.vkcs_images_image.ubuntu24.id
    source_type           = "image"
    volume_size           = 20
    boot_index            = 0
    destination_type      = "volume"
    volume_type           = "ceph-ssd"
    delete_on_termination = true
  }
}

resource "vkcs_compute_instance" "priv_srv_03" {
  name              = "Priv-SRV-03"
  image_id          = data.vkcs_images_image.ubuntu24.id
  flavor_name       = "STD3-4-4"
  availability_zone = "MS1"
  key_pair          = var.ssh_key_name

  security_group_ids = [
    vkcs_networking_secgroup.private_sg.id,
    "d479b4d7-55b3-4ff1-bf8d-24d826a38f11"
  ]

  network {
    uuid = vkcs_networking_network.lan_net.id
  }

  block_device {
    uuid                  = data.vkcs_images_image.ubuntu24.id
    source_type           = "image"
    volume_size           = 20
    boot_index            = 0
    destination_type      = "volume"
    volume_type           = "ceph-ssd"
    delete_on_termination = true
  }
}