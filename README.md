# infra-ops-scripts

Collection of day-to-day automation scripts for Linux administration, Terraform workflows, Ansible playbooks, Docker, LXD, and Windows PowerShell operations.

---

## Terraform

| Script | Description |
|---|---|
| [plan.sh](plan.sh) | Init and run `terraform plan` against a given path |
| [apply.sh](apply.sh) | Init and run `terraform apply -auto-approve` against a given path |
| [destroy.sh](destroy.sh) | Init and run `terraform destroy -auto-approve` against a given path |
| [validate.sh](validate.sh) | Run `terraform fmt -check` and `terraform validate` before plan/apply |
| [workspace.sh](workspace.sh) | Create, select, list, show, and delete Terraform workspaces |
| [state_list.sh](state_list.sh) | List, show, move, remove, and pull Terraform state resources |

**Usage:**
```bash
./plan.sh terraform/instance
./apply.sh terraform/instance
./validate.sh terraform/instance
./workspace.sh create staging terraform/instance
./state_list.sh list terraform/instance
./state_list.sh remove aws_instance.web terraform/instance
```

---

## Ansible Playbooks

| Playbook | Description |
|---|---|
| [playbook_patch_os.yml](playbook_patch_os.yml) | Patch and reboot Linux hosts (apt/yum), one host at a time |
| [playbook_user_management.yml](playbook_user_management.yml) | Create/delete users, manage SSH keys and sudo access |
| [playbook_deploy_app.yml](playbook_deploy_app.yml) | Pull a Docker image and deploy a container on remote hosts |
| [playbook_service_restart.yml](playbook_service_restart.yml) | Start, stop, or restart services across hosts |
| [playbook_service_status_check.yml](playbook_service_status_check.yml) | Check status of services within a deployment |
| [service_status.yml](service_status.yml) | Check and report status of defined services |

**Inventory:** [`inventory/hosts.ini`](inventory/hosts.ini)

**Usage:**
```bash
ansible-playbook -i inventory/hosts.ini playbook_patch_os.yml
ansible-playbook -i inventory/hosts.ini playbook_patch_os.yml --limit staging
ansible-playbook -i inventory/hosts.ini playbook_deploy_app.yml --limit webservers
ansible-playbook -i inventory/hosts.ini playbook_user_management.yml
```

---

## System Administration (Bash)

| Script | Description |
|---|---|
| [check_services_status.sh](check_services_status.sh) | Check runtime status of common services |
| [start_stop_restart_service.sh](start_stop_restart_service.sh) | Interactive start/stop/restart for a service |
| [backup.sh](backup.sh) | Create timestamped tar.gz archives with integrity check and retention cleanup |
| [log_rotate.sh](log_rotate.sh) | Compress and delete old log files with configurable age and dry-run support |
| [cpu_memory_monitor.sh](cpu_memory_monitor.sh) | Monitor CPU and memory, alert on threshold breach with optional email |
| [ssl_cert_check.sh](ssl_cert_check.sh) | Check SSL certificate expiry for a list of hosts, WARN/CRIT thresholds |
| [user_audit.sh](user_audit.sh) | Audit login-shell users, sudo access, last logins, failed attempts, UID 0 accounts |

**Usage:**
```bash
./backup.sh /etc/nginx /backups 14
./log_rotate.sh /var/log/nginx --age 7 --delete 60 --dry-run
./cpu_memory_monitor.sh --cpu-threshold 85 --mem-threshold 80 --disk-threshold 90 --interval 30
./ssl_cert_check.sh hosts.txt --warn 30 --crit 7 --email ops@example.com
./user_audit.sh --output /tmp/audit.txt
```

---

## Docker

| Script | Description |
|---|---|
| [docker_cleanup.sh](docker_cleanup.sh) | Remove stopped containers, dangling images, unused volumes and networks |
| [docker_health_check.sh](docker_health_check.sh) | Check health status of containers, auto-restart unhealthy ones |

**Usage:**
```bash
./docker_cleanup.sh --all --dry-run
./docker_cleanup.sh --containers --images
./docker_health_check.sh --restart --email ops@example.com
./docker_health_check.sh --name myapp --restart
```

---

## LXD Containers

| Script | Description |
|---|---|
| [lxd_snapshot.sh](lxd_snapshot.sh) | Create, list, restore, delete LXD snapshots with retention pruning |

