: '
menu.sh - Custom Linux Menu Script

This script provides an interactive menu for managing Kubernetes and various system configurations on Linux-based systems. It supports multiple distributions and adapts its actions based on the detected operating system and network configuration tools.

Features:
- Change system hostname
- Set or change static IP address for network interfaces (supports Netplan, NetworkManager, systemd-networkd, traditional scripts, BSD rc.conf)
- Enable root SSH login and configure passwordless sudo for the current user
- Disable SELinux and firewalld, enable IPv4 forwarding
- Disable swap (required for Kubernetes)
- Install Docker (supports apt, yum, dnf)
- Install Kubernetes (supports apt, yum, dnf, and manual installation)
- Initialize Kubernetes master node and export join command

Usage:
- Run the script as root for full functionality.
- Follow the interactive prompts to select and configure system options.

Notes:
- The script attempts to detect the operating system and network configuration method automatically.
- Some actions may overwrite existing configuration files (e.g., network settings).
- Always review changes before applying in production environments.

Author: zkt2202
Date: 22/07/2025
'
#!/bin/bash
# menu.sh
# This script provides a menu for managing Kubernetes and other system configurations.
# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Please use 'sudo' or switch to the root user."
    exit 1
fi  
# Function to display the menu
display_menu() {
    echo "=============================="
    echo "   Custom Linux Menu"
    echo "=============================="
    echo "1) Change Hostname"
    echo "2) Set Static IP Address"
    echo "3) Change Static IP Address"
    echo "4) Enable Root SSH & Sudoer No Password"
    echo "5) Disable SELinux, Firewalld & Enable IP Forwarding"
    echo "6) Disable Swap for Kubernetes"
    echo "7) Install Docker"
    echo "8) Install Kubernetes"
    echo "9) Initialize Kubernetes Master Node"
    echo "0) Exit"
    echo "------------------------------"
}

get_os() {
  if [[ -f /etc/os-release ]]; then
    # On Linux, source the file and return the ID (e.g., ubuntu, fedora, alpine)
    source /etc/os-release
    echo "$ID"
  else
    # On macOS or BSD, use uname to get the OS name
    uname
  fi
}
get_interfaces() {
 ip -o link show up | awk -F': ' '{print $2}' | grep -v "lo"   
}
# Usage
#os=$(get_os)
#echo "Operating System: $os"
#interface=$(get_interfaces)

# Function to handle user input
handle_choice() {
    case $1 in
        1) 
        # Change Hostname
            read -p "Enter new hostname: " new_hostname
            if [ -z "$new_hostname" ]; then
                echo "Hostname cannot be empty."
            else
                sudo hostnamectl set-hostname "$new_hostname"
                sudo sed -i "s/127.0.1.1.*/127.0.1.1\t$new_hostname/g" /etc/hosts
                echo "Hostname updated to: $new_hostname"
            fi
            ;;
        2)
        # Set IP
            read -p "Enter interfaces connected: " interface 
            read -p "Enter the static IP address (e.g., 192.168.9.100): " static_ip
            read -p "Enter the subnet mask (e.g., 255.255.255.0): " subnet_mask
            read -p "Enter the gateway (e.g., 192.168.9.1): " gateway
            read -p "Enter the DNS server (e.g., 8.8.8.8): " dns_server
            # Check if the interface exists
            if ! ip link show "$interface" > /dev/null 2>&1; then
                echo "Interface '$interface' does not exist. Please check the interface name and try again."
                exit 1
            fi
            # Set the static IP address
            if [ -f /etc/netplan/50-cloud-init.yaml ]; then
                # For systems using netplan (e.g., Ubuntu)
                echo "Setting static IP for Ubuntu..."
                sudo bash -c "cat <<EOF > /etc/netplan/50-cloud-init.yaml
network:
  version: 2
  ethernets:
    $interface: 
      dhcp4: no
      addresses:
        - $static_ip/24
      gateway4: $gateway
      nameservers:
        addresses:
          - $dns_server
EOF"
                sudo netplan apply
                echo "Static IP set successfully for Ubuntu."
            elif [ -f /etc/network/interfaces ]; then
                # For Debian-based systems
                echo "Setting static IP for Debian..."
                sudo bash -c "cat <<EOF > /etc/network/interfaces
auto $interface
iface $interface inet static
    address $static_ip/24
    gateway $gateway
    dns-nameservers $dns_server
EOF"
                sudo systemctl restart networking
                echo "Static IP set successfully for Debian."
            elif [ -f /etc/sysconfig/network-scripts/ifcfg-$interface ]; then
                # For Red Hat-based systems (CentOS, Fedora, etc.)
                echo "Setting static IP for Red Hat-based system..."
                sudo bash -c "cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-$interface
