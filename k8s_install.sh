#!/bin/bash

install_kubernetes() {
set -e # Detiene el script si un comando falla
echo "--- Iniciando la preparación del sistema para Kubernetes ---"
# Actualizar paquetería e instalar requisitos previos:
apt update && apt upgrade -y
apt install curl apt-transport-https git wget software-properties-common lsb-release ca-certificates socat -y
# Desactivar swap:
swapoff -a
sed -i '/swap/s/^\(.*\)$/#\1/g' /etc/fstab
# Cargar módulos necesarios del kernel y cargar configuración en sysctl:
modprobe overlay
modprobe br_netfilter
cat << EOF | tee /etc/sysctl.d/kubernetes.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
# Aplicar configuración de sysctl y comprobar que se ha aplicado correctamente:
sysctl --system
# Instalar las claves gpg de Docker para instalar containerd:
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
# Instalar containerd y configurar el daemon para que use cgroups de systemd:
apt-get update && apt-get install containerd.io -y
containerd config default | tee /etc/containerd/config.toml
sed -e's/SystemdCgroup = false/SystemdCgroup = true/g' -i /etc/containerd/config.toml
sed -e's|sandbox_image = "registry.k8s.io/pause:3.8"|sandbox_image = "registry.k8s.io/pause:3.10"|g' -i /etc/containerd/config.toml
systemctl restart containerd
# Instalar claves gpg de Kubernetes y añadir el repositorio:
mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
# Añadir el repositorio de Kubernetes 1.30 (puedes cambiar la versión modificando las URLs):
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
apt-get update
# Instalar kubeadm, kubelet y kubectl:
apt-get install -y kubeadm kubelet kubectl
apt-mark hold kubelet kubeadm kubectl

kubeadm init --pod-network-cidr=192.168.0.0/16 --control-plane-endpoint=node_master:6443
}

# Configuración de /etc/hosts
echo "Cuantos nodos tendra el cluster:"
read count_node

echo "Direccion ip node_master:"
read master_ip
echo "node_master   $master_ip" >> ips.txt

for ((i=2; i<=count_node; i++)); do
    echo "Direccion ip node_$i:"
    read ip_node
    ip_node=$ip_node
    echo "node_$i   $ip_node" >> ips.txt
done

echo ips.txt >> /etc/hosts

install_kubernetes

# Generar el archivo de configuración de kubeconfig
touch kubeconfig
cp -i /etc/kubernetes/admin.conf kubeconfig

# Instalacion de CNI cilium
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}

cilium install --version 1.18.1

# Generar bash de coneccion de nodos al master
token=$(kubeadm token list | grep -v "TOKEN" | head -n 1 | awk '{print $1}')
hash=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')

echo "Generando bash de conexión para node_master"
cat <<EOF > node_master.sh
#!/bin/bash
echo ips.txt >> /etc/hosts
kubeadm join $master_ip:6443 --token $token --discovery-token-ca-cert-hash sha256:$hash
EOF

echo "Generado bash de conexión para nodos"
echo "debe de copiar los archivos ips.txt y node_master.sh a los nodos"
echo "y ejecutar el bash node_master.sh en cada nodo" 
echo "Recuerda que debes ejecutar el script como root no con sudo"
