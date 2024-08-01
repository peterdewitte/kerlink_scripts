#!/bin/bash


# According https://docs.kerlink.com/en/lora/edge-computing 29/07/2024

## Step one: Install and configure Chirpstack LNS
### Add Chirpstack repository

cat > chirpstack_4.list << EOF
deb https://artifacts.chirpstack.io/packages/4.x/deb stable main
EOF

mv chirpstack_4.list /etc/apt/sources.list.d/

curl -s "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x1ce2afd36dbcca00" | gpg --dearmor -o /etc/apt/trusted.gpg.d/chirpstack_4.gpg

cat > 50-chirpstack-mqtt-forwarder << EOF
Package: chirpstack-mqtt-forwarder
Pin: origin artifacts.chirpstack.io
Pin-Priority: -1
EOF

mv 50-chirpstack-mqtt-forwarder /etc/apt/preferences.d/

apt update


### Install Chirpstack LNS

apt install chirpstack postgresql postgresql-client \
  postgresql-contrib mosquitto mosquitto-clients redis zram
printf "\n[gateway]\n  allow_unknown_gateways=true\n" | tee -a /etc/chirpstack/chirpstack.toml


### Setup postgresql database for Chirpstack LNS

su -l postgres -c "/usr/bin/initdb --pgdata='/var/lib/postgresql/data' --auth='trust'"
systemctl enable postgresql --now
su - postgres -c "psql -c \" create role chirpstack with login password 'chirpstack' \" "
su - postgres -c "psql -c \" create database chirpstack with owner chirpstack \" "
su - postgres -c "psql -d chirpstack -c \" create extension pg_trgm \" "
systemctl enable chirpstack --now
sleep 2
su - postgres -c "psql -d chirpstack -c \"insert into gateway (gateway_id, tenant_id, created_at, updated_at, last_seen_at, name, description, latitude, longitude, altitude, stats_interval_secs, tls_certificate, tags, properties) values (bytea '\x$EUI64', (select id from tenant limit 1), now(), now(), null, 'local gateway', 'self', 0.0, 0.0, 0.0, 30, null, '{}', '{}')\" "


### Configure firewall rules to access to the LNS management interface

cat > chirpstack.rules << EOF
*filter
-A INPUT -p tcp --dport http-alt -j ACCEPT
COMMIT
EOF
mv chirpstack.rules /etc/iptables/iptables.d/
systemctl restart iptables


### Install the LoRaWAN forwarder


apt update
apt install chirpstack-mqtt-forwarder

# Adapt LEADER_IP_ADDR to Hostname or IP of your leader gateway
# LEADER_IP_ADDR=myLeaderGW
# Adapt topic_prefix if needed (us915_0,as923,...)
cat > leader_config.toml << EOF
[mqtt]
topic_prefix = "eu868"
server = "${LEADER_IP_ADDR:=localhost}:1883"
EOF

conflex -t -o chirpstack-mqtt-forwarder.toml -T /usr/share/chirpstack-mqtt-forwarder/template.hb leader_config.toml
mv chirpstack-mqtt-forwarder.toml /etc/chirpstack-mqtt-forwarder/chirpstack-mqtt-forwarder.toml
systemctl enable chirpstack-mqtt-forwarder --now

mkdir -p /etc/mosquitto/conf.d/

echo "include_dir /etc/mosquitto/conf.d/" | tee -a /etc/mosquitto/mosquitto.conf

cat > local.conf << EOF
listener 1883 0.0.0.0
allow_anonymous true
EOF

mv local.conf /etc/mosquitto/conf.d/

systemctl enable mosquitto --now









