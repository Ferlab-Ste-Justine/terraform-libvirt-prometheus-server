#cloud-config
%{ if admin_user_password != "" ~}
chpasswd:
  list: |
     ${ssh_admin_user}:${admin_user_password}
  expire: False
%{ endif ~}
users:
  - default
  - name: node-exporter
    system: true
    lock_passwd: true
  - name: prometheus
    system: true
    lock_passwd: true
  - name: ${ssh_admin_user}
    ssh_authorized_keys:
      - "${ssh_admin_public_key}"
write_files:
  #Chrony config
%{ if chrony.enabled ~}
  - path: /opt/chrony.conf
    owner: root:root
    permissions: "0444"
    content: |
%{ for server in chrony.servers ~}
      server ${join(" ", concat([server.url], server.options))}
%{ endfor ~}
%{ for pool in chrony.pools ~}
      pool ${join(" ", concat([pool.url], pool.options))}
%{ endfor ~}
      driftfile /var/lib/chrony/drift
      makestep ${chrony.makestep.threshold} ${chrony.makestep.limit}
      rtcsync
%{ endif ~}
  #Prometheus node exporter systemd configuration
  - path: /etc/systemd/system/node-exporter.service
    owner: root:root
    permissions: "0444"
    content: |
      [Unit]
      Description="Prometheus Node Exporter"
      Wants=network-online.target
      After=network-online.target
      StartLimitIntervalSec=0

      [Service]
      User=node-exporter
      Group=node-exporter
      Type=simple
      Restart=always
      RestartSec=1
      ExecStart=/usr/local/bin/node_exporter

      [Install]
      WantedBy=multi-user.target
%{ if fluentd.enabled ~}
  #Fluentd config file
  - path: /opt/fluentd.conf
    owner: root:root
    permissions: "0444"
    content: |
      ${indent(6, fluentd_conf)}
  #Fluentd systemd configuration
  - path: /etc/systemd/system/fluentd.service
    owner: root:root
    permissions: "0444"
    content: |
      [Unit]
      Description="Fluentd"
      Wants=network-online.target
      After=network-online.target
      StartLimitIntervalSec=0

      [Service]
      User=root
      Group=root
      Type=simple
      Restart=always
      RestartSec=1
      ExecStart=fluentd -c /opt/fluentd.conf

      [Install]
      WantedBy=multi-user.target
  #Fluentd forward server certificate
  - path: /opt/fluentd_ca.crt
    owner: root:root
    permissions: "0444"
    content: |
      ${indent(6, fluentd.forward.ca_cert)}
%{ endif ~}
  #Prometheus systemd configuration
  - path: /etc/systemd/system/prometheus.service
    owner: root:root
    permissions: "0444"
    content: |
      [Unit]
      Description="Metrics Service"
      Wants=network-online.target
      After=network-online.target
      StartLimitIntervalSec=0

      [Service]
      User=prometheus
      Group=prometheus
      Type=simple
      Restart=always
      RestartSec=1
      ExecStart=/usr/local/bin/prometheus \
          --config.file=/etc/prometheus/configs/prometheus.yml \
          --web.console.templates=/etc/prometheus/consoles \
          --web.console.libraries=/etc/prometheus/console_libraries \
          --web.external-url=${prometheus.web.external_url} \
          --web.max-connections=${prometheus.web.max_connections} \
          --web.read-timeout=${prometheus.web.read_timeout} \
          --storage.tsdb.path=/var/lib/prometheus/data \
          --storage.tsdb.retention.time=${prometheus.retention.time} \
          --storage.tsdb.retention.size=${prometheus.retention.size}
      ExecReload=/bin/kill -HUP $MAINPID

      [Install]
      WantedBy=multi-user.target
  - path: /usr/local/bin/reload-prometheus-configs
    owner: root:root
    permissions: "0555"
    content: |
      #!/bin/sh
      PROMETHEUS_STATUS=$(systemctl is-active prometheus.service)
      if [ $PROMETHEUS_STATUS = "active" ]; then
        systemctl reload prometheus.service
      fi
  - path: /etc/etcd/ca.crt
    owner: root:root
    permissions: "0444"
    content: |
      ${indent(6, etcd_ca_certificate)}
%{ if etcd_client_username == "" ~}
  - path: /etc/etcd/client.crt
    owner: root:root
    permissions: "0444"
    content: |
      ${indent(6, etcd_client_certificate)}
  - path: /etc/etcd/client.key
    owner: root:root
    permissions: "0440"
    content: |
      ${indent(6, etcd_client_key)}
