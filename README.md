# Instalacion de cilium en kubernetes
Usaremos la manera mas recomendada para instalar cilum, la cual es usando helm, el gestor de paquetes de kubernetes ademas habilitaremos el balanceo de carga layer2 para soluciones om-premise

![guia](/imagenes/imagen-0.png)

Añadimos el Repositorio de Helm, para poder instalar Cilium 
```
helm repo add cilium https://helm.cilium.io/
helm repo update
```
Instalamos cilium usando helm, ademas de añadir los parametros para habilitar la publicacion en Layer2
```
helm install cilium cilium/cilium \
  --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set l2announcements.enabled=true \
  --set l2announcements.leaseDuration=10s \
  --set l2announcements.leaseRenewDeadline=5s \
  --set l2announcements.leaseRetryPeriod=1s \
  --set ipam.mode=kubernetes \
  --set operator.replicas=2
```
> [!NOTE]
> **--set kubeProxyReplacement=true:** Indica a Cilium que reemplace completamente la funcionalidad de kube-proxy. Esto es fundamental para que Cilium pueda manejar el balanceo de carga L2 y las IPs de tipo LoadBalancer.

> [!NOTE]
> **--set l2announcements.enabled=true:** Habilita la característica de anuncios L2, que es la base >para la exposición de servicios.

> [!NOTE]
> **--set ipam.mode=kubernetes:** Asegura que Cilium use el controlador de IPAM de Kubernetes para la asignación de IPs a los Pods.

Verificamos el estado de de los pods de cilium, esperemanos a que todos los pods esten en **Runnig**
```
kubectl get pods -n kube-system -l k8s-app=cilium
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

Ahora eliminamos los pods de kube-proxy, para que cilium lo pueda reemplazar
> [!WARNING]
> Ten en cuenta que la eliminación de kube-proxy romperá las conexiones de servicio existentes. El tráfico relacionado con los servicios se detendrá hasta que la funcionalidad de reemplazo de Cilium esté completamente instalada y operativa. Ten un plan de reversión en caso de que algo salga mal.

> [!CAUTION]
> Antes de elimianar kube-proxy asegurate que todos los pods de cilium esten en **Running**
```
kubectl delete daemonset -n kube-system kube-proxy
```

### Cilium CLI
Cilium ya esta instalado pero añadiremos su recurso CLI para poder verificar el estado de los pods, descargamos el binario directamente desde el releases de GitHub.
> [!TIP]
> Define la versión de Cilium que estás usando o la más reciente si no estás seguro Puedes encontrar la última versión en https://github.com/cilium/cilium-cli/releases
```
CILIUM_CLI_VERSION=$(curl -s https://api.github.com/repos/cilium/cilium-cli/releases/latest | grep -oP '"tag_name": "\K[^"]+')

curl -L --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz{,.sha256sum}
```

verficamos la integridad del archivo descargado
```
sha256sum --check cilium-linux-amd64.tar.gz.sha256sum
```

Extraemos el binario
```
tar xzvf cilium-linux-amd64.tar.gz
```

Movemos el binario al directorio **/usr/local/bin** 
```
sudo mv cilium /usr/local/bin
```

Verificamos la instalacion del CLI
```
cilium version
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
## Configuracion de cilium
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
```
> [!IMPORTANT]
> Para definir el rango de IPs, se debe de usar el mismo metodo que se usa para crear subredes

```
kubectl apply -f ip-pool.yaml
```

Crearemos una Política de Anuncio Layer2, creando el manifiesto **l2-policy.yaml** y lo aplicamos
```yaml
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
kubectl apply -f l2-policy.yaml
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
clamav       ClusterIP      10.96.37.93      <none>         3310/TCP       16h
kubernetes   ClusterIP      10.96.0.1        <none>         443/TCP        20h
nginx        LoadBalancer   10.106.163.196   172.16.8.180   80:32160/TCP   7m26s
postgresql   ClusterIP      10.104.138.185   <none>         5432/TCP       16h
redis        ClusterIP      10.100.66.147    <none>         6379/TCP       16h
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

![guia](/imagenes/imagen-1.png)

![guia](/imagenes/imagen-2.png)
