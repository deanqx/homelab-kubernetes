#!/bin/bash

if [ "$#" = 0 ]; then
    echo "Overwrite current secrets with newly generated ones and encrypt them."
    echo
    echo "Usage: generate_secrets.sh [TARGET]"
    echo
    echo "Targets:"
    echo "    all"
    echo "    monitoring_grafana"
    echo "    monitoring_s3"
    echo "    nextcloud_admin"
    echo "    nextcloud_postgresql"
    echo "    nextcloud_redis"
    exit 1
fi

function monitoring_grafana {
    echo "Generating secret for monitoring_grafana"

    password=$(pwgen -sBcn 25 1)

    echo "username: admin"
    echo "password: $password"

    kubectl -n default create secret generic grafana \
    --namespace=monitoring \
    --from-literal=username=admin \
    --from-literal=password=$password \
    --dry-run=client \
    -o yaml > monitoring/production/grafana-secret.yaml

    sops --encrypt --in-place monitoring/production/grafana-secret.yaml
}

function monitoring_s3 {
    echo "Generating secret for monitoring_s3"

    admin_access_key_id=admin$(pwgen -sBcn 10 1)
    admin_secret_access_key=$(pwgen -sBcn 25 1)
    read_access_key_id=read$(pwgen -sBcn 10 1)
    read_secret_access_key=$(pwgen -sBcn 25 1)

    seaweedfs_s3_config=$(jq -n \
    --arg a_id "$admin_access_key_id" \
    --arg a_sec "$admin_secret_access_key" \
    --arg r_id "$read_access_key_id" \
    --arg r_sec "$read_secret_access_key" \
    '-c' '{
      identities: [
        {
          name: "anvAdmin",
          credentials: [{ accessKey: $a_id, secretKey: $a_sec }],
          actions: ["Admin", "Read", "Write"]
        },
        {
          name: "anvReadOnly",
          credentials: [{ accessKey: $r_id, secretKey: $r_sec }],
          actions: ["Read"]
        }
      ]
    }')

    echo "admin_access_key_id: $admin_access_key_id"
    echo "admin_secret_access_key: $admin_secret_access_key"
    echo "read_access_key_id: $read_access_key_id"
    echo "read_secret_access_key: $read_secret_access_key"
    # echo "seaweedfs_s3_config: $(echo $seaweedfs_s3_config | jq)"
    while true; do
        echo    "Do you want to store the credentials in"
        read -p "the Minio CLI as \"homelab_monitoring\"? (y/N): " store_in_mcli
        case $store_in_mcli in
        [Yy]* )
            mcli alias set homelab_monitoring http://localhost:8333 \
                $admin_access_key_id $admin_secret_access_key \
                --api "s3v4"
            break;;
        [Nn]* )
            echo "Skipping Minio CLI"
            break;;
        * )
            echo "Please answer yes or no."
            ;;
        esac
    done
    echo

    kubectl -n default create secret generic seaweedfs-s3-secret \
    --namespace=monitoring \
    --from-literal=admin_access_key_id=$admin_access_key_id \
    --from-literal=admin_secret_access_key=$admin_secret_access_key \
    --from-literal=read_access_key_id=$read_access_key_id \
    --from-literal=read_secret_access_key=$read_secret_access_key \
    --from-literal=seaweedfs_s3_config=$seaweedfs_s3_config \
    --dry-run=client \
    -o yaml > monitoring/production/seaweedfs-s3-secret.yaml

    sops --encrypt --in-place monitoring/production/seaweedfs-s3-secret.yaml
}

function nextcloud_admin {
    echo "Generating secret for nextcloud_admin"

    password=$(pwgen -sBcn 25 1)

    echo "username: admin"
    echo "password: $password"
    echo

    kubectl -n default create secret generic nextcloud \
    --namespace=nextcloud \
    --from-literal=username=admin \
    --from-literal=password=$password \
    --dry-run=client \
    -o yaml > apps/production/nextcloud/app/secret.yaml

    sops --encrypt --in-place apps/production/nextcloud/app/secret.yaml
}

function nextcloud_postgresql {
    echo "Generating secret for nextcloud_postgresql"

    admin_password=$(pwgen -sBcn 25 1)
    user_password=$(pwgen -sBcn 25 1)
    replication_password=$(pwgen -sBcn 25 1)
    metrics_password=$(pwgen -sBcn 25 1)

    echo "username: nextcloud"
    echo "admin-password: $admin_password"
    echo "user-password: $user_password"
    echo "replication-password: $replication_password"
    echo "metrics-password: $metrics_password"
    echo

    kubectl -n default create secret generic postgresql \
    --namespace=nextcloud \
    --from-literal=username=nextcloud \
    --from-literal=admin-password=$admin_password \
    --from-literal=user-password=$user_password \
    --from-literal=replication-password=$replication_password \
    --from-literal=metrics-password=$metrics_password \
    --dry-run=client \
    -o yaml > apps/production/nextcloud/database/postgresql-secret.yaml

    sops --encrypt --in-place apps/production/nextcloud/database/postgresql-secret.yaml
}

function nextcloud_redis {
    echo "Generating secret for nextcloud_redis"

    redis_password=$(pwgen -sBcn 25 1)

    echo "redis-password: $redis_password"
    echo

    kubectl -n default create secret generic redis \
    --namespace=nextcloud \
    --from-literal=redis-password=$redis_password \
    --dry-run=client \
    -o yaml > apps/production/nextcloud/database/redis-secret.yaml

    sops --encrypt --in-place apps/production/nextcloud/database/redis-secret.yaml
}

function all {
    echo "Generating secret for all"
    monitoring_grafana
    monitoring_s3
    nextcloud_admin
    nextcloud_postgresql
    nextcloud_redis
}

for target in "$@"; do
    if [ "$target" = "all" ]; then
        all
    elif [ "$target" = "monitoring_grafana" ]; then
        monitoring_grafana
    elif [ "$target" = "monitoring_s3" ]; then
        monitoring_s3
    elif [ "$target" = "nextcloud_admin" ]; then
        nextcloud_admin
    elif [ "$target" = "nextcloud_postgresql" ]; then
        nextcloud_postgresql
    elif [ "$target" = "nextcloud_redis" ]; then
        nextcloud_redis
    else
        echo "Unknown target: \"$target\""
        echo "Quitting"
        exit 1
    fi

    echo "Verify the changes: git status"
done
