# VPNProject

> Servidor VPN WireGuard para tu casa. Conéctate desde fuera, entra en tu red
> local y navega con la IP pública de tu hogar.

Cuando estás fuera y activas el túnel:

- **Ves tu red de casa** como si estuvieras en el salón: NAS, impresora,
  cámaras, el panel del router… con sus IPs de siempre.
- **Sales a internet por tu conexión de casa.** Las plataformas de streaming
  ven la IP de tu casa, no la del hotel, la del aeropuerto o la del país donde
  estés.
- **Todo va cifrado**, incluidas las consultas DNS. En un WiFi público, nadie
  ve qué haces.

---

## Lo que tienes que hacer

Tres cosas. Sólo la segunda requiere que pienses.

```bash
git clone <este-repo> && cd VPNProject
./deploy.sh
```

Luego **abres un puerto en el router** (sección siguiente) y escaneas el código
QR que te ha pintado el script. Ya está.

`deploy.sh` detecta solo tu interfaz de red, tu IP local, tu subred y tu IP
pública, genera el `.env`, levanta el servidor y crea el primer dispositivo. No
tienes que editar ningún fichero antes de ejecutarlo.

---

## Qué necesitas

| | |
|---|---|
| Un equipo encendido en casa | Raspberry Pi, mini-PC, NAS, un portátil viejo… |
| Linux con kernel ≥ 5.6 | `uname -r` para comprobarlo |
| Docker con Compose v2 | `curl -fsSL https://get.docker.com \| sh` |
| Acceso al router | Para abrir un puerto |
| **Una IP pública de verdad** | Ni CGNAT ni nada raro — se explica más abajo |

El equipo servidor conviene que tenga **IP fija en tu red local** (reserva por
DHCP en el router). Si cambia de IP, el reenvío del puerto dejará de apuntar a
donde debe.

---

## Abrir el puerto

Es el único paso manual, y donde falla casi todo el mundo. Hay que reenviar
**un solo puerto: 51820/UDP** hasta el equipo servidor.

Ejecuta primero:

```bash
./scripts/doctor.sh
```

Te dirá cuántos routers hay en el camino y te escribirá la regla exacta de cada
uno, con las IPs ya rellenadas.

### Si tienes un solo router

Una regla y listo:

| Campo | Valor |
|---|---|
| Protocolo | **UDP** (no TCP) |
| Puerto externo | `51820` |
| Puerto interno | `51820` |
| IP destino | la del equipo servidor, p.ej. `192.168.1.50` |

### Si tienes dos routers en cascada

Es el caso típico de **router de la operadora (Huawei, Movistar, etc.) + un
segundo router (TP-Link Archer y similares) en modo router**. El segundo crea
su propia red dentro de la del primero, así que hay **dos NAT** que atravesar y
**hay que poner la regla en los dos**. Con una sola no entra nada.

Supongamos que el Huawei da la red `192.168.1.x`, el Archer da `192.168.0.x`, y
el servidor está en `192.168.0.50`:

**1. En el Archer** (el más cercano al servidor):

| Campo | Valor |
|---|---|
| Protocolo | UDP |
| Puerto externo / interno | `51820` |
| IP destino | `192.168.0.50` ← el servidor |

**2. En el Huawei** (el de la operadora):

| Campo | Valor |
|---|---|
| Protocolo | UDP |
| Puerto externo / interno | `51820` |
| IP destino | la **IP WAN del Archer**, p.ej. `192.168.1.2` |

Esa IP WAN la ves en el Archer, en la pantalla de estado, como "dirección IP de
internet" o "WAN IP". Conviene fijarla también por DHCP en el Huawei.

### Mejor todavía: quítate un router de en medio

Si el Archer sólo te hace falta por su WiFi, **ponlo en modo punto de acceso**
(*Access Point* / *modo AP* / *bridge*, según el firmware). Deja de crear una
red propia, todos los equipos quedan en la red del Huawei, y entonces **sólo
tienes que abrir el puerto en el Huawei**. Menos configuración y menos cosas que
se rompan.

---

## Antes de nada: ¿tienes CGNAT?

Si tu operadora te tiene detrás de **CGNAT**, no compartes una IP pública
propia: la compartes con más clientes. **Ningún reenvío de puertos funcionará**,
por mucho que lo configures bien.

