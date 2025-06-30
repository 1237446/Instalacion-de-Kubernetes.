# cilium
Usaremos la manera mas recomendada para instalar cilum, la cual es usando helm, el gestor de paquetes de kubernetes ademas habilitaremos el balanceo de carga layer2 para soluciones om-premise
## Instalacion de cilium en kubernetes
Añadimos el Repositorio de Helm de Cilium
```
helm repo add cilium https://helm.cilium.io/
helm repo update
```
Creamos el manifiesto yaml usando helm
```
helm template cilium cilium/cilium \
  --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set l2announcements.enabled=true \
  --set l2announcements.leaseDuration=10s \
  --set l2announcements.leaseRenewDeadline=5s \
  --set l2announcements.leaseRetryPeriod=1s \
  --set ipam.mode=kubernetes \
  --set operator.replicas=2 > cilium.yaml
```
> [!NOTE]
> **--set kubeProxyReplacement=true:** Indica a Cilium que reemplace completamente la funcionalidad de kube-proxy. Esto es fundamental para que Cilium pueda manejar el balanceo de carga L2 y las IPs de tipo LoadBalancer.

> [!NOTE]
> **--set l2announcements.enabled=true:** Habilita la característica de anuncios L2, que es la base >para la exposición de servicios.

> [!NOTE]
> **--set ipam.mode=kubernetes:** Asegura que Cilium use el controlador de IPAM de Kubernetes para la asignación de IPs a los Pods.

Una vez generado el manifiesto, lo ejecutamos 
```
kubectl apply -f cilium.yaml
```

Ahora eliminamos los pods de kube-proxy, para que cilium lo pueda reemplazar
> [!CAUTION]
> Ten en cuenta que la eliminación de kube-proxy romperá las conexiones de servicio existentes. El tráfico relacionado con los servicios se detendrá hasta que la funcionalidad de reemplazo de Cilium esté completamente instalada y operativa. Ten un plan de reversión en caso de que algo salga mal. 
```
kubectl delete daemonset -n kube-system kube-proxy
```

Verificamos el estado de cilium
```
kubectl get pods -n kube-system -l k8s-app=cilium
```

### Cilium CLI
usaremos la manera mas facil, la cual es descargando el binario directamente desde el releases de GitHub.
> [!TIP]
> Define la versión de Cilium que estás usando o la más reciente si no estás seguro Puedes encontrar la última versión en https://github.com/cilium/cilium-cli/releases
```
CILIUM_CLI_VERSION=$(curl -s https://api.github.com/repos/cilium/cilium-cli/releases/latest | grep -oP '"tag_name": "\K[^"]+')

curl -L --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz{,.sha256sum}
```

verficamos la integridad del archivo
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

Verificamos la instalacion
```
cilium version
```
Ahora verificaremos la instalacion de Cilium
```
cilium status --wait
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
