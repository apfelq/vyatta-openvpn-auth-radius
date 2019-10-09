#!/bin/bash
set -e

# all credit goes to Mathias Fredriksson
# https://github.com/mafredri/vyatta-wireguard-installer

declare -A SUPPORTED_BOARDS
SUPPORTED_BOARDS=(
	#[e50]=e50 # ER-X (EdgeRouter X)
	#[e51]=e50 # ER-X-SFP (Edgerouter X SFP)
	#[e101]=e100 # ERLite-3 (EdgeRouter Lite 3-Port)
	#[e102]=e100 # ERPoe-5 (EdgeRouter PoE 5-Port)
	#[e200]=e200 # EdgeRouter Pro 8-Port
	#[e201]=e200 # EdgeRouter 8-Port
	#[e300]=e300 # ER-4 (EdgeRouter 4)
	#[e301]=e300 # ER-6P (EdgeRouter 6P)
	#[e1000]=e1000 # USG-XG (EdgeRouter Infinity)
	[e120]=mips # USG (UniFi-Gateway-3)
	[e221]=mips # USG-PRO-4 (UniFi-Gateway-4)
	[e1020]=mips # USG‑XG‑8 (UniFi Security Gateway XG)
)

OPENVPN_DIR=/config/user-data/openvpn
CACHE_DIR=$OPENVPN_DIR/cache

config() {
	/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper "$@"
}

current_version() {
	dpkg-query --showformat=\$\{Version\} --show openvpn-auth-radius 2>/dev/null
}

is_installed() {
	current_version >/dev/null
}

latest_release_for() {
	local board=$1

	# Fetch the latest release, sorted by created_at attribute since this is
	# how GitHub operates for the /releases/latest end-point. We would use
	# it, but it does not contain pre-releases.
	#
	# From the GitHub API documentation:
	# > The created_at attribute is the date of the commit used for the
	# > release, and not the date when the release was drafted or published.
	curl -sSL https://api.github.com/repos/apfelq/vyatta-openvpn-auth-radius/releases \
		| jq -r --arg version "openvpn-auth-radius-${board}" \
			'sort_by(.created_at) | reverse | .[0].assets | map(select(.name | contains($version))) | .[0] | {name: .name, url: .browser_download_url}'
}

disable_openvpn() {
	echo "Deleting OpenVPN interfaces..."
	config delete interfaces openvpn
	config commit
	config end
}

reload_config() {
	echo "Reloading configuration..."
	config begin
	config load
	config commit
	config end
}

install() {
	local name package

	if [[ $* =~ --no-cache ]] || ! [[ -f $CACHE_DIR/latest ]]; then
		upgrade "$@"
		return $?
	fi

	name=$(<$CACHE_DIR/latest)
	package=$CACHE_DIR/$name

	echo "Installing ${name}..."
	sudo dpkg -i "$package"

	mkdir -p $OPENVPN_DIR
	chmod g+w $OPENVPN_DIR
	echo "$name" >$OPENVPN_DIR/installed

	reload_config
}

