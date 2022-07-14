locals {
  cloud_init_volume_name = var.cloud_init_volume_name == "" ? "${var.name}-cloud-init.iso" : var.cloud_init_volume_name
  bind_addresses = length(var.macvtap_interfaces) == 0 ? [var.libvirt_network.ip] : [for macvtap_interface in var.macvtap_interfaces: macvtap_interface.ip]
  network_config = templatefile(
    "${path.module}/files/network_config.yaml.tpl", 
    {
      macvtap_interfaces = var.macvtap_interfaces
    }
  )
  network_interfaces = length(var.macvtap_interfaces) == 0 ? [{
    network_id = var.libvirt_network.network_id
    macvtap = null
    addresses = [var.libvirt_network.ip]
    mac = var.libvirt_network.mac != "" ? var.libvirt_network.mac : null
    hostname = var.name
  }] : [for macvtap_interface in var.macvtap_interfaces: {
    network_id = null
    macvtap = macvtap_interface.interface
    addresses = null
    mac = macvtap_interface.mac
    hostname = null
  }]
  fluentd_conf = templatefile(
    "${path.module}/files/fluentd.conf.tpl", 
    {
      fluentd = var.fluentd
      fluentd_buffer_conf = var.fluentd.buffer.customized ? var.fluentd.buffer.custom_value : file("${path.module}/files/fluentd_buffer.conf")
    }
  )
}

data "template_cloudinit_config" "user_data" {
  gzip = false
  base64_encode = false
  part {
    content_type = "text/cloud-config"
    content = templatefile(
      "${path.module}/files/user_data.yaml.tpl", 
      {
        etcd_ca_certificate = var.etcd.ca_certificate
        etcd_client_certificate = var.etcd.client.certificate
        etcd_client_key = var.etcd.client.key
        etcd_client_username = var.etcd.client.username
        etcd_client_password = var.etcd.client.password
        etcd_endpoints = var.etcd.endpoints
        etcd_key_prefix = var.etcd.key_prefix
        prometheus = {
          web = {
            external_url = var.prometheus.web.external_url
            max_connections = var.prometheus.web.max_connections > 0 ? var.prometheus.web.max_connections : 512
            read_timeout = var.prometheus.web.read_timeout != "" ? var.prometheus.web.read_timeout : "5m"
          }
          retention = {
            time = var.prometheus.retention.time != "" ? var.prometheus.retention.time : "15d"
            size = var.prometheus.retention.size != "" ? var.prometheus.retention.size : "0"
          }
        }
        ssh_admin_user = var.ssh_admin_user
        admin_user_password = var.admin_user_password
        ssh_admin_public_key = var.ssh_admin_public_key
        chrony = var.chrony
        fluentd = var.fluentd
        fluentd_conf = local.fluentd_conf
      }
    )
  }
}

resource "libvirt_cloudinit_disk" "prometheus" {
  name           = local.cloud_init_volume_name
  user_data      = data.template_cloudinit_config.user_data.rendered
  network_config = length(var.macvtap_interfaces) > 0 ? local.network_config : null
  pool           = var.cloud_init_volume_pool
}

resource "libvirt_domain" "prometheus" {
  name = var.name

  cpu {
    mode = "host-passthrough"
  }

  vcpu = var.vcpus
  memory = var.memory

  disk {
    volume_id = var.volume_id
  }

  dynamic "network_interface" {
    for_each = local.network_interfaces
    content {
      network_id = network_interface.value["network_id"]
      macvtap = network_interface.value["macvtap"]
      addresses = network_interface.value["addresses"]
      mac = network_interface.value["mac"]
      hostname = network_interface.value["hostname"]
    }
  }

  autostart = true

  cloudinit = libvirt_cloudinit_disk.prometheus.id

  //https://github.com/dmacvicar/terraform-provider-libvirt/blob/main/examples/v0.13/ubuntu/ubuntu-example.tf#L61
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }
}