DEVICE=$interface
BOOTPROTO=none
ONBOOT=yes
IPADDR=$static_ip
NETMASK=$subnet_mask
GATEWAY=$gateway
DNS1=$dns_server
EOF"
                sudo systemctl restart NetworkManager
                echo "Static IP set successfully for Red Hat-based system."
            elif [ -f /etc/NetworkManager/system-connections ]; then
                # For systems using NetworkManager
                echo "Setting static IP for system using NetworkManager..."
                sudo bash -c "cat <<EOF > /etc/NetworkManager/system-connections/$interface.nmconnection
[connection]
id=$interface
uuid=$(uuidgen)
type=ethernet
interface-name=$interface
[ethernet]
mac-address=$(ip link show $interface | awk '/ether/ {print $2}')
[ipv4]
method=manual
address1=$static_ip/$subnet_mask,$gateway
dns=$dns_server
[ipv6]
method=ignore
EOF"
                sudo systemctl restart NetworkManager
                echo "Static IP set successfully for system using NetworkManager."
            elif [ -f /etc/systemd/network/10-$interface.network ]; then
                # For systems using systemd-networkd (e.g., Arch Linux)
                echo "Setting static IP for Arch Linux..."
                sudo bash -c "cat <<EOF > /etc/systemd/network/10-$interface.network
[Match]
Name=$interface
[Network]
Address=$static_ip/24
Gateway=$gateway
DNS=$dns_server
EOF"
                sudo systemctl restart systemd-networkd
                echo "Static IP set successfully for Arch Linux."
            elif [ -f /etc/rc.conf ]; then
                # For systems using rc.conf (e.g., FreeBSD)
                echo "Setting static IP for FreeBSD..."
                sudo bash -c "cat <<EOF >> /etc/rc.conf
ifconfig_$interface=\"inet $static_ip netmask $subnet_mask\"
defaultrouter=\"$gateway\"
ifconfig_$interface_alias=\"inet $dns_server\"
EOF"
                sudo service netif restart
                echo "Static IP set successfully for FreeBSD."
            elif [ -f /etc/bsdrc.conf ]; then
                # For systems using bsdrc.conf (e.g., OpenBSD)
                echo "Setting static IP for OpenBSD..."
                sudo bash -c "cat <<EOF >> /etc/bsdrc.conf