upgrade() {
	local asset_data name url package version update_cache=1 skip_install=0

	if [[ $* =~ --no-cache ]]; then
		update_cache=0
	fi

	echo "Checking latest release for ${BOARD}..."
	asset_data=$(latest_release_for "$BOARD")
	name=$(jq -r .name <<<"$asset_data")
	url=$(jq -r .url <<<"$asset_data")
	package=/tmp/$name

	# Use simple version parsing based on name so that we
	# can avoid downloading the deb for the version check.
	version=${name#openvpn-auth-radius-${BOARD}-}
	version=${version%.deb}

	if [[ $version == $(current_version) ]]; then
		# Avoid exiting if the cache is missing and we should update it.
		if ((update_cache)) && ! [[ -f $CACHE_DIR/latest ]]; then
			echo "OpenVPN-Auth-RADIUS is already up to date ($(current_version)) but the cache is missing, continuing."
			skip_install=1
		else
			echo "OpenVPN-Auth-RADIUS is already up to date ($(current_version)), nothing to do."
			exit 1
		fi
	fi

	echo "Downloading ${name}..."
	curl -sSL "$url" -o "$package"

	if ((skip_install)); then
		echo "Skipping installation..."
	else
		if is_installed; then
			# Delay until _after_ we have successfully
			# downloaded the latest release.
			disable_openvpn
		fi

		echo "Installing ${name}..."
		sudo dpkg -i "$package"
	fi

	mkdir -p $OPENVPN_DIR
	chmod g+w $OPENVPN_DIR
	echo "$name" >$OPENVPN_DIR/installed

	if ((update_cache)); then
		# Ensure cache directory exists.
		mkdir -p $CACHE_DIR
		chmod g+w $CACHE_DIR

		echo "Purging previous cache..."
		rm -fv $CACHE_DIR/*.deb
		echo "Caching installer to ${CACHE_DIR}..."
		cp -v "$package" $CACHE_DIR/"$name"

		echo "$name" >$CACHE_DIR/latest
	fi

	rm -f "$package"

	if ((!skip_install)); then
		reload_config
	fi
}

run_install() {
	if is_installed; then
		echo "OpenVPN-Auth-RADIUS is already installed ($(current_version)), nothing to do."
		exit 0
	fi

	echo "Installing OpenVPN-Auth-RADIUS..."
	install "$@"
	echo "Install complete!"
}

run_upgrade() {
	if ! is_installed; then
		echo "OpenVPN-Auth-RADIUS is not installed, please run install first."
		exit 1
	fi

	echo "Upgrading OpenVPN-Auth-RADIUS..."
	upgrade "$@"
	echo "Upgrade complete!"
}

run_remove() {
	if ! is_installed; then
		echo "OpenVPN-Auth-RADIUS is not installed, nothing to do."
		exit 0
	fi

	echo "Removing OpenVPN-Auth-RADIUS..."
	
	disable_openvpn

	# Prevent automatic installation.
	rm -f $OPENVPN_DIR/installed

	echo "Purging package..."
	sudo dpkg --purge openvpn-auth-radius

	echo "OpenVPN-Auth-RADIUS removed!"
}

run_self_update() {
	tmpdir=$(mktemp -d)
	cat <<-EOS >"$tmpdir"/openvpn-auth-radius-script-self-update.sh
		#!/bin/bash
		set -e

		OLD_SCRIPT="${BASH_SOURCE[0]}"
		NEW_SCRIPT="$tmpdir"/openvpn-auth-radius-latest.sh

		echo "Downloading script..."
		curl -sSL https://github.com/apfelq/vyatta-openvpn-auth-radius/raw/master/openvpn-auth-radius.sh -o \$NEW_SCRIPT

		echo "Checking for changes..."
		echo
		if ! diff -u "\$OLD_SCRIPT" "\$NEW_SCRIPT"; then
			echo
			read -p "Use updated script (Y/n)? " update
			if [[ -z \$update ]] || [[ \$update =~ [yY] ]]; then
				cat "\$NEW_SCRIPT" >"\$OLD_SCRIPT"
				echo "Script updated!"
			else
				echo "Aborting update..."
			fi
		else
			echo "Script is already up to date, nothing to do."
		fi
		rm -rfv "${tmpdir}"
		exit 0
	EOS

	chmod +x "$tmpdir"/openvpn-auth-radius-script-self-update.sh
	exec "$tmpdir"/openvpn-auth-radius-script-self-update.sh
}

usage() {
	cat <<EOU 1>&2
Install, upgrade or remove OpenVPN-RoadWarrior on Ubiquiti hardware.
By default, the installer caches the deb-package so that the same
version of OpenVPN can be restored after a firmware upgrade.

Note: This script can be placed in /config/scripts/post-config.d for
automatic installation after firmware upgrades.

Usage:
  $0 [COMMAND] [OPTION]...

Commands:
  install      Install the latest version of OpenVPN-Auth-RADIUS
  upgrade      Upgrade OpenVPN-Auth-RADIUS to the latest version
  remove       Remove OpenVPN-Auth-RADIUS
  self-update  Fetch the latest version of this script
  help         Show this help

Options:
      --no-cache  Disable package caching, cache is used during (re)install

EOU
}

BOARD_ID="$(/usr/sbin/ubnt-hal-e getBoardIdE)"
BOARD=${SUPPORTED_BOARDS[$BOARD_ID]}

if [[ -z $BOARD ]]; then
	echo "Unsupported board ${BOARD_ID}, aborting."
	exit 1
fi

case $1 in
	-h | --help | help)
		usage
		;;
	install)
		run_install "$@"
		;;
	upgrade)
		run_upgrade "$@"
		;;
	remove)
		run_remove "$@"
		;;
	self-update)
		run_self_update "$@"
		;;
	*)
		# Perform install if we're running as part of post-config.d and
		# OpenVPN-Auth-RADIUS is supposed to be installed. (BOOTFILE is
		# declared in /etc/init.d/vyatta-router.)
		# Alternatively, we could check $CONSOLE == /dev/console.
		if [[ $BOOTFILE == /config/config.boot ]] && [[ -f $OPENVPN_DIR/installed ]]; then
			run_install
			exit 0
		fi

		usage
		exit 1
		;;
esac

exit 0