```bash
./scripts/doctor.sh
```

La primera sección te lo dice. Si sale CGNAT, tienes tres salidas:

1. **Pedir una IP pública a tu operadora.** Muchas la dan gratis si la pides.
   Es la solución buena.
2. **Alquilar un VPS barato** y montar ahí el servidor. Pierdes la "IP de tu
   casa" para el streaming, que probablemente sea justo lo que buscabas.
3. **Usar una malla tipo Tailscale o ZeroTier**, que atraviesan CGNAT. No
   necesitan abrir puertos, pero son otro proyecto distinto a este.

Compruébalo **antes** de pelearte con los routers.

---

## Tu IP pública cambia: configura DDNS

Casi todas las conexiones domésticas tienen **IP dinámica**: la operadora te la
cambia cada cierto tiempo. Cuando eso pasa, los dispositivos que apuntaban a la
IP antigua dejan de conectar de golpe.

La solución es un dominio que se actualice solo:

1. Entra en [duckdns.org](https://www.duckdns.org), inicia sesión y crea un
   subdominio (gratis, 30 segundos).
2. Copia el **token**.
3. Ejecuta:

```bash
DUCKDNS_SUBDOMAIN=mi-casa DUCKDNS_TOKEN=tu-token-aqui ./deploy.sh
```

A partir de ahí, un contenedor mantiene `mi-casa.duckdns.org` apuntando a tu IP
actual, también después de reiniciar el equipo, y los dispositivos nuevos se
generan contra ese dominio.

> ¿Usas otro proveedor de DDNS? Deja `DUCKDNS_*` vacíos, pon tu dominio en
> `WG_HOST` dentro de `.env` y encárgate tú del registro.

**Los dispositivos creados antes de configurar DDNS siguen apuntando a la IP
literal.** Vuelve a generarlos para que usen el dominio.

---

## Tus dispositivos

```bash
./scripts/add-client.sh portatil      # dar de alta
./scripts/list-clients.sh             # ver cuáles hay y cuándo conectaron
./scripts/remove-client.sh portatil   # revocar
```

Cada dispositivo recibe sus propias claves. Te deja la configuración en
`clients/<nombre>.conf` y te pinta el código QR en la terminal.

- **Móvil**: instala [WireGuard](https://www.wireguard.com/install/) y escanea
  el QR.
- **Escritorio**: WireGuard → *Importar túnel desde archivo* → el `.conf`.

Un nombre por dispositivo. Si intentas repetir uno, el script se niega en lugar
de sobrescribir las claves del que ya existe (que dejaría de conectar sin
avisarte).

Instala `qrencode` si quieres ver los QR en la terminal:
`sudo apt install qrencode`.

### Si pierdes el móvil

```bash
./scripts/remove-client.sh movil
```

Deja de conectar **en el momento**. Te muestra sus datos y te pide confirmación
antes, porque no hay vuelta atrás: para volver a usar ese dispositivo hay que
darlo de alta otra vez, con claves nuevas. No afecta al resto.

### Elegir cuánto tráfico pasa por casa

```bash
./scripts/add-client.sh tele                 # túnel completo (por defecto)
./scripts/add-client.sh portatil --solo-lan  # sólo tu red de casa
```

| | Túnel completo | Sólo-LAN |
|---|---|---|
| Llegas a tu red de casa | Sí | Sí |
| Sales con la IP de tu casa | **Sí** | No |
| Sirve para streaming | **Sí** | No |
| Te protege en WiFi público | **Sí** | No |
| Consume la subida de tu casa | Todo el tráfico | Sólo lo que va a tu red |

El **túnel completo es el que quieres** para ver tus canales fuera de casa y
para conectarte con tranquilidad desde el WiFi de un hotel: es el modo por
defecto y no tienes que hacer nada.

El **sólo-LAN** tiene sentido en un portátil de trabajo del que sólo necesitas
llegar al NAS: no hace pasar por tu casa las descargas ni las videollamadas.
A cambio, en un WiFi público ese tráfico va sin proteger.

Puedes tener dispositivos de los dos tipos a la vez, e incluso el mismo aparato
con dos túneles importados y elegir cuál activas.

---

## Comprobar que funciona

```bash
./scripts/doctor.sh
```

Revisa la conexión, CGNAT, los niveles de NAT, el servidor, el reenvío IP, los
dispositivos y la sincronía del DDNS. Cada fallo viene con la acción concreta
que lo arregla. No toca nada: es sólo lectura.

**La prueba de verdad** es esta, y no admite discusión:

1. Coge el móvil y **apaga el WiFi** (datos móviles).
2. Activa el túnel de WireGuard.
3. Abre [whatismyip.com](https://whatismyip.com): debe salir **la IP de tu
   casa**.
4. Entra en la IP de tu router o de tu NAS: debe responder.

Comprobar un puerto UDP desde fuera no es fiable (un puerto abierto y uno
filtrado callan igual), por eso `doctor.sh` dice "no concluyente" en vez de
inventarse un diagnóstico. La conexión real desde datos móviles es lo único
que lo confirma.

---

## Cómo funciona

Tus dispositivos se conectan en **túnel completo** (`AllowedIPs = 0.0.0.0/0`):
absolutamente todo el tráfico entra por el túnel. Eso resuelve las dos cosas a
la vez —ver tu red y salir por tu IP— sin configurar ninguna ruta en el móvil.

Para llegar a los equipos de tu red, el tráfico se enmascara dos veces:

```
tu móvil (10.8.0.2)
   → túnel cifrado → servidor VPN
   → enmascarado → sale con la IP local del servidor (192.168.1.50)
   → tu NAS, tu impresora, tu router…
```

La consecuencia práctica es que **los equipos de tu casa no necesitan saber que
la VPN existe**. Ven tráfico que viene del servidor, de su misma red. Por eso no
hay que añadir rutas estáticas en el router: ese paso manual desaparece.

El precio: los equipos de tu red no distinguen qué dispositivo VPN les habla, y
no pueden iniciar conexiones hacia ellos. Para uso doméstico da igual.

<details>
<summary>Mejora opcional: ruta estática en el router</summary>

Si quieres que los equipos de tu LAN vean las IPs reales de los dispositivos VPN
(`10.8.0.x`) y puedan iniciar conexiones hacia ellos, añade en tu router una
ruta estática:

| Campo | Valor |
|---|---|
| Red destino | `10.8.0.0` |
| Máscara | `255.255.255.0` |
| Puerta de enlace | la IP local del servidor VPN |

Es opcional. Sin ella todo funciona igual para el uso normal.
</details>

---

## Mantenimiento

**Panel web.** Lo dice `deploy.sh` al terminar (algo como
`http://192.168.1.50:51821`). Sirve para ver quién está conectado, añadir o
borrar dispositivos y descargar configuraciones.

Es accesible desde tu red de casa, **nunca desde internet**: en el router sólo
se reenvía el puerto UDP del túnel, jamás el del panel. Si quieres cerrarlo aún
más, pon `WG_UI_BIND=127.0.0.1` en `.env` y entra por túnel SSH:

```bash
ssh -L 51821:127.0.0.1:51821 usuario@tu-servidor   # y abre http://localhost:51821
```

> No pongas ahí la IP local de tu servidor. Si el DHCP se la cambia, Docker no
> puede publicar el puerto y **el servidor VPN no arranca**: no se cae el panel,
> te quedas sin túnel. `doctor.sh` te avisa si detecta esa configuración.

**Copia de seguridad.** Todo el estado vive en un único volumen de Docker: las
claves del servidor y las de todos los dispositivos. Si lo pierdes, hay que dar
de alta todos los dispositivos otra vez, uno a uno.

```bash
./scripts/backup.sh                                    # crear
./scripts/backup.sh --restaurar backups/vpn-....tar.gz # restaurar
```

El fichero queda en `backups/` (fuera de git). **Contiene las claves privadas de
todos tus dispositivos en claro**: guárdalo fuera del equipo y trátalo como la
contraseña del router.

La restauración para el servidor, reemplaza el estado y lo vuelve a levantar.
Comprueba antes que el fichero es válido, así que un archivo corrupto no te deja
a medias.

**Órdenes útiles.**

```bash
docker compose ps                      # estado
docker compose logs -f wg-easy         # registros en vivo
docker compose restart wg-easy         # reiniciar
docker compose pull && ./deploy.sh     # actualizar
```

---

## Si conecta pero va mal

Hay un fallo de WireGuard que despista a todo el mundo: **el túnel conecta, las
webs pequeñas cargan, y las descargas grandes o algunas páginas se quedan
colgadas para siempre sin dar error**.

La causa es el tamaño de paquete. WireGuard usa 1420 bytes por defecto, pero si
tu conexión admite menos —el PPPoE de muchas fibras deja 1492, y detrás de dos
routers puede ser menos— los paquetes grandes se pierden. Y como los routers
domésticos suelen filtrar el aviso ICMP que lo señalaría, nadie te dice nada:
simplemente no llegan.

```bash
./scripts/doctor.sh
```

El apartado 7 lo mide y te da el número exacto. Si te dice que no cabe, añade a
`.env` la línea que te indique y vuelve a desplegar:

```bash
echo "WG_MTU=1320" >> .env    # el valor concreto lo dice el diagnóstico
./deploy.sh
```

Para volver atrás, borra esa línea y ejecuta `./deploy.sh` otra vez.

---

## Problemas frecuentes

| Síntoma | Causa habitual | Solución |
|---|---|---|
| El túnel no conecta desde fuera | Falta el reenvío del puerto, o sólo está en uno de los dos routers | Repasa "Abrir el puerto". Con dos routers hacen falta **dos** reglas |
| No conecta y `doctor.sh` dice CGNAT | Tu operadora no te da IP pública propia | Pídesela, o cambia de enfoque. No hay arreglo por configuración |
| Funcionaba y de pronto dejó de ir | Te cambió la IP pública | Configura DDNS |
| El contenedor se reinicia sin parar | Al kernel le falta WireGuard | `sudo apt install wireguard-dkms wireguard-tools` |
| Conecta pero no hay internet | Falta el enmascarado o el reenvío IP | `./scripts/doctor.sh`, apartado 3 |
| Conecta, hay internet, pero no veo mi NAS | El servidor no está en la misma subred que el NAS, o el NAS tiene cortafuegos | Comprueba la subred del servidor y las reglas del NAS |
| **Conecta pero las descargas se cuelgan a medias** | El tamaño de paquete no cabe por tu conexión | `./scripts/doctor.sh` te da el `WG_MTU` exacto. Es el fallo más común y el que menos lo parece |
| **No conecta nadie tras un corte de luz** | El reloj del equipo se desajustó, o Docker no arrancó solo | `./scripts/doctor.sh`, apartado 7 |
| El streaming me sigue viendo fuera | Fuga de DNS | Comprueba en [dnsleaktest.com](https://dnsleaktest.com) que sale tu DNS de casa |
| El panel rechaza la contraseña | Cambiaste `WG_EASY_PASSWORD` a mano | `./deploy.sh` para recalcular el hash |

---

## Seguridad

- Cada dispositivo tiene su propio par de claves. Se generan en el servidor y
  la privada sólo viaja en el fichero que tú importas.
- El puerto del panel de administración **nunca** se reenvía a internet.
- `.env` y `clients/` están en `.gitignore` y se crean con permisos `600`. No
  se sube ninguna clave al repositorio.
- Si pierdes un dispositivo, bórralo desde el panel: deja de conectar al
  instante, sin tocar a los demás.
- La contraseña del panel se guarda como hash bcrypt, que es lo único que el
  contenedor acepta.

---

## Estructura

```
VPNProject/
├── deploy.sh                 # despliegue completo, un solo comando
├── docker-compose.yml        # servidor VPN + DDNS opcional
├── .env.example              # referencia de las variables
├── scripts/
│   ├── lib.sh                # autodetección de red, utilidades, API del panel
│   ├── add-client.sh         # alta de dispositivos
│   ├── list-clients.sh       # listado de dispositivos
│   ├── remove-client.sh      # revocación de dispositivos
│   ├── backup.sh             # copia y restauración
│   └── doctor.sh             # diagnóstico (sólo lectura)
└── openspec/                 # especificación del proyecto
```

Este proyecto se desarrolla con [OpenSpec](https://github.com/Fission-AI/OpenSpec):
en `openspec/` está el porqué de cada decisión de diseño, incluidas las
alternativas que se descartaron y el motivo.
