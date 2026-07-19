# Domains

|                    | To      | Description       |
| ------------------ | ------- | ----------------- |
| www.deanqx.com     | Cluster | Blog              |
| cloud.deanqx.com   | Cluster | Nextcloud         |
| monitor.deanqx.com | Cluster | Grafana Dashboard |
| home.deanqx.com    | Offsite | Home Assistant    |
| backup.deanqx.com  | Offsite | Backup (S3)       |

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

| from Port | forward to IP | Description   |
| --------- | ------------- | ------------- |
| 80        | Load Balancer | HTTP          |
| 443       | Load Balancer | HTTPS         |
| 3901      | Load Balancer | Garage S3 RPC |

# (b) Offsite Location

Hosts Backup storage and Home Assistant
## VLAN 10.101.2.0/29

| 10.101.2.0/29 | Name           |
| ------------- | -------------- |
| 10.101.2.0    | (Network)      |
| 10.101.2.1    | b-backup-01    |
| 10.101.2.2    | Home Assistant |
| 10.101.2.3    |                |
| 10.101.2.4    |                |
| 10.101.2.5    |                |
| 10.101.2.6    |                |
| 10.101.2.7    | (Broadcast)    |

| from Port | forward to IP | Description   |
| --------- | ------------- | ------------- |
| 80        | b-backup-01   | HTTP          |
| 443       | b-backup-01   | HTTPS         |
| 3901      | b-backup-01   | Garage S3 RPC |
