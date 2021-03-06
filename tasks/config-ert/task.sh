#!/bin/bash -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

CF_RELEASE=`om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k available-products | grep cf`

PRODUCT_NAME=`echo $CF_RELEASE | cut -d"|" -f2 | tr -d " "`
PRODUCT_VERSION=`echo $CF_RELEASE | cut -d"|" -f3 | tr -d " "`

om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k stage-product -p $PRODUCT_NAME -v $PRODUCT_VERSION

ERT_AZS=$(echo $DEPLOYMENT_NW_AZS | jq --raw-input 'split(",") | map({name: .})')

CF_NETWORK=$(cat <<-EOF
{
  "singleton_availability_zone": {
    "name": "$ERT_SINGLETON_JOB_AZ"
  },
  "other_availability_zones": $ERT_AZS,
  "network": {
    "name": "$NETWORK_NAME"
  }
}
EOF
)

if [[ -z "$SSL_CERT" ]]; then
DOMAINS=$(cat <<-EOF
  {"domains": ["*.$SYSTEM_DOMAIN", "*.$APPS_DOMAIN", "*.login.$SYSTEM_DOMAIN", "*.uaa.$SYSTEM_DOMAIN"] }
EOF
)

  CERTIFICATES=`om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k curl -p "$OPS_MGR_GENERATE_SSL_ENDPOINT" -x POST -d "$DOMAINS"`

  export SSL_CERT=`echo $CERTIFICATES | jq '.certificate'`
  export SSL_PRIVATE_KEY=`echo $CERTIFICATES | jq '.key'`

  echo "Using self signed certificates generated using Ops Manager..."

fi

source $SCRIPT_DIR/load_cf_properties.sh

CF_RESOURCES=$(cat <<-EOF
{
  "consul_server": {
    "instance_type": {"id": "automatic"},
    "instances" : $CONSUL_SERVER_INSTANCES
  },
  "nats": {
    "instance_type": {"id": "automatic"},
    "instances" : $NATS_INSTANCES
  },
  "etcd_tls_server": {
    "instance_type": {"id": "automatic"},
    "instances" : $ETCD_TLS_SERVER_INSTANCES
  },
  "nfs_server": {
    "instance_type": {"id": "automatic"},
    "instances" : $NFS_SERVER_INSTANCES
  },
  "mysql_proxy": {
    "instance_type": {"id": "automatic"},
    "instances" : $MYSQL_PROXY_INSTANCES
  },
  "mysql": {
    "instance_type": {"id": "automatic"},
    "instances" : $MYSQL_INSTANCES
  },
  "backup-prepare": {
    "instance_type": {"id": "automatic"},
    "instances" : $BACKUP_PREPARE_INSTANCES
  },
  "ccdb": {
    "instance_type": {"id": "automatic"},
    "instances" : $CCDB_INSTANCES
  },
  "uaadb": {
    "instance_type": {"id": "automatic"},
    "instances" : $UAADB_INSTANCES
  },
  "uaa": {
    "instance_type": {"id": "automatic"},
    "instances" : $UAA_INSTANCES
  },
  "cloud_controller": {
    "instance_type": {"id": "automatic"},
    "instances" : $CLOUD_CONTROLLER_INSTANCES
  },
  "ha_proxy": {
    "instance_type": {"id": "automatic"},
    "instances" : $HA_PROXY_INSTANCES
  },
  "router": {
    "instance_type": {"id": "automatic"},
    "instances" : $ROUTER_INSTANCES
  },
  "mysql_monitor": {
    "instance_type": {"id": "automatic"},
    "instances" : $MYSQL_MONITOR_INSTANCES
  },
  "clock_global": {
    "instance_type": {"id": "automatic"},
    "instances" : $CLOCK_GLOBAL_INSTANCES
  },
  "cloud_controller_worker": {
    "instance_type": {"id": "automatic"},
    "instances" : $CLOUD_CONTROLLER_WORKER_INSTANCES
  },
  "diego_database": {
    "instance_type": {"id": "automatic"},
    "instances" : $DIEGO_DATABASE_INSTANCES
  },
  "diego_brain": {
    "instance_type": {"id": "automatic"},
    "instances" : $DIEGO_BRAIN_INSTANCES
  },
  "diego_cell": {
    "instance_type": {"id": "automatic"},
    "instances" : $DIEGO_CELL_INSTANCES
  },
  "doppler": {
    "instance_type": {"id": "automatic"},
    "instances" : $DOPPLER_INSTANCES
  },
  "loggregator_trafficcontroller": {
    "instance_type": {"id": "automatic"},
    "instances" : $LOGGREGATOR_TC_INSTANCES
  },
  "tcp_router": {
    "instance_type": {"id": "automatic"},
    "instances" : $TCP_ROUTER_INSTANCES
  }
}
EOF
)

om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k configure-product -n cf -p "$CF_PROPERTIES" -pn "$CF_NETWORK" -pr "$CF_RESOURCES"

