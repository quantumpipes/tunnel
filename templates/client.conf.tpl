[Interface]
PrivateKey = ${CLIENT_PRIVATE_KEY}
Address = ${CLIENT_TUNNEL_IP}/32
DNS = ${TUNNEL_DNS_SERVER}

[Peer]
PublicKey = ${RELAY_PUBLIC_KEY}
PresharedKey = ${PRESHARED_KEY}
Endpoint = ${RELAY_ENDPOINT}
AllowedIPs = ${TUNNEL_ALLOWED_IPS}
PersistentKeepalive = 25
