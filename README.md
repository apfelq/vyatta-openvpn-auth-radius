# Vyatta-OpenVPN-Auth-Radius

Install, upgrade or remove OpenVPN-Radius-Auth ([Debian/openvpn-auth-radius](http://archive.debian.org/debian/pool/main/o/openvpn-auth-radius/)) on Ubiquiti hardware. By default, the installer caches the deb-package so that the same version of OpenVPN-Radius-Auth can be restored after a firmware upgrade.

The script is based on the work of Mathias Fredriksson ([mafredri/vyatta-wireguard-installer](https://github.com/mafredri/vyatta-wireguard-installer/)).

The package was provided by the [Debian](https://www.debian.org/) community.

## Installation

Simply copy the script onto your Ubiquiti router and run it.

**Note:** By placing this script in `/config/scripts/post-config.d`, the OpenVPN-Auth-Radius installation will persist across firmware upgrades.

```console
curl -sSL https://github.com/apfelq/vyatta-openvpn-auth-radius/raw/master/openvpn-auth-radius.sh -o /config/scripts/post-config.d/openvpn-auth-radius.sh
chmod +x /config/scripts/post-config.d/openvpn-auth-radius.sh
```

## Usage

```console
$ ./openvpn-auth-radius.sh help
Install, upgrade or remove OpenVPN-Auth-Radius (github.com/apfelq/vyatta-openvpn-auth-radius)
on Ubiquiti hardware. By default, the installer caches the deb-package so that the
same version of OpenVPN-Auth-Radius can be restored after a firmware upgrade.

Note: This script can be placed in /config/scripts/post-config.d for automatic
installation after firmware upgrades.

Usage:
  ./openvpn-auth-radius.sh [COMMAND] [OPTION]...

Commands:
  install      Install the latest version of OpenVPN-Auth-Radius
  upgrade      Upgrade OpenVPN-Auth-Radius to the latest version
  remove       Remove OpenVPN-Auth-Radius
  self-update  Fetch the latest version of this script
  help         Show this help

Options:
      --no-cache  Disable package cache for this run, cache is used during (re)install
```

## Setup Road-Warrior OpenVPN

### Install Vyatta-OpenVPN-Auth-Radius

See above.

### Setup Client Configs

- Create client config dir:

```console
mkdir -p /config/user-data/openvpn/ccd
```

- Create client configs if needed (filename equals RADIUS username), e. g. a static IP:

```console
echo 'ifconfig-push 10.8.0.202 255.255.255.0' > /config/user-data/openvpn/ccd/<username>
```

### Configure OpenVPN-Server

- Minimal config needed by RADIUS plugin:

```
#/config/user-data/openvpn/server.conf
client-config-dir /config/user-data/openvpn/ccd
username-as-common-name
client-cert-not-required
status /var/run/openvpn/status/vtun0.status
```

### Configure Radius-Plugin

Adjust the following values to your environment:

- NAS-IP-Address (**Note:** Use a LAN IP address, when using the built-in RADIUS-server set to your default LAN IP address, `127.0.0.1` won't work!)
- name (**Note:** The address of your RADIUS-Server, when using the built-in RADIUS-server set to your default LAN IP address.)
- sharedsecret (**Note:** Use only alphanumeric characters `[A-Za-z0-9]` in RADIUS server secret!)

Optional:

- NAS-Identifier
- subnet
- acctport
- authport

```
#/config/user-data/openvpn/radiusplugin.cnf
NAS-Identifier=OpenVpn
Service-Type=5
Framed-Protocol=1
NAS-Port-Type=5
NAS-IP-Address=192.168.1.1
OpenVPNConfig=/config/user-data/openvpn/server.conf
subnet=255.255.255.0
overwriteccfiles=false
server
{
	acctport=1813
	authport=1812
	name=192.168.1.1
	retry=1
	wait=1
	sharedsecret=testing123
}
```

### Install Easy-RSA

```console
curl -LSs http://archive.debian.org/debian/pool/main/e/easy-rsa/easy-rsa_2.2.2-1_all.deb > /tmp/easy-rsa.deb
dpkg -i /tmp/easy-rsa.deb && rm /tmp/easy-rsa.deb
make-cadir /config/user-data/easy-rsa
```

### Create Certificates

```console
cd /config/user-data/easy-rsa
source ./vars
./clean-all
./build-ca
./build-key-server openvpn-server
./build-dh
```

- Generate `tls-auth` key

```bash
openvpn --genkey --secret /config/user-data/openvpn/ta.key
```

### Configure USG

- Check for existing remote user vpn networks: 

```console
mca-ctrl -t dump-cfg | jq -r '.firewall.group["network-group"].remote_user_vpn_network.network'
```

- Adapt the example [config.gateway.json](config.gateway.json.example):

    - if applicable merge with existing `config.gateway.json`
    - `interfaces > openvpn > vtun0 > openvpn-option`
    - `interfaces > openvpn > vtun0 > server > subnet`
    - `firewall > group > network-group > remote_user_vpn_network > network`

- Transfer to controller and appropriate site (`/srv/unifi/data/sites/<site>/`)

- Force provision USG in controller

### Create Client Profile

- Adapt the [client.ovpn](client.ovpn.example):

    - YOUR_SERVER (FQDN or IP address)
    - \<ca> (the content of `/config/user-data/eays-rsa/keys/ca.crt` generated above)
    - \<tls-auth> (the content of `/config/user-data/openvpn/ta.key` generated above)

- Import into your client and connect

## Monitoring & Troubleshooting

- Check config of USG

```
mca-ctrl -t dump-cfg
```

- Monitor VPN connections

```bash
show openvpn status server
```

- FreeRADIUS debugging

```bash
sudo service freeradius stop
sudo freeradius -fX

# end debugging with Ctrl-C
sudo service freeradius start
```

## Resources

- [VyOS Wiki: Configuration management](https://wiki.vyos.net/wiki/Configuration_management)
- [Lochnair/vyatta-wireguard#62: feature request: make wireguard sustain firmware updates](https://github.com/Lochnair/vyatta-wireguard/issues/62)