if [[ "$AUTHENTICATION_MODE" == "internal" ]]; then
echo "Configuring Internal Authentication in ERT..."
CF_AUTH_PROPERTIES=$(cat <<-EOF
{
  ".properties.uaa": {
    "value": "$AUTHENTICATION_MODE"
  },
  ".uaa.service_provider_key_credentials": {
        "value": {
          "cert_pem": "",
          "private_key_pem": ""
        }
  }
}
EOF
)

elif [[ "$AUTHENTICATION_MODE" == "ldap" ]]; then
echo "Configuring LDAP Authentication in ERT..."
CF_AUTH_PROPERTIES=$(cat <<-EOF
{
  ".properties.uaa": {
    "value": "ldap"
  },
  ".properties.uaa.ldap.url": {
    "value": "$LDAP_URL"
  },
  ".properties.uaa.ldap.credentials": {
    "value": {
      "identity": "$LDAP_USER",
      "password": "$LDAP_PWD"
    }
  },
  ".properties.uaa.ldap.search_base": {
    "value": "$SEARCH_BASE"
  },
  ".properties.uaa.ldap.search_filter": {
    "value": "$SEARCH_FILTER"
  },
  ".properties.uaa.ldap.group_search_base": {
    "value": "$GROUP_SEARCH_BASE"
  },
  ".properties.uaa.ldap.group_search_filter": {
    "value": "$GROUP_SEARCH_FILTER"
  },
  ".properties.uaa.ldap.mail_attribute_name": {
    "value": "$MAIL_ATTR_NAME"
  },
  ".properties.uaa.ldap.first_name_attribute": {
    "value": "$FIRST_NAME_ATTR"
  },
  ".properties.uaa.ldap.last_name_attribute": {
    "value": "$LAST_NAME_ATTR"
  },
  ".uaa.service_provider_key_credentials": {
        "value": {
          "cert_pem": "",
          "private_key_pem": ""
        }
  }  
}
EOF
)

fi

saml_cert_domains=$(cat <<-EOF
  {"domains": ["*.$SYSTEM_DOMAIN", "*.login.$SYSTEM_DOMAIN", "*.uaa.$SYSTEM_DOMAIN"] }
EOF
)

saml_cert_response=`om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k curl -p "$OPS_MGR_GENERATE_SSL_ENDPOINT" -x POST -d "$saml_cert_domains"`

saml_cert_pem=$(echo $saml_cert_response | jq --raw-output '.certificate')
saml_key_pem=$(echo $saml_cert_response | jq --raw-output '.key')

cat > saml_auth_filters <<'EOF'
.".uaa.service_provider_key_credentials".value = {
  "cert_pem": $saml_cert_pem,
  "private_key_pem": $saml_key_pem
}
EOF

CF_AUTH_WITH_SAML_CERTS=$(echo $CF_AUTH_PROPERTIES | jq \
  --arg saml_cert_pem "$saml_cert_pem" \
  --arg saml_key_pem "$saml_key_pem" \
  --from-file saml_auth_filters \
  --raw-output)


om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k configure-product -n cf -p "$CF_AUTH_WITH_SAML_CERTS"

if [[ ! -z "$SYSLOG_HOST" ]]; then

echo "Configuring Syslog in ERT..."

CF_SYSLOG_PROPERTIES=$(cat <<-EOF
{
  ".doppler.message_drain_buffer_size": {
    "value": $SYSLOG_DRAIN_BUFFER_SIZE
  },
  ".cloud_controller.security_event_logging_enabled": {
    "value": $ENABLE_SECURITY_EVENT_LOGGING
  },
  ".properties.syslog_host": {
    "value": "$SYSLOG_HOST"
  },
  ".properties.syslog_port": {
    "value": "$SYSLOG_PORT"
  },
  ".properties.syslog_protocol": {
    "value": "$SYSLOG_PROTOCOL"
  }
}
EOF
)

om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k configure-product -n cf -p "$CF_SYSLOG_PROPERTIES"

fi

if [[ ! -z "$SMTP_ADDRESS" ]]; then

echo "Configuraing SMTP in ERT..."

CF_SMTP_PROPERTIES=$(cat <<-EOF
{
  ".properties.smtp_from": {
    "value": "$SMTP_FROM"
  },
  ".properties.smtp_address": {
    "value": "$SMTP_ADDRESS"
  },
  ".properties.smtp_port": {
    "value": "$SMTP_PORT"
  },
  ".properties.smtp_credentials": {
    "value": {
      "identity": "$SMTP_USER",
      "password": "$SMTP_PWD"
    }
  },
  ".properties.smtp_enable_starttls_auto": {
    "value": true
  },
  ".properties.smtp_auth_mechanism": {
    "value": "$SMTP_AUTH_MECHANISM"
  }
}
EOF
)

om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k configure-product -n cf -p "$CF_SMTP_PROPERTIES"

fi

if [[ "$SSL_TERMINATION" == "haproxy" ]]; then

echo "Terminating SSL on HAProxy"
CF_SSL_TERM_PROPERTIES=$(cat <<-EOF
{
  ".properties.networking_point_of_entry": {
    "value": "haproxy"
  },
  ".properties.networking_point_of_entry.haproxy.ssl_rsa_certificate": {
    "value": {
      "cert_pem": $SSL_CERT,
      "private_key_pem": $SSL_PRIVATE_KEY
    }
  }
}
EOF
)

