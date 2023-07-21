#cloud-config
merge_how:
 - name: list
   settings: [append, no_replace]
 - name: dict
   settings: [no_replace, recurse_list]

%{ if admin_user_password != "" ~}
chpasswd:
  list: |
     ${ssh_admin_user}:${admin_user_password}
  expire: False
%{ endif ~}
preserve_hostname: false
hostname: ${hostname}
users:
  - default
  - name: ${ssh_admin_user}
    ssh_authorized_keys:
      - "${ssh_admin_public_key}"

%{ if length(prometheus_secrets) > 0 ~}
write_files:
%{ for secret in prometheus_secrets ~}
  - path: ${secret.path}
    owner: root:root
    permissions: "0400"
    content: |
      ${indent(6, secret.content)}
%{ endfor ~}

runcmd:
%{ for secret in prometheus_secrets ~}
  - chown prometheus:prometheus ${secret.path}
%{ endfor ~}
%{ endif ~}