**Usage:**
```bash
./lxd_snapshot.sh create rocky
./lxd_snapshot.sh auto rocky --retain 7
./lxd_snapshot.sh all --retain 3
./lxd_snapshot.sh restore rocky snap_20260403_120000
```

---

## Windows PowerShell

| Script | Description |
|---|---|
| [disk_space.ps1](disk_space.ps1) | Collect disk usage across servers and email an HTML report |
| [cpu_memory_report.ps1](cpu_memory_report.ps1) | Collect CPU and memory stats across servers, color-coded HTML report |
| [windows_update_status.ps1](windows_update_status.ps1) | Check pending Windows Updates and reboot status per server |
| [event_log_errors.ps1](event_log_errors.ps1) | Pull Critical/Error events from System and Application logs across servers |

**Usage:**
```powershell
# Update C:\Scripts\Test\ServerList.txt with target server names, then run:
.\disk_space.ps1
.\cpu_memory_report.ps1
.\windows_update_status.ps1
.\event_log_errors.ps1
```

---

## GitHub Actions Workflows

| Workflow | Trigger | Description |
|---|---|---|
| [terraform-plan.yml](.github/workflows/terraform-plan.yml) | PR to `main` touching `terraform/**` | fmt check, validate, plan — posts output as PR comment |
| [terraform-apply.yml](.github/workflows/terraform-apply.yml) | Push to `main` or manual dispatch | apply with `production` environment gate (manual approval) |
| [ansible-lint.yml](.github/workflows/ansible-lint.yml) | Push/PR on `*.yml` files | Lint all playbooks with `ansible-lint`, post results as PR comment |

---

## Linux Command Notes

| File | Topic |
|---|---|
| [Controlling system locale](Controlling%20system%20locale) | `localectl` usage |
| [Compiling software packages](Compiling%20software%20packages) | Build from source with `make` |
| [system timezone](system%20timezone) | `timedatectl` usage |
| [Working with package managers](Working%20with%20package%20managers) | `apt` and `yum` reference |
| [Working with LXD containers](Working%20with%20LXD%20containers) | `lxc` quick reference |
| [Launching Docker](Launching%20Docker) | Docker build and run reference |
| [Install and launch Apache](Install%20and%20launch%20Apache) | httpd install via yum |
| [Discover and mount a storage volume](Discover%20and%20mount%20a%20storage%20volume) | `lsblk`, `mount` reference |

---

## Known Issues

See the [Issues](https://github.com/vivs-ty/infra-ops-scripts/issues) tab for bugs and planned improvements.

### Open

| # | File | Issue |
|---|---|---|
| [#2](https://github.com/vivs-ty/infra-ops-scripts/issues/2) | `ssl_cert_check.sh` | `date -d` not compatible with macOS/BSD |
| [#3](https://github.com/vivs-ty/infra-ops-scripts/issues/3) | `backup.sh` | Add remote backup via rsync over SSH |
| [#4](https://github.com/vivs-ty/infra-ops-scripts/issues/4) | `docker_health_check.sh` | No re-verification after auto-restart |
| [#5](https://github.com/vivs-ty/infra-ops-scripts/issues/5) | `playbook_patch_os.yml` | Add pre-patch snapshot for rollback |
| [#6](https://github.com/vivs-ty/infra-ops-scripts/issues/6) | `log_rotate.sh` | `maxdepth` misses deeply nested log directories |
| [#8](https://github.com/vivs-ty/infra-ops-scripts/issues/8) | `windows_update_status.ps1` | WUA COM object fails on WSUS-configured servers |

### Fixed

| # | File | Fix |
|---|---|---|
| [#1](https://github.com/vivs-ty/infra-ops-scripts/issues/1) | `cpu_memory_monitor.sh` | Added `-d`/`--disk-threshold` flag and per-mount disk alerting |
| [#12](https://github.com/vivs-ty/infra-ops-scripts/issues/12) | `terraform-plan.yml` | Added `workflow_dispatch`, path validation, `try/catch` on plan output, artifact upload |
| [#13](https://github.com/vivs-ty/infra-ops-scripts/issues/13) | `terraform-apply.yml` | Added `concurrency` block to queue parallel runs; moved context expressions out of inline JS |
| [#14](https://github.com/vivs-ty/infra-ops-scripts/issues/14) | `ansible-lint.yml` | Replaced hardcoded playbook list with dynamic `find` discovery |
| [#15](https://github.com/vivs-ty/infra-ops-scripts/issues/15) | `ansible-lint.yml` | Pinned `ansible-lint==24.2.3` and `ansible-core==2.17.9` |