%{ endif ~}
  - path: /etc/configurations-auto-updater/configs.json
    owner: root:root
    permissions: "0440"
    content: |
      {
          "FilesystemPath": "/etc/prometheus/configs/",
          "EtcdEndpoints": "${join(",", etcd_endpoints)}",
          "CaCertPath": "/etc/etcd/ca.crt",
          "UserAuth": {
%{ if etcd_client_username == "" ~}
              "CertPath": "/etc/etcd/client.crt",
              "KeyPath": "/etc/etcd/client.key"
%{ else ~}
              "Username": "${etcd_client_username}",
              "Password": "${etcd_client_password}"
%{ endif ~}
          },
          "EtcdKeyPrefix": "${etcd_key_prefix}",
          "ConnectionTimeout": 5,
          "RequestTimeout": 5,
          "FilesPermission": "0770",
          "DirectoriesPermission": "0770",
          "NotificationCommand": ["/usr/local/bin/reload-prometheus-configs"]
      }
  #Configurations auto updater systemd configuration
  - path: /etc/systemd/system/configurations-auto-updater.service
    owner: root:root
    permissions: "0444"
    content: |
      [Unit]
      Description="Prometheus Configurations Updating Service"
      Wants=network-online.target
      After=network-online.target
      StartLimitIntervalSec=0

      [Service]
      Environment=CONFS_AUTO_UPDATER_CONFIG_FILE=/etc/configurations-auto-updater/configs.json
      User=prometheus
      Group=prometheus
      Type=simple
      Restart=always
      RestartSec=1
      WorkingDirectory=/opt
      ExecStart=/usr/local/bin/configurations-auto-updater

      [Install]
      WantedBy=multi-user.target
packages:
  - curl
  - unzip
%{ if fluentd.enabled ~}
  - ruby-full
  - build-essential
%{ endif ~}
%{ if chrony.enabled ~}
  - chrony
%{ endif ~}
runcmd:
  #Finalize Chrony Setup
%{ if chrony.enabled ~}
  - cp /opt/chrony.conf /etc/chrony/chrony.conf
  - systemctl restart chrony.service 
%{ endif ~}
  #Install prometheus node exporter as a binary managed as a systemd service
  - wget -O /opt/node_exporter.tar.gz https://github.com/prometheus/node_exporter/releases/download/v1.3.0/node_exporter-1.3.0.linux-amd64.tar.gz
  - mkdir -p /opt/node_exporter
  - tar zxvf /opt/node_exporter.tar.gz -C /opt/node_exporter
  - cp /opt/node_exporter/node_exporter-1.3.0.linux-amd64/node_exporter /usr/local/bin/node_exporter
  - chown node-exporter:node-exporter /usr/local/bin/node_exporter
  - rm -r /opt/node_exporter && rm /opt/node_exporter.tar.gz
  - systemctl enable node-exporter
  - systemctl start node-exporter
  #Fluentd setup
%{ if fluentd.enabled ~}
  - mkdir -p /opt/fluentd-state
  - chown root:root /opt/fluentd-state
  - chmod 0700 /opt/fluentd-state
  - gem install fluentd
  - gem install fluent-plugin-systemd -v 1.0.5
  - systemctl enable fluentd.service
  - systemctl start fluentd.service
%{ endif ~}
  #Setup configurations auto updater service
  - curl -L https://github.com/Ferlab-Ste-Justine/configurations-auto-updater/releases/download/v0.2.0/configurations-auto-updater_0.2.0_linux_amd64.tar.gz -o /tmp/configurations-auto-updater_0.2.0_linux_amd64.tar.gz
  - mkdir -p /tmp/configurations-auto-updater
  - tar zxvf /tmp/configurations-auto-updater_0.2.0_linux_amd64.tar.gz -C /tmp/configurations-auto-updater
  - cp /tmp/configurations-auto-updater/configurations-auto-updater /usr/local/bin/configurations-auto-updater
  - rm -rf /tmp/configurations-auto-updater
  - rm -f /tmp/configurations-auto-updater_0.2.0_linux_amd64.tar.gz
  - chown -R prometheus:prometheus /etc/etcd
  - chown -R prometheus:prometheus /etc/configurations-auto-updater
  - mkdir /etc/prometheus
  - chown prometheus:prometheus /etc/prometheus
  - systemctl enable configurations-auto-updater
  - systemctl start configurations-auto-updater
  #Setup prometheus service
  - curl -L https://github.com/prometheus/prometheus/releases/download/v2.36.2/prometheus-2.36.2.linux-amd64.tar.gz --output prometheus.tar.gz
  - mkdir -p /tmp/prometheus
  - tar zxvf prometheus.tar.gz -C /tmp/prometheus
  - cp -r /tmp/prometheus/prometheus-2.36.2.linux-amd64/console_libraries /etc/prometheus/console_libraries
  - chown -R prometheus:prometheus /etc/prometheus/console_libraries
  - cp -r /tmp/prometheus/prometheus-2.36.2.linux-amd64/consoles /etc/prometheus/consoles
  - chown -R prometheus:prometheus /etc/prometheus/consoles
  - cp /tmp/prometheus/prometheus-2.36.2.linux-amd64/prometheus /usr/local/bin/prometheus
  - cp /tmp/prometheus/prometheus-2.36.2.linux-amd64/promtool /usr/local/bin/promtool
  - rm -r /tmp/prometheus
  - rm prometheus.tar.gz
  - mkdir -p /var/lib/prometheus/data
  - chown -R prometheus:prometheus /var/lib/prometheus
  - systemctl enable prometheus
  - systemctl start prometheus