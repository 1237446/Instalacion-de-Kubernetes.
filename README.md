# Instalacion de Kubernetes v1.33 en Ubuntu server 24.04
> [!NOTE]
> Esta presente guia es una adaptacion de la guia echa por [Pabpereza](https://pabpereza.dev/docs/cursos/kubernetes/instalacion_de_kubernetes_cluster_completo_ubuntu_server_con_kubeadm/), la guia original es de su propiedad

Kubernetes, al igual que pasa con Linux no tiene una manera única de instalarse, esta dependerá de la distribución que elijamos. En esta guía usaremos K8s que es la distribución "oficial" de kubernetes.

Para todas las instalaciones estos son los requisitos mínimos y los recomendados para un clúster de Kubernetes:

![guia](/imagenes/picture-0.png)

## Nodo maestro y workers
> [!NOTE]
> los comandos se han ejecutado con el usuario root.

Actualizar paquetería e instalar requisitos previos:
```
apt update && apt upgrade -y
apt install curl apt-transport-https git wget software-properties-common lsb-release ca-certificates socat -y
```

Desactivar swap:
```
swapoff -a
sed -i '/swap/s/^\(.*\)$/#\1/g' /etc/fstab
```

Cargar módulos necesarios del kernel y cargar configuración en sysctl:
```
modprobe overlay
modprobe br_netfilter
cat << EOF | tee /etc/sysctl.d/kubernetes.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
```

Aplicar configuración de sysctl y comprobar que se ha aplicado correctamente:
```
sysctl --system
```

Instalar las claves gpg de Docker para instalar containerd:
```
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
| sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu \
$(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

Instalar containerd y configurar el daemon para que use cgroups de systemd:
```
apt-get update && apt-get install containerd.io -y
containerd config default | tee /etc/containerd/config.toml
sed -e's/SystemdCgroup = false/SystemdCgroup = true/g' -i /etc/containerd/config.toml
sed -e 's|sandbox_image = "registry.k8s.io/pause:3.8"|sandbox_image = "registry.k8s.io/pause:3.10"|g' -i /etc/containerd/config.toml
systemctl restart containerd
```

Instalar claves gpg de Kubernetes y añadir el repositorio:
```
mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key \
| sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

Añadir el repositorio de Kubernetes 1.30 (puedes cambiar la versión modificando las URLs):
```
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /" \
| sudo tee /etc/apt/sources.list.d/kubernetes.list
apt-get update
```

Instalar kubeadm, kubelet y kubectl:
```
apt-get install -y kubeadm kubelet kubectl
apt-mark hold kubelet kubeadm kubectl
```

Buscamos las ips de los nodos master y worker IP y la añadimos al fichero /etc/hosts de todos los nodos
> [!TIP]
> Puedes obtener tu ip con el comando "ip a" o "hostname -i."
```
echo "<IP> <nombre del nodo>" >> /etc/hosts
```
verificamos la adicion de las ips
```
cat /etc/hosts
```
```
192.168.1.200    node-master-0
192.168.1.201    node-worker-0
192.168.1.202    node-worker-1 
```

## Nodo Master
Iniciar el cluster con kubeadm (importante cambiar el rango de IPs para pods por uno que no esté en uso en tu red, evitar también el rango 10.x.x.x ya que es un rango reservado para redes privadas). Por último, añadimos el nombre del nodo maestro (recuerda usar el de antes) y el puerto 6443:
```
kubeadm init --pod-network-cidr=<rango de IPs para pods> --control-plane-endpoint=<Nombre añañadido en el /etc/hosts>:6443
```
> [!TIP]
> kubeadm init --pod-network-cidr=192.168.0.0/16 --control-plane-endpoint=node-master-0:6443 

Configurar kubectl:
> [!NOTE]
> Apartir de este paso los comandos se han ejecutado con el usuario del sistema.
```
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

instalar autocompletado:
> [!TIP]
> Esto nos permitirá usar autocompletado en la terminal de bash y si tabulamos después de escribir kubectl nos mostrará las opciones disponibles.
```
sudo apt-get install bash-completion -y
source <(kubectl completion bash)
echo 'source <(kubectl completion bash)' >> ~/.bashrc
```

Instalar Helm, necesario para instalar algunas aplicaciones en Kubernetes, incluido cilium (la CNI que vamos a instalar):
```
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm -y
```

### Instalacion de CNI
En este caso usaremos CILIUM debido a que se basa en una nueva tecnología del kernel de Linux llamada eBPF, que permite la integración dinámica de una potente lógica de visibilidad y control de seguridad dentro del propio Linux.

> [!NOTE]
> La instalacion de cilium es sacada de la guia [oficial](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/)

![guia](/imagenes/picture-1.png)

```
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
```
```
cilium install --version 1.18.1
```

Si quieres que tu nodo maestro también sea un nodo worker (es decir, que ejecute pods), puedes hacerlo con el siguiente comando:
> [!WARNING]
> Esta es una opcion pero no es recomendado
```
kubectl taint nodes --all  node-role.kubernetes.io/control-plane-
```

Podríamos reactivar la restricción (taint) de que el nodo maestro no ejecute pods con el comando:
```
kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule
```

## Nodo worker
Obtenemos el token:
```
kubeadm token list
```
```
TOKEN                     TTL         EXPIRES                USAGES                   DESCRIPTION                                                EXTRA GROUPS
vm8owh.kajjwyp94tajsizs   1h          2025-08-24T01:52:35Z   authentication,signing   The default bootstrap token generated by 'kubeadm init'.   system:bootstrappers:kubeadm:default-node-token
```
> [!TIP]
> Si hubiera expirado, se puede generar uno nuevo con **kubeadm token create**.

El hash se puede obtener con el siguiente comando de openssl. Lo lanzamos en el nodo maestro:
```
openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'
```

Unir el nodo worker al cluster con el comando que nos proporcionó kubeadm init en el nodo maestro:
```
kubeadm join <Nombre del nodo maestro>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

Comprobar que el nodo worker se ha unido correctamente al cluster. Lanza el siguiente comando en el nodo maestro:
```
kubectl get nodes
```
> [!TIP]
> Es posible que tarde un poco en estar listo
```
NAME            STATUS   ROLES           AGE   VERSION
node-master-0   Ready    control-plane   15m   v1.33.4
node-worker-0   Ready    <none>          15m   v1.33.4
node-worker-1   Ready    <none>          15m   v1.33.4
```

Comprobamos el funcionamiento en general de los pods
```
kubectl get pods -n kube-system
```
```
NAMESPACE     NAME                               READY   STATUS    RESTARTS      AGE
kube-system   cilium-envoy-5fwdq                 1/1     Running   0             9m34s
kube-system   cilium-envoy-74bxq                 1/1     Running   0             9m34s
kube-system   cilium-envoy-tgckc                 1/1     Running   0             9m34s
kube-system   cilium-mhd72                       1/1     Running   0             9m34s
kube-system   cilium-ngl2m                       1/1     Running   0             9m34s
kube-system   cilium-operator-686959b66d-6t86c   1/1     Running   0             9m33s
kube-system   cilium-operator-686959b66d-bmvgx   1/1     Running   0             9m33s
kube-system   cilium-qvcgj                       1/1     Running   0             9m34s
kube-system   coredns-674b8bbfcf-7q6mp           1/1     Running   0             16m
kube-system   coredns-674b8bbfcf-d4tlf           1/1     Running   0             16m
kube-system   etcd-node-01                       1/1     Running   1             16m
kube-system   kube-apiserver-node-01             1/1     Running   2             16m
kube-system   kube-controller-manager-node-01    1/1     Running   7 (14m ago)   16m
kube-system   kube-proxy-6xjdn                   1/1     Running   0             16m
kube-system   kube-proxy-lmb69                   1/1     Running   0             16m
kube-system   kube-proxy-qlzvh                   1/1     Running   0             16m
kube-system   kube-scheduler-node-01             1/1     Running   7 (14m ago)   16m
```

Ahora verificaremos el funcionamiento de Cilium
```
cilium status --wait
```
```
    /¯¯\
 /¯¯\__/¯¯\    Cilium:             OK
 \__/¯¯\__/    Operator:           OK
 /¯¯\__/¯¯\    Envoy DaemonSet:    OK
 \__/¯¯\__/    Hubble Relay:       disabled
    \__/       ClusterMesh:        disabled

DaemonSet              cilium                   Desired: 3, Ready: 3/3, Available: 3/3
DaemonSet              cilium-envoy             Desired: 3, Ready: 3/3, Available: 3/3
Deployment             cilium-operator          Desired: 2, Ready: 2/2, Available: 2/2
Containers:            cilium                   Running: 3
                       cilium-envoy             Running: 3
                       cilium-operator          Running: 2
                       clustermesh-apiserver
                       hubble-relay
Cluster Pods:          2/2 managed by Cilium
Helm chart version:    1.17.5
Image versions         cilium             quay.io/cilium/cilium:v1.17.5@sha256:baf8541723ee0b72d6c489c741c81a6fdc5228940d66cb76ef5ea2ce3c639ea6: 3
                       cilium-envoy       quay.io/cilium/cilium-envoy:v1.32.6-1749271279-0864395884b263913eac200ee2048fd985f8e626@sha256:9f69e290a7ea3d4edf9192acd81694089af048ae0d8a67fb63bd62dc1d72203e: 3
                       cilium-operator    quay.io/cilium/operator-generic:v1.17.5@sha256:f954c97eeb1b47ed67d08cc8fb4108fb829f869373cbb3e698a7f8ef1085b09e: 2
```

## Configuracion de cilium (OPCIONAL) 
Ahora que hemos completado la instalacion de cilium, habilitaremos la exposicion de servicos con Layer2 para el Balanceador de carga

Definiremos las IPs a usar, creando el manifiesto **ip-pool.yaml** y lo aplicamos
```yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumLoadBalancerIPPool
metadata:
  name: my-l2-ip-pool
spec:
  blocks:
    - cidr: "192.168.1.200/29" # REEMPLAZA con un rango de IPs DISPONIBLES en tu red local
  serviceSelector: {} # Deja vacío para aplicar a todos los servicios por defecto, o usa un selector si es necesario

---
apiVersion: cilium.io/v2alpha1
kind: CiliumL2AnnouncementPolicy
metadata:
  name: default-l2-policy
spec:
  loadBalancerIPs: true
  externalIPs: true
  interfaces:
    - enp0s3 # REEMPLAZA con el nombre de tu interfaz de red principal
  nodeSelector: {} # Puedes usar un selector para aplicar esta política a nodos específicos
  serviceSelector: {} # Puedes usar un selector para aplicar esta política a servicios específicos
```
```
kubectl apply -f ip-pool.yaml
```

Verificaremos que el funcionamiento, ejecutando el manifiesto test.yaml para probar el correcto funcionamiento 
```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx
spec:
  selector:
    app: nginx
  ports:
    - port: 80
      targetPort: 80
  type: LoadBalancer

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  labels:
    app: nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.7.9
        ports:
        - containerPort: 80
```
```
kubectl apply -f test.yaml
```
```
kubectl get svc
```
```
NAME         TYPE           CLUSTER-IP       EXTERNAL-IP    PORT(S)        AGE
kubernetes   ClusterIP      10.96.0.1        <none>         443/TCP        20m
nginx        LoadBalancer   10.106.163.196   172.16.8.180   80:32160/TCP   7m26s
```

## Hubble
Es una la poderosa herramienta de observabilidad para monitorear y entender lo que sucede en tu red de Kubernetes impulsada por Cilium

Su instalacion es sencilla debido a que ya contamos con **cilium cli**
```
cilium hubble enable --ui
```
Una vez habilitado ingresamos a la interfaz web
```
cilium hubble ui
```
Para poder acceder tendremos que crear un pequeño tunel con ssh
```
sudo ssh -L 80:localhost:12000 <user>@<host>
```
ingresamos desde nuestro navegador al local hosts y seleccionamos que namespaces observaremos

![guia](/imagenes/picture-2.png)

![guia](/imagenes/picture-3.png)
