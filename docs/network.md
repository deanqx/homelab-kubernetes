# Domains

|                    | To      | Description       |
| ------------------ | ------- | ----------------- |
| www.deanqx.com     | Cluster | Blog              |
| cloud.deanqx.com   | Cluster | Nextcloud         |
| monitor.deanqx.com | Cluster | Grafana Dashboard |
| home.deanqx.com    | Offsite | Home Assistant    |
| backup.deanqx.com  | Offsite | Backup (S3)       |
# Global

| from Port | forward to IP | Description   |
| --------- | ------------- | ------------- |
| 80        | Load Balancer | HTTP          |
| 443       | Load Balancer | HTTPS         |
| 3901      | Load Balancer | Garage S3 RPC |

# (a) Cluster Location

Hosts Kubernetes Cluster
## VLAN 10.101.2.0/29

| 10.101.2.0/29 | Name                          |
| ------------- | ----------------------------- |
| 10.101.2.0    | (Network)                     |
| 10.101.2.1    | Load Balancer (Traffic entry) |
| 10.101.2.2    | a-master-01                   |
| 10.101.2.3    | a-worker-01                   |
| 10.101.2.4    | a-worker-02                   |
| 10.101.2.5    |                               |
| 10.101.2.6    |                               |
| 10.101.2.7    | (Broadcast)                   |

# (b) Offsite Location

Hosts Backup storage and Home Assistant
## VLAN 10.101.2.0/28

### Dev Subnet

| 10.101.2.0/29 | Name      |
| ------------- | --------- |
| 10.101.2.0    | (Network) |
| 10.101.2.1    | Reserved  |
| 10.101.2.2    | Reserved  |
| 10.101.2.3    |           |
| 10.101.2.4    |           |
| 10.101.2.5    |           |
| 10.101.2.6    | Reserved  |
| 10.101.2.7    | Reserved  |
### Server Range

| 10.101.2.8/29 | Name                          |
| ------------- | ----------------------------- |
| 10.101.2.8    | Load Balancer (Traffic entry) |
| 10.101.2.9    | b-backup-01                   |
| 10.101.2.10   | Home Assistant                |
| 10.101.2.11   |                               |
| 10.101.2.12   |                               |
| 10.101.2.13   |                               |
| 10.101.2.14   |                               |
| 10.101.2.15   | (Broadcast)                   |