elif [[ "$SSL_TERMINATION" == "external_ssl" ]]; then
echo "Terminating SSL on GoRouters"

CF_SSL_TERM_PROPERTIES=$(cat <<-EOF
{
  ".properties.networking_point_of_entry": {
    "value": "external_ssl"
  },
  ".properties.networking_point_of_entry.external_ssl.ssl_rsa_certificate": {
    "value": {
      "cert_pem": $SSL_CERT,
      "private_key_pem": $SSL_PRIVATE_KEY
    }
  }
}
EOF
)

elif [[ "$SSL_TERMINATION" == "external_non_ssl" ]]; then
echo "Terminating SSL on Load Balancers"
CF_SSL_TERM_PROPERTIES=$(cat <<-EOF
{
  ".properties.networking_point_of_entry": {
    "value": "external_non_ssl"
  }
}
EOF
)

fi

om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k configure-product -n cf -p "$CF_SSL_TERM_PROPERTIES"

if [[ -z "$ERRANDS_TO_DISABLE" ]] || [[ "$ERRANDS_TO_DISABLE" == "none" ]]; then
  echo "No post-deploy errands to disable"
else
  enabled_errands=$(
  $CMD -t https://${OPS_MGR_HOST} -u $OPS_MGR_USR -p $OPS_MGR_PWD -k errands --product-name $PRODUCT_NAME |
  tail -n+4 | head -n-1 | grep -v false | cut -d'|' -f2 | tr -d ' '
  )
  if [[ "$ERRANDS_TO_DISABLE" == "all" ]]; then
    errands_to_disable="${enabled_errands[@]}"
  else
    errands_to_disable=$(echo "$ERRANDS_TO_DISABLE" | tr ',' '\n')
  fi
  
  will_disable=$(for i in $enabled_errands; do
      for j in $errands_to_disable; do
        if [ $i == $j ]; then
          echo $j
        fi
      done
    done
  )

  if [ -z "$will_disable" ]; then
    echo "All errands are already disable that were requested"
  else
    while read errand; do
      echo -n Disabling $errand...
      $CMD -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k set-errand-state --product-name $PRODUCT_NAME --errand-name $errand --post-deploy-state "disabled"
      echo done
    done < <(echo "$will_disable")
  fi
fi

if [[ -z "$ERRANDS_TO_WHENCHANGED" ]] || [[ "$ERRANDS_TO_WHENCHANGED" == "none" ]]; then
  echo "No post-deploy errands to set to when-changed"
else
  enabled_errands=$(
  $CMD -t https://${OPS_MGR_HOST} -u $OPS_MGR_USR -p $OPS_MGR_PWD -k errands --product-name $PRODUCT_NAME |
  tail -n+4 | head -n-1 | grep -v false | cut -d'|' -f2 | tr -d ' '
  )
  if [[ "$ERRANDS_TO_WHENCHANGED" == "all" ]]; then
    errands_to_whenchanged="${enabled_errands[@]}"
  else
    errands_to_whenchanged=$(echo "$ERRANDS_TO_WHENCHANGED" | tr ',' '\n')
  fi
  
  will_whenchanged=$(for i in $enabled_errands; do
      for j in $errands_to_whenchanged; do
        if [ $i == $j ]; then
          echo $j
        fi
      done
    done
  )

  if [ -z "$will_whenchanged" ]; then
    echo "All errands are already set to when changed that were requested"
  else
    while read errand; do
      echo -n Disabling $errand...
      $CMD -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k set-errand-state --product-name $PRODUCT_NAME --errand-name $errand --post-deploy-state "when-changed"
      echo done
    done < <(echo "$will_whenchanged")
  fi
fi

if [[ -z "$PREDELETE_ERRANDS_TO_DISABLE" ]] || [[ "$PREDELETE_ERRANDS_TO_DISABLE" == "none" ]]; then
  echo "No pre-delete errands to disable"
else
  enabled_errands=$(
  $CMD -t https://${OPS_MGR_HOST} -u $OPS_MGR_USR -p $OPS_MGR_PWD -k errands --product-name $PRODUCT_NAME |
  tail -n+4 | head -n-1 | grep -v false | cut -d'|' -f2 | tr -d ' '
  )
  if [[ "$PREDELETE_ERRANDS_TO_DISABLE" == "all" ]]; then
    errands_to_disable="${enabled_errands[@]}"
  else
    errands_to_disable=$(echo "$PREDELETE_ERRANDS_TO_DISABLE" | tr ',' '\n')
  fi
  
  will_disable=$(for i in $enabled_errands; do
      for j in $errands_to_disable; do
        if [ $i == $j ]; then
          echo $j
        fi
      done
    done
  )

  if [ -z "$will_disable" ]; then
    echo "All errands are already disable that were requested"
  else
    while read errand; do
      echo -n Disabling $errand...
      $CMD -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k set-errand-state --product-name $PRODUCT_NAME --errand-name $errand --pre-delete-state "disabled"
      echo done
    done < <(echo "$will_disable")
  fi
fi
