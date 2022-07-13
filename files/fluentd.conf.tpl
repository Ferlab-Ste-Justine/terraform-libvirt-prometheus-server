<system>
  Log_Level info
</system>

<source>
  @type systemd
  tag ${fluentd.prometheus_tag}
  path /var/log/journal
  matches [{ "_SYSTEMD_UNIT": "prometheus.service" }]
  read_from_head true

  <storage>
    @type local
    path /opt/fluentd-state/prometheus-cursor.json
  </storage>
</source>

<source>
  @type systemd
  tag ${fluentd.configurations_updater_tag}
  path /var/log/journal
  matches [{ "_SYSTEMD_UNIT": "configurations-auto-updater.service" }]
  read_from_head true

  <storage>
    @type local
    path /opt/fluentd-state/configurations-auto-updater-cursor.json
  </storage>
</source>

<source>
  @type systemd
  tag ${fluentd.node_exporter_tag}
  path /var/log/journal
  matches [{ "_SYSTEMD_UNIT": "node-exporter.service" }]
  read_from_head true

  <storage>
    @type local
    path /opt/fluentd-state/node-exporter-cursor.json
  </storage>
</source>

<match *>
  @type forward
  transport tls
  tls_insecure_mode false
  tls_allow_self_signed_cert false
  tls_verify_hostname true
  tls_cert_path /opt/fluentd_ca.crt
  send_timeout 20
  connect_timeout 20
  hard_timeout 20
  recover_wait 10
  expire_dns_cache 5
  dns_round_robin true

  <server>
    host ${fluentd.forward.domain}
    port ${fluentd.forward.port}
  </server>

  <security>
    self_hostname ${fluentd.forward.hostname}
    shared_key ${fluentd.forward.shared_key}
  </security>

  ${indent(2, fluentd_buffer_conf)}
</match>