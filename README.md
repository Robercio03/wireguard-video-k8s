# WireGuard Video K8s

Helm chart para desplegar una infraestructura WireGuard sobre Kubernetes y validar la transmisión segura de vídeo entre nodos del clúster.

La solución despliega una red WireGuard entre pods ubicados en distintos nodos de Kubernetes. De forma opcional, permite ejecutar un sistema multimedia compuesto por un emisor, un receptor y un servidor HLS para comprobar que el tráfico de vídeo atraviesa el túnel WireGuard.

## Características principales

- Despliegue automatizado mediante Helm.
- Creación de un pod por nodo participante.
- Configuración dinámica de WireGuard en tiempo de arranque.
- Descubrimiento automático de las IPs de los pods mediante la API de Kubernetes.
- Gestión de claves privadas mediante `Secrets`.
- Distribución de claves públicas mediante `ConfigMap`.
- Sistema opcional de transmisión de vídeo sobre WireGuard.
- Generación de salida HLS reproducible mediante FFmpeg.
- Recogida de métricas y logs de transmisión.

## Arquitectura general

La solución está formada por tres elementos principales:

1. **Infraestructura WireGuard**  
   Cada nodo participante ejecuta un pod que incluye un contenedor WireGuard. Este contenedor crea la interfaz `wg0` y establece túneles cifrados con el resto de nodos.

2. **Sistema multimedia opcional**  
   Si `video.enabled=true`, el chart añade contenedores adicionales:
   - `video-sender`: emisor del flujo de vídeo.
   - `video-receiver`: receptor del flujo UDP.
   - `video-player`: servidor HTTP basado en Nginx para exponer la salida HLS.

3. **Automatización con Helm**  
   Toda la topología se define desde el fichero `values.yaml`, incluyendo nodos, direcciones WireGuard, claves públicas, nodos emisor/receptor y parámetros de vídeo.

## Requisitos previos

Antes de desplegar el chart es necesario disponer de:

- Un clúster Kubernetes funcional.
- Helm instalado.
- `kubectl` configurado contra el clúster.
- Al menos dos nodos Kubernetes para probar la transmisión de vídeo.
- Permisos para crear:
  - `Deployments`
  - `Services`
  - `ConfigMaps`
  - `Secrets`
  - `ServiceAccounts`
  - `Roles`
  - `RoleBindings`
- WireGuard soportado por el kernel de los nodos.
- Una imagen Docker con FFmpeg, Python y herramientas de red para los contenedores multimedia.

En MicroK8s, los comandos pueden ejecutarse con:

```bash
microk8s kubectl ...
helm ...
````

En otros entornos Kubernetes, se puede usar directamente:

```bash
kubectl ...
helm ...
```

## Estructura recomendada del repositorio

```text
.
├── Chart.yaml
├── values.yaml
├── video-tools/
|   ├── Dockerfile.video
|   └── media/
|       └── (meter el vídeo que quieras mandar .mp4)
├── templates/
│   ├── _helpers.tpl
│   ├── configmap.yaml
│   ├── deployment.yaml
│   ├── rbac.yaml
│   ├── video-configmap.yaml
│   └── video-player-svc.yaml
├── generate-wireguard-keys.sh
└── README.md
```

## 1. Clonar el repositorio

```bash
git clone git@github.com:Robercio03/wireguard-video-k8s.git
cd wireguard-video-k8s
```

## 2. Crear el namespace

```bash
kubectl create namespace wireguard
```

En MicroK8s:

```bash
microk8s kubectl create namespace wireguard
```

## 3. Generar las claves WireGuard

Cada nodo necesita un par de claves WireGuard: una clave privada y una clave pública.

Paara ello, utiliza el script proporcionado.

### generate-secrets.sh

Ejecútalo:

```bash
chmod +x scripts/generate-wireguard-keys.sh
./generate-wireguard-keys.sh
```

El script debe generar las claves privadas y públicas necesarias para cada nodo participante.

## 4. Crear los Secrets con las claves privadas

Cada clave privada debe almacenarse en un `Secret` de Kubernetes. El chart espera que cada secret contenga una clave llamada `privateKey`.

Ejemplo:

```bash
kubectl create secret generic wg-key-node-1 \
  -n wireguard \
  --from-file=privateKey=keys/node-1.private

kubectl create secret generic wg-key-node-2 \
  -n wireguard \
  --from-file=privateKey=keys/node-2.private

kubectl create secret generic wg-key-node-3 \
  -n wireguard \
  --from-file=privateKey=keys/node-3.private
```

En MicroK8s:

```bash
microk8s kubectl create secret generic wg-key-node-1 \
  -n wireguard \
  --from-file=privateKey=keys/node-1.private

microk8s kubectl create secret generic wg-key-node-2 \
  -n wireguard \
  --from-file=privateKey=keys/node-2.private

microk8s kubectl create secret generic wg-key-node-3 \
  -n wireguard \
  --from-file=privateKey=keys/node-3.private
```

## 5. Configurar `values.yaml`

Edita el fichero `values.yaml` para adaptar la topología a tu clúster.

### 5.1. Configurar los nodos

Primero obtén los nombres reales de los nodos Kubernetes:

```bash
kubectl get nodes -o wide
```

En MicroK8s:

```bash
microk8s kubectl get nodes -o wide
```

Después configura la sección `nodes`:

```yaml
nodes:
  - name: node-1
    hostname: "k8s-node-1"
    wgIP: "10.200.0.1"
    secretName: "wg-key-node-1"

  - name: node-2
    hostname: "k8s-node-2"
    wgIP: "10.200.0.2"
    secretName: "wg-key-node-2"

  - name: node-3
    hostname: "k8s-node-3"
    wgIP: "10.200.0.3"
    secretName: "wg-key-node-3"
```

Donde:

* `name`: identificador lógico usado por el chart.
* `hostname`: nombre real del nodo en Kubernetes.
* `wgIP`: IP privada asignada dentro de la red WireGuard.
* `secretName`: nombre del secret con la clave privada del nodo.

### 5.2. Configurar las claves públicas

Sustituye los valores de ejemplo por las claves públicas generadas:

```yaml
publicKeys:
  node-1: "PUBLIC_KEY_NODE_1"
  node-2: "PUBLIC_KEY_NODE_2"
  node-3: "PUBLIC_KEY_NODE_3"
```

Puedes obtenerlas con:

```bash
cat keys/node-1.public
cat keys/node-2.public
cat keys/node-3.public
```

### 5.3. Configurar WireGuard

Ejemplo:

```yaml
wireguard:
  interface: wg0
  port: 51820
  networkCIDR: "10.200.0.0/24"
```

## 6. Preparar la imagen de vídeo

El repositorio incluye un `Dockerfile` para construir la imagen utilizada por los contenedores multimedia. Esta imagen incorpora las herramientas necesarias para la transmisión y recepción de vídeo, como `ffmpeg`, `ffprobe`, `python3`, `curl` y utilidades básicas de red.

Antes de construir la imagen, es necesario incluir en el contexto de construcción un fichero de vídeo en formato MP4, dentro de la carpeta `/video-tools/media`, con el siguiente nombre:

```text
video_tfg.mp4
````

A continuación, construye la imagen:

```bash
docker build -t video-tools:0.1 .
```

Si estás utilizando MicroK8s con el registro local habilitado, etiqueta la imagen para el registro local:

```bash
docker tag video-tools:0.1 localhost:32000/video-tools:0.1
```

Y súbela al registro local:

```bash
docker push localhost:32000/video-tools:0.1
```

En ese caso, configura el `values.yaml` de la siguiente forma:

```yaml
video:
  image:
    repository: localhost:32000/video-tools
    tag: "0.1"
    pullPolicy: IfNotPresent
```

El fichero de vídeo quedará disponible dentro del contenedor en la ruta configurada en el `values.yaml`:

```yaml
video:
  source:
    inputFile: "/media/video_tfg.mp4"
```

Si se utiliza otro nombre o ubicación para el fichero de vídeo dentro de la imagen, será necesario modificar también el valor `video.source.inputFile`.


## 7. Activar o desactivar el sistema de vídeo

Por defecto, el sistema de vídeo puede estar deshabilitado:

```yaml
video:
  enabled: false
```

Para probar la transmisión multimedia, actívalo:

```yaml
video:
  enabled: true
```

Configura el nodo emisor y receptor:

```yaml
video:
  sender:
    enabled: true
    nodeName: "node-1"
    destinationWGIP: "10.200.0.3"
    destinationPort: 5004
    controlPort: 9090

  receiver:
    enabled: true
    nodeName: "node-3"
    listenPort: 5004
    senderControlURL: "http://10.200.0.1:9090/start"
    maxWaitSeconds: 3600
```

En este ejemplo:

* El emisor se despliega en `node-1`.
* El receptor se despliega en `node-3`.
* El vídeo se envía hacia `10.200.0.3:5004`.
* El receptor solicita el inicio al emisor usando `http://10.200.0.1:9090/start`.

## 8. Instalar el chart

Desde `./wireguard_chart/`:

```bash
helm install wireguard . -n wireguard
```

## 9. Comprobar WireGuard

Accede a uno de los pods:

```bash
kubectl exec -it -n wireguard <pod-node-1> -c wireguard -- sh
```

Comprueba la interfaz:

```bash
wg show
ip addr show wg0
```

## 10. Probar conectividad entre nodos WireGuard

Desde el pod del nodo emisor:

```bash
kubectl exec -it -n wireguard <pod-node-1> -c wireguard -- ping 10.200.0.3
```

Si el ping funciona, la red WireGuard está correctamente configurada.

## 11. Iniciar la prueba de vídeo

El receptor queda escuchando en el puerto UDP configurado y el emisor espera una petición HTTP en su endpoint de control.

Primero localiza el pod receptor:

```bash
kubectl get pods -n wireguard -l wireguard.node=node-3
```

Comprueba los logs del receptor:

```bash
kubectl logs -n wireguard <pod-receptor> -c video-receiver
```

Para iniciar la transmisión, ejecuta la petición desde el contenedor receptor:

```bash
kubectl exec -it -n wireguard <pod-receptor> -c video-receiver -- \
  curl http://10.200.0.1:9090/start
```

En MicroK8s:

```bash
microk8s kubectl exec -it -n wireguard <pod-receptor> -c video-receiver -- \
  curl http://10.200.0.1:9090/start
```

## 12. Consultar el estado del emisor

Desde el receptor:

```bash
kubectl exec -it -n wireguard <pod-receptor> -c video-receiver -- \
  curl http://10.200.0.1:9090/status
```

También puedes comprobar la salud del servidor de control:

```bash
kubectl exec -it -n wireguard <pod-receptor> -c video-receiver -- \
  curl http://10.200.0.1:9090/health
```

## 13. Comprobar los resultados de vídeo

Cuando finalice la recepción, comprueba que se han generado los ficheros HLS:

```bash
kubectl exec -it -n wireguard <pod-receptor> -c video-receiver -- ls -lh /hls
```

Deberías ver algo similar a:

```text
received.ts
stream.m3u8
segment_000.ts
segment_001.ts
segment_002.ts
...
```

También puedes consultar los logs:

```bash
kubectl logs -n wireguard <pod-receptor> -c video-receiver
kubectl logs -n wireguard <pod-emisor> -c video-sender
```

## 14. Ver el vídeo desde tu PC si el clúster está en una máquina remota

Si ejecutas `kubectl port-forward` dentro de una máquina virtual remota, pero quieres ver el vídeo desde tu PC local, necesitas un túnel SSH adicional.

En tu PC local:

```bash
ssh -L 8080:localhost:8080 usuario@IP_DE_LA_MAQUINA_REMOTA
```

Después, en la máquina remota, ejecuta:

```bash
kubectl port-forward -n wireguard svc/<servicio-video-player> 8080:8080
```

Finalmente, en tu PC local abre:

```text
http://localhost:8080/stream.m3u8
```

El flujo completo sería:

```text
PC local → túnel SSH → máquina remota → kubectl port-forward → Service HLS → video-player
```

## Licencia

Este proyecto se distribuye bajo licencia MIT.