ifconfig_$interface=\"inet $static_ip netmask $subnet_mask\"
defaultrouter=\"$gateway\"
nameserver=\"$dns_server\"
EOF"
                sudo sh /etc/rc.d/netif restart

            else
                echo "Unsupported operating system or network configuration."
                exit 1
            fi  
            ;;

        3)
        # Change new IP address 
            read -p "Enter interfaces connected: " interface 
            read -p "Enter the new static IP address (e.g., 192.168.9.100): " NEW_IP
            if [ -f /etc/network/interfaces ]; then
                # Debian-based system
                echo "Updating static IP on Debian-based system..."
                sed -i "s|192\.168\.9\.[0-9]\+/24|$NEW_IP/24|g" /etc/network/interfaces
                systemctl restart networking
                echo "Static IP updated to $NEW_IP successfully."
            elif [ -f /etc/netplan/50-cloud-init.yaml ]; then
                # Debian-based system with netplan
                echo "Updating static IP on Debian-based system with netplan..."
                sed -i "s|192\.168\.9\.[0-9]\+/24|$NEW_IP/24|g" /etc/netplan/50-cloud-init.yaml
            
            elif [ -d /etc/NetworkManager/system-connections ]; then
                # Red Hat-based system with NetworkManager
                echo "Updating static IP on Red Hat-based system with NetworkManager..."
                sudo sed -i "s/^address1=.*/address1=$NEW_IP/" /etc/NetworkManager/system-connections/* || true
                sudo systemctl restart NetworkManager
                echo "Static IP updated to $NEW_IP successfully."
            elif [ -f /etc/sysconfig/network-scripts/ifcfg-$interface]; then
                # Red Hat-based system with traditional network scripts
                echo "Updating static IP on Red Hat-based system with network scripts..."
                sudo sed -i "s/IPADDR=.*/IPADDR=$NEW_IP/" /etc/sysconfig/network-scripts/ifcfg-"$interface"
                sudo systemctl restart NetworkManager
                echo "Static IP updated to $NEW_IP successfully."
            else
                echo "Unsupported operating system or network configuration."
            fi
            ;;

        4)
        # SSH with root
            echo "Enable root login via SSH"
            # Uncomment the following line to enable root login via SSH
             sudo sed -i 's/prohibit-password/yes/' /etc/ssh/sshd_config
            # Restart SSH service to apply changes
             sudo systemctl restart sshd
            # Enable sudoer without password
            sudo bash -c 'echo "$(logname) ALL=(ALL:ALL) NOPASSWD: ALL" | (EDITOR="tee -a" visudo)'
            echo "Sudoer no password has been enabled."
            ;;

        5)
        # Check and install policycoreutils if getenforce or setenforce is missing
            if ! command -v getenforce &> /dev/null || ! command -v setenforce &> /dev/null; then
                echo "Installing policycoreutils to manage SELinux..."
                if command -v yum &> /dev/null; then
                    sudo yum install -y policycoreutils || sudo apt-get install -y policycoreutils || sudo dnf install -y policycoreutils
                else
                    echo "Package manager not found. Please install policycoreutils manually."
                    exit 1
                fi
            fi
            # Check and disable SELinux
            echo "Checking SELinux status..."
            SELINUX_STATUS=$(getenforce)
            if [ "$SELINUX_STATUS" != "Disabled" ]; then
                echo "SELinux is currently $SELINUX_STATUS. Disabling SELinux..."
                sudo setenforce 0
                sudo sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
                echo "SELinux has been disabled."
            else
                echo "SELinux is already disabled."
            fi
            # Check and disable firewalld (if it exists)
            if systemctl list-unit-files | grep -q "^firewalld.service"; then
                echo "Checking firewalld status..."
                FIREWALLD_STATUS=$(sudo systemctl is-active firewalld)
                if [ "$FIREWALLD_STATUS" = "active" ]; then
                    echo "firewalld is active. Disabling firewalld..."
                    sudo systemctl stop firewalld
                    sudo systemctl disable firewalld
                    echo "firewalld has been disabled."
                else
                    echo "firewalld is already disabled."
                fi
            else
                echo "firewalld service does not exist on this system." 
            fi
            # Check and enable IPv4 IP forwarding
            echo "Checking IPv4 IP forwarding status..."
            IP_FORWARD_STATUS=$(sysctl net.ipv4.ip_forward | awk '{print $3}')
            if [ "$IP_FORWARD_STATUS" = "0" ]; then
                echo "IPv4 IP forwarding is disabled. Enabling it..."
                sudo sysctl -w net.ipv4.ip_forward=1
                sudo sed -i 's/^net.ipv4.ip_forward=.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
                echo "IPv4 IP forwarding has been enabled."
            else
                echo "IPv4 IP forwarding is already enabled."
            fi
            echo "All tasks completed."
            ;;

        6)
        # Disable swap for Kube
            echo "Disabling swap..."
            sudo swapoff -a
            sudo sed -i '/\sswap\s/d' /etc/fstab
            echo "Swap has been disabled and removed from /etc/fstab."
            # Ensure swap remains disabled after reboot by adding to /etc/rc.local
            if [ -f /etc/rc.local ]; then
                if ! grep -q "swapoff -a" /etc/rc.local; then
                    echo "swapoff -a" | sudo tee -a /etc/rc.local > /dev/null
                    sudo chmod +x /etc/rc.local
                    echo "Added 'swapoff -a' to /etc/rc.local to disable swap on boot."
                else
                    echo "'swapoff -a' is already present in /etc/rc.local."
                fi
            else
                echo "#!/bin/bash
            swapoff -a
            exit 0" | sudo tee /etc/rc.local > /dev/null
                sudo chmod +x /etc/rc.local
                echo "Created /etc/rc.local and added 'swapoff -a' to disable swap on boot."
            fi
            ;;

        7)
        # Check Docker
            echo "Checking Docker installation..."
            if ! command -v docker &> /dev/null; then
                echo "Docker not found. Installing Docker..."
                if command -v apt-get &> /dev/null; then
                    sudo apt-get update
                    sudo apt-get install -y ca-certificates curl gnupg
                    sudo install -m 0755 -d /etc/apt/keyrings
                    curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
                    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
                    sudo apt-get update
                    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
                    sudo systemctl enable --now docker
                elif command -v yum &> /dev/null || command -v dnf &> /dev/null; then
                    PKG_MGR="yum"
                    if command -v dnf &> /dev/null; then
                        PKG_MGR="dnf"
                    fi
                    sudo $PKG_MGR install -y yum-utils
                    sudo $PKG_MGR config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
                    sudo $PKG_MGR install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
                    sudo systemctl enable --now docker
                else
                    echo "Unsupported OS or package manager. Please install Docker manually."
                    exit 1
                fi
                echo "Docker installation completed."
            else
                echo "Docker is already installed."
            fi
            ;;

        8)
            # Intall Kubernetes
            echo "Installing Kubernetes..."
            # Check the operating system and install Kubernetes accordingly
            # Install using native package management
            # Check if the system is Debian-based (e.g., Ubuntu)
            if command -v apt-get &> /dev/null; then
                echo "Detected Debian-based system. Installing Kubernetes..."
                sudo apt-get update -y
                sudo apt-get install -y apt-transport-https ca-certificates curl gnupg
                # Add Kubernetes's official GPG key 
                # Check if /etc/apt/keyrings exists, create if not
                if [ ! -d /etc/apt/keyrings ]; then
                    sudo mkdir -p -m 755 /etc/apt/keyrings
                fi
                curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
                sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg 
                # allow unprivileged APT programs to read this keyring
                echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
                sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list  
                # helps tools such as command-not-found to work correctly
                sudo apt-get update
                sudo apt-get install -y kubelet kubeadm kubectl
                sudo apt-mark hold kubelet kubeadm kubectl
                sudo systemctl enable --now kubelet
            # Check if the system is Redhat-based 
            elif command -v yum &> /dev/null || command -v dnf &> /dev/null; then
                echo "Detected Red Hat-based system. Installing Kubernetes..."
                if command -v yum &> /dev/null; then
                PKG_MGR="yum"
                else
                PKG_MGR="dnf"
                fi
                # Set SELinux in permissive mode (effectively disabling it)
                sudo setenforce 0
                sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
                # This overwrites any existing configuration in /etc/yum.repos.d/kubernetes.repo
                cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
    [kubernetes]
    name=Kubernetes
    baseurl=https://pkgs.k8s.io/core:/stable:/v1.33/rpm/
    enabled=1
    gpgcheck=1
    gpgkey=https://pkgs.k8s.io/core:/stable:/v1.33/rpm/repodata/repomd.xml.key
    exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
                sudo $PKG_MGR install -y curl 
                sudo $PKG_MGR install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

                sudo systemctl enable --now kubelet
            else
            # Without a package manager
            # Install CNI plugins (required for most pod network):
                CNI_PLUGINS_VERSION="v1.3.0"
                ARCH="amd64"
                DEST="/opt/cni/bin"
                sudo mkdir -p "$DEST"
                curl -L "https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/cni-plugins-linux-${ARCH}-${CNI_PLUGINS_VERSION}.tgz" | sudo tar -C "$DEST" -xz
                DOWNLOAD_DIR="/usr/local/bin"
                sudo mkdir -p "$DOWNLOAD_DIR"
                RELEASE="$(curl -sSL https://dl.k8s.io/release/stable.txt)"
                cd $DOWNLOAD_DIR
                sudo curl -L --remote-name-all https://dl.k8s.io/release/${RELEASE}/bin/linux/${ARCH}/{kubeadm,kubelet}
                sudo chmod +x {kubeadm,kubelet}
                RELEASE_VERSION="v0.16.2"
                curl -sSL "https://raw.githubusercontent.com/kubernetes/release/${RELEASE_VERSION}/cmd/krel/templates/latest/kubelet/kubelet.service" | sed "s:/usr/bin:${DOWNLOAD_DIR}:g" | sudo tee /usr/lib/systemd/system/kubelet.service
                sudo mkdir -p /usr/lib/systemd/system/kubelet.service.d
                curl -sSL "https://raw.githubusercontent.com/kubernetes/release/${RELEASE_VERSION}/cmd/krel/templates/latest/kubeadm/10-kubeadm.conf" | sed "s:/usr/bin:${DOWNLOAD_DIR}:g" | sudo tee /usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf
                sudo systemctl enable --now kubelet
                sudo systemctl start --now kubelet

            fi
            ;;
        
        9) 
        # For Master Kube
            echo "Initializing Kubernetes master node..."
            # Check kubeadm run on master 
            if systemctl is-active --quiet kubelet; then
                sudo kubeadm init --pod-network-cidr=10.244.0.0/16
            else
                echo "Kubelet not install or not run"
            fi

            if [ $? -eq 0 ]; then
                mkdir -p $HOME/.kube
                sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
                sudo chown $(id -u):$(id -g) $HOME/.kube/config
                echo "Kubernetes master node initialized successfully."
                echo "You can now install a pod network add-on, e.g.:"
                echo "kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml"
                # Generate join command as root and export to a text file in $HOME
                JOIN_CMD=$(kubeadm token create --print-join-command)
                echo "$JOIN_CMD" > "$HOME/kubeadm-join-command.txt"
                echo "$JOIN_CMD" | tee kubeadm-join-command.txt
                echo "Join command exported to kubeadm-join-command.txt"

            else
                echo "Kubernetes master node initialization failed."
            fi
            ;;

        0)
            echo "Thank you for using the Custom Linux Menu!"
            echo "Goodbye!"
            exit 0
            ;;
        *)
            echo "Invalid choice. Please try again."
            ;;
    esac
}
# Main loop to display the menu and handle user input
while true; do
    display_menu
    read -p "Enter your choice: " choice
    handle_choice "$choice"
    echo
done
