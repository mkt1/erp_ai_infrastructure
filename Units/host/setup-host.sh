#!/bin/bash
################################################################################
# setup-host.sh — prepare a remote host for docker-based scenarios
#
# Runs on your own machine and works on the host via SSH.
# Part 1 (always): SSH access, operating system (Debian/Ubuntu), hostname, shell
#   aliases, Docker, additional packages.
# Part 2 (optional, project specific): every setup-host-*.sh next to this script is
#   sourced afterwards. Such an extension may use SSHCONFIG, HAS_SUDO, IS_DEBIAN,
#   SCRIPT_DIR, mark_failure, mark_warning and append to the TODOS array.
#
# Usage: ./setup-host.sh [sshconfig]
# Settings: every *.host.conf next to this script is sourced first (optional).
#   SSHCONFIG_DEFAULT in such a file makes the argument optional.
# Safe to re-run.
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for conf in "${SCRIPT_DIR}"/*.host.conf; do
    # shellcheck disable=SC1090
    [ -f "$conf" ] && . "$conf"
done

FAILURES=0
WARNINGS=0
TODOS=()

mark_failure() {
    FAILURES=$((FAILURES + 1))
}

mark_warning() {
    WARNINGS=$((WARNINGS + 1))
}

# Usage: ./setup-host.sh [sshconfig]
if [ "$#" -gt 1 ]; then
    echo "Usage: $0 [sshconfig]"
    exit 1
fi
SSHCONFIG=${1:-${SSHCONFIG_DEFAULT:-}}
if [ -z "$SSHCONFIG" ]; then
    echo "Usage: $0 <sshconfig>   (or set SSHCONFIG_DEFAULT in a *.host.conf next to this script)"
    exit 1
fi
echo "▶ Host: ${SSHCONFIG}"

# Check if the sshconfig string exists in the file ~/.ssh/config
if grep -qE "^Host (.* )?${SSHCONFIG//./\\.}( |\$)" ~/.ssh/config; then
    echo "✅ SSH config already exists."
else
    echo "❌ SSH config does not exist. Please add the following to your ~/.ssh/config:"
    cat <<EOF
# Add the following lines to your ~/.ssh/config file
Host ${SSHCONFIG}
    User root
    Port 22
    HostName <your-hostname>
    IdentityFile ~/.ssh/id_rsa
EOF
    exit 1
fi

# Check if login works password free
if ssh -o BatchMode=yes "${SSHCONFIG}" true; then
    echo "✅ SSH login works without a password."
else
    echo "❌ SSH login does not work without a password. Please check your SSH keys and configuration."
    exit 1
fi

# Check remote OS and sudo capability early
REMOTE_OS_ID=$(ssh "${SSHCONFIG}" "if [ -r /etc/os-release ]; then . /etc/os-release; echo \"\${ID:-unknown}\"; else uname -s; fi" | tr '[:upper:]' '[:lower:]')
REMOTE_OS_PRETTY=$(ssh "${SSHCONFIG}" "if [ -r /etc/os-release ]; then . /etc/os-release; echo \"\${PRETTY_NAME:-unknown}\"; else uname -s; fi")

if [ -n "$REMOTE_OS_PRETTY" ]; then
    echo "✅ Remote OS detected: $REMOTE_OS_PRETTY (id: $REMOTE_OS_ID)"
else
    echo "❌ Could not detect remote OS reliably."
    mark_failure
fi

# Debian and Ubuntu share apt and are both supported by install-docker.sh.
# IS_DEBIAN therefore means "Debian family", not Debian only.
IS_DEBIAN=0
case "$REMOTE_OS_ID" in
    debian|ubuntu)
        IS_DEBIAN=1
        echo "✅ Debian-family host detected ($REMOTE_OS_ID)."
        ;;
    *)
        echo "⚠️ Neither Debian nor Ubuntu detected. apt-based install steps will be skipped."
        ;;
esac

HAS_SUDO=0
if ssh "${SSHCONFIG}" "command -v sudo >/dev/null 2>&1"; then
    if ssh "${SSHCONFIG}" "sudo -n true >/dev/null 2>&1"; then
        HAS_SUDO=1
        echo "✅ Passwordless sudo is available for automation."
    else
        echo "⚠️ sudo exists, but passwordless sudo is not available. Root-requiring install steps will be skipped."
    fi
else
    echo "⚠️ sudo is not installed on the remote host. Root-requiring install steps will be skipped."
fi

# Check remote hostname
REMOTE_HOSTNAME=$(ssh "${SSHCONFIG}" hostname)
if [ -z "$REMOTE_HOSTNAME" ]; then
    echo "❌ Could not retrieve remote hostname. Please check your SSH connection."
    exit 1
else
    echo "✅ Remote hostname is: $REMOTE_HOSTNAME"
    # Ask if correct
    read -p "  Is this the correct hostname? (Y/n): " response
    if [[ "$response" =~ ^[Nn] ]]; then
        read -p "  Please enter the hostname for the remote server with domain:" -r REMOTE_HOSTNAME_WITH_DOMAIN
        # Get ip for current hostname
        IP_ADDRESS=$(ssh "${SSHCONFIG}" hostname -I | awk '{print $1}')
        if [ -z "$IP_ADDRESS" ]; then
            echo "❌ Could not retrieve IP address for the remote hostname. Please check your SSH connection."
            exit 1
        fi
        echo "  Current IP address for $REMOTE_HOSTNAME_WITH_DOMAIN is: $IP_ADDRESS"
        # Set the new hostname
        REMOTE_HOSTNAME=$(echo "$REMOTE_HOSTNAME_WITH_DOMAIN" | awk -F. '{print $1}')
        echo "  Setting remote hostname to: $REMOTE_HOSTNAME"
        echo "  Adding new hostname to /etc/hosts"
        if [ "$HAS_SUDO" -eq 1 ]; then
            ssh "${SSHCONFIG}" "echo '$IP_ADDRESS $REMOTE_HOSTNAME_WITH_DOMAIN $REMOTE_HOSTNAME # Added by setup-host.sh' | sudo -n tee -a /etc/hosts > /dev/null"
            ssh "${SSHCONFIG}" "sudo -n hostnamectl set-hostname $REMOTE_HOSTNAME"
            if [ $? -eq 0 ]; then
                echo "✅ Remote hostname set successfully."
                REMOTE_HOSTNAME=$(ssh "${SSHCONFIG}" hostname)
                echo "  New remote hostname is: $REMOTE_HOSTNAME"
            else
                echo "❌ Failed to set remote hostname. Please check your permissions."
                mark_failure
            fi
        else
            echo "⚠️ Hostname update requires root permissions and was skipped (no passwordless sudo)."
            mark_failure
        fi
    fi
fi

# Copy .bashrc-mkc to remote host
echo "  Copying .bashrc-mkc to remote host and adding to .bashrc..."
scp "${SCRIPT_DIR}/.bashrc-mkc" "${SSHCONFIG}":~/.bashrc-mkc 2>&1 > /dev/null
if [ $? -ne 0 ]; then
    echo "❌ Failed to copy .bashrc-mkc to remote host. Please check your SSH connection."
    exit 1
fi
# Append source command to remote .bashrc if not already present
ssh "${SSHCONFIG}" "grep -q 'source ~/.bashrc-mkc' ~/.bashrc || echo 'source ~/.bashrc-mkc' >> ~/.bashrc"
if ssh "${SSHCONFIG}" "grep -q 'source ~/.bashrc-mkc' ~/.bashrc"; then
    echo "✅ .bashrc-mkc is sourced in .bashrc on remote host."
else
    echo "❌ Failed to append source command to .bashrc. Please check your permissions."
    mark_failure
fi

# Check for docker installation
DOCKER_INSTALLED=$(ssh "${SSHCONFIG}" command -v docker 2>/dev/null)
if [ -z "$DOCKER_INSTALLED" ]; then
    echo "  Docker is not installed on the remote host."
    read -p "  Do you want to install Docker? (y/N): " response
    if [[ "$response" =~ ^[Yy] ]]; then
        if [ "$IS_DEBIAN" -ne 1 ]; then
            echo "❌ Docker installation requested but skipped: install-docker.sh supports Debian and Ubuntu only."
            mark_failure
        elif [ "$HAS_SUDO" -eq 1 ]; then
            echo "  Installing Docker on remote host..."
            echo "  Copying install-docker.sh to remote host and executing it..."
            scp "${SCRIPT_DIR}/install-docker.sh" "${SSHCONFIG}":~/install-docker.sh 2>&1 > /dev/null
            ssh "${SSHCONFIG}" "sudo -n bash ~/install-docker.sh"
            if [ $? -eq 0 ]; then
                echo "✅ Docker installed successfully."
            else
                echo "❌ Failed to install Docker. Please check your permissions."
                mark_failure
            fi
        else
            echo "❌ Docker installation requested but skipped: no passwordless sudo available."
            mark_failure
        fi
    else
        echo "⚠️ Skipping Docker installation."
        mark_failure
    fi
else
    echo "✅ Docker is already installed on the remote host."
fi

# Check if docker run works with available permissions
if [ "$HAS_SUDO" -eq 1 ]; then
    echo "  Checking if 'sudo -n docker run hello-world' works..."
    DOCKER_TEST_CMD="sudo -n docker run hello-world"
else
    echo "  Checking if 'docker run hello-world' works without sudo..."
    DOCKER_TEST_CMD="docker run hello-world"
fi

if ssh "${SSHCONFIG}" "$DOCKER_TEST_CMD"; then
    echo "✅ Docker hello-world check passed."
else
    echo "❌ Docker hello-world check failed. Please check Docker installation and permissions."
    mark_failure
fi

check_required_packages() {
    local required_packages="wget rsync tree git qemu-guest-agent"
    local package_report

    package_report=$(ssh "${SSHCONFIG}" "
missing=''
installed=''

for pkg in $required_packages; do
    case \"\$pkg\" in
        qemu-guest-agent)
            if command -v qemu-ga >/dev/null 2>&1 || command -v qemu-guest-agent >/dev/null 2>&1; then
                installed=\"\$installed \$pkg\"
            else
                missing=\"\$missing \$pkg\"
            fi
            ;;
        *)
            if command -v \"\$pkg\" >/dev/null 2>&1; then
                installed=\"\$installed \$pkg\"
            else
                missing=\"\$missing \$pkg\"
            fi
            ;;
    esac
done

echo \"INSTALLED:\${installed# }\"
echo \"MISSING:\${missing# }\"
")

echo "  Package status for: $required_packages"
echo "$package_report" | sed 's/^/  /'
}

# Install additional packages: wget, rsync, tree, git, qemu-guest-agent
if [ "$IS_DEBIAN" -eq 1 ] && [ "$HAS_SUDO" -eq 1 ]; then
    echo "  Installing additional packages: wget, rsync, tree, git, qemu-guest-agent..."
    ssh "${SSHCONFIG}" "sudo -n apt-get update && sudo -n apt-get install -y wget rsync tree git qemu-guest-agent"
    if [ $? -eq 0 ]; then
	    echo "✅ Additional packages installed successfully."
        check_required_packages
    else
	    echo "❌ Failed to install additional packages. Please check your permissions."
	    echo "  Verifying which required packages are already present..."
	    check_required_packages
	    mark_failure
    fi
else
    echo "⚠️ Skipping package installation (requires Debian/Ubuntu + passwordless sudo)."
    echo "  Verifying which required packages are already present..."
    check_required_packages
fi

# Part 2: project specific extensions (optional)
for ext in "${SCRIPT_DIR}"/setup-host-*.sh; do
    # shellcheck disable=SC1090
    [ -f "$ext" ] && . "$ext"
done

echo ""
echo "════════════════════════════════════════════════════════════════"
if [ "${#TODOS[@]}" -gt 0 ]; then
    echo "📋 Still to do by hand:"
    for t in "${TODOS[@]}"; do echo "   - $t"; done
fi
if [ "$FAILURES" -gt 0 ]; then
    echo "❌ setup-host.sh finished with $FAILURES issue(s) and $WARNINGS warning(s). See logs above."
    exit 1
fi
echo "✅ setup-host.sh finished successfully ($WARNINGS warning(s))."
