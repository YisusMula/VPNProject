## Context

Ver `proposal.md` — Why para la motivación. Restricciones técnicas que
condicionan el diseño:

- El servidor corre en una máquina doméstica cualquiera (Raspberry Pi, mini-PC,
  NAS) sobre Docker. No se puede asumir nombre de interfaz, subred ni
  distribución.
- La topología real del usuario tiene **dos niveles de NAT**: router Huawei de la
  operadora → router Archer en modo router → servidor. El servidor no tiene
  credenciales de ninguno de los dos routers, por lo que el proyecto **no puede
  configurarlos**: sólo detectar la situación y decir qué regla poner en cada uno.
- La IP pública es dinámica.
- El requisito de producto es "abrir puertos y poco más". Todo lo que no sea
  abrir puertos debe ocurrir sin que el usuario lo teclee.

## Goals / Non-Goals

**Goals:**

- Un solo ejecutable (`deploy.sh`) que lleve de clon limpio a cliente conectable.
- Que el acceso a la LAN doméstica y la salida a internet por la IP de casa se
  consigan **sin tocar la configuración de los routers más allá del reenvío de
  puerto** — en concreto, sin añadir rutas estáticas.
- Diagnóstico que señale el punto exacto de fallo en la cadena Huawei → Archer →
  servidor.

**Non-Goals:**

- Configurar los routers automáticamente (no hay credenciales ni API común).
- Sortear CGNAT. Si la operadora lo aplica, el diseño lo detecta y lo declara
  bloqueante; resolverlo queda fuera de este cambio.
- Site-to-site entre dos hogares. Se elimina en este cambio.
- Alta disponibilidad, multi-usuario con roles, o cuotas de tráfico.

## Decisions

### D1 — Túnel completo (`AllowedIPs = 0.0.0.0/0`) como mecanismo único

El cliente enruta **todo** por el túnel. Esto cubre de una sola vez los dos
requisitos del producto: alcanzar la LAN de casa y salir a internet por la IP de
casa. Una sola regla, cero rutas manuales en el dispositivo cliente.

*Alternativa descartada — túnel dividido* (`AllowedIPs = 192.168.1.0/24` sólo):
daría acceso a la LAN pero no a la salida por IP del hogar, que es justamente el
requisito de streaming. Además obliga a conocer y fijar la subred LAN en cada
cliente, que es configuración que queremos eliminar.

*Coste asumido*: todo el tráfico del cliente consume el ancho de subida de la
conexión doméstica.

### D2 — El acceso a la LAN se resuelve por doble enmascaramiento, no por rutas

Ruta de un paquete de cliente VPN a un dispositivo de la LAN:

```
cliente 10.8.0.2  →[túnel]→  wg0 (contenedor)
   → MASQUERADE en el contenedor  → origen pasa a ser la IP del contenedor (172.x)
   → bridge de Docker → anfitrión
   → MASQUERADE de Docker en el anfitrión → origen pasa a ser la IP LAN del anfitrión
   → dispositivo de la LAN (responde a una IP de su propia subred)
```

La consecuencia clave es que **los dispositivos de la LAN no necesitan saber que
existe la subred VPN**: ven tráfico procedente de la IP local del servidor. Por
eso no hace falta añadir una ruta estática `10.8.0.0/24 → servidor` en el router,
que es exactamente el paso manual que queremos evitar.

*Alternativa descartada — ruta estática en el router*: es la solución "limpia"
(los dispositivos LAN verían las IPs reales de los clientes VPN y podrían
iniciar conexiones hacia ellos), pero exige entrar al Archer y al Huawei a
configurar rutas. Se documenta en el README como mejora opcional, no como paso
obligatorio.

*Coste asumido*: los dispositivos de la LAN no pueden distinguir por IP qué
cliente VPN les habla, ni iniciar conexiones hacia los clientes VPN.

*Alternativa descartada — `network_mode: host`*: elimina un nivel de
enmascaramiento y simplifica el camino, pero el contenedor pasa a competir por
puertos con los servicios del anfitrión y se pierde el aislamiento; además la
restricción del puerto de administración a la red local deja de estar en manos
de Docker.

### D3 — La gestión de claves se delega íntegramente a wg-easy

Se elimina `keys/` y las plantillas `.conf.template`. wg-easy genera el par de
claves del servidor y de cada peer y los persiste en su volumen.

*Motivo*: mantener un generador propio en paralelo al del contenedor crea dos
fuentes de verdad que pueden divergir (regenerar `keys/` sin recrear el
contenedor dejaba el servidor con claves distintas a las de los clientes, un
fallo silencioso). Delegar reduce el estado del proyecto a un único volumen.

### D4 — Imagen anclada a `wg-easy:14`, dirigida por variables de entorno

*Motivo*: la serie 14 se configura íntegramente por entorno, lo que permite un
despliegue desatendido. Las series posteriores introducen un asistente de
configuración inicial vía navegador, que obligaría al usuario a abrir la web y
rellenar un formulario — precisamente lo contrario del objetivo de este cambio.

Se ancla la etiqueta mayor para evitar que una actualización automática cambie el
modelo de configuración bajo los pies del usuario.

### D5 — No se sobrescribe `WG_POST_UP` / `WG_POST_DOWN`

La configuración actual fija `-o eth0` en las reglas de `MASQUERADE`. Ese nombre
de interfaz es el que la imagen resuelve por defecto en tiempo de arranque, pero
codificarlo lo vuelve frágil ante cualquier cambio del entorno de red de Docker.
Se retiran ambos overrides y se usan los valores por defecto de la imagen, que ya
aplican `FORWARD ACCEPT` + `MASQUERADE` sobre la interfaz de salida real.

### D6 — DDNS como servicio opcional dentro del mismo Compose

Se añade un contenedor de actualización DDNS bajo un **perfil de Compose**
(`profiles: [ddns]`), de modo que sólo arranca si el usuario aportó credenciales.
`deploy.sh` activa el perfil automáticamente cuando detecta el token en la
configuración.

Se integra DuckDNS como proveedor de primera clase (gratuito, alta sin fricción,
dos variables: dominio y token). Cualquier otro proveedor sigue siendo válido:
basta con que el usuario fije `WG_HOST` a su dominio y mantenga el registro por
su cuenta; el resto del sistema no distingue el origen del nombre.

*Motivo de meterlo en el mismo Compose y no como script con cron*: hereda
`restart: unless-stopped`, con lo que el requisito de "sigue funcionando tras un
reinicio" se cumple sin tocar systemd ni crontab.

### D7 — Autodetección: qué se detecta y cómo

| Valor | Método | Fallback |
|---|---|---|
| Interfaz de salida | ruta por defecto del sistema | abortar y pedirla |
| IP LAN y subred del servidor | dirección de esa interfaz | abortar y pedirla |
| IP pública | consulta HTTPS a un servicio de eco, con más de un proveedor | pedirla al usuario |
| Niveles de NAT / CGNAT | clasificación de los saltos de un `traceroute` | reportar como no concluyente |

El orden de precedencia es siempre: **valor explícito del usuario > valor
detectado**. La detección nunca pisa lo que el usuario escribió.

### D8 — CGNAT y doble NAT se detectan con una única sonda

Un `traceroute` a una IP pública conocida devuelve la cadena de saltos. Se
clasifica cada salto:

- salto en `100.64.0.0/10` → **CGNAT** confirmado. El reenvío de puertos no puede
  funcionar; se declara bloqueante.
- número de saltos privados (RFC1918) consecutivos antes del primer salto público
  → **número de niveles de NAT**. Dos o más ⇒ doble NAT ⇒ hay que reenviar el
  puerto en cada router de la cadena.

Una sola sonda responde a las dos preguntas que más tiempo hacen perder al
usuario.

*Alternativa descartada — consultar la IP WAN del router por UPnP*: no todos los
routers lo exponen, muchos operadores lo desactivan, y en cascada sólo
respondería el router más cercano.

### D9 — La alcanzabilidad del puerto UDP se reporta con tres estados

Comprobar un puerto UDP desde fuera no es determinista: un puerto correctamente
abierto y uno filtrado producen el mismo silencio. El diagnóstico usa por tanto:

1. **Alcanzable confirmado** si algún peer registra una negociación previa desde
   una red externa — es la única evidencia positiva incontestable.
2. **No alcanzable confirmado** si el propio servicio no escucha en el puerto.
3. **No concluyente** en el resto de casos, con la instrucción de confirmarlo
   conectando desde datos móviles.

*Motivo*: un falso "puerto cerrado" enviaría al usuario a reconfigurar dos
routers que ya estaban bien.

### D10 — Apertura automática de puertos por UPnP: descartada

Habría eliminado incluso el paso de "abrir puertos". Se descarta porque en una
cascada de dos routers UPnP sólo actúa sobre el más cercano (el Archer), dejando
el Huawei sin regla: el resultado sería un fallo silencioso y más difícil de
diagnosticar que la configuración manual. Además muchas operadoras lo desactivan
en el router principal.

### D11 — El túnel es exclusivamente IPv4

Se retira el sysctl `net.ipv6.conf.all.forwarding` del contenedor y `::/0` de las
rutas del cliente.

*Motivo*: en un equipo con IPv6 deshabilitado en el kernel — configuración
habitual en instalaciones domésticas de Raspberry Pi y en entornos
containerizados — ese sysctl no existe y el contenedor **no llega a arrancar**,
con un error que no menciona IPv6 de forma reconocible. Detectado al ejecutar el
despliegue real durante la implementación.

Los dos objetivos del producto (alcanzar la LAN doméstica y salir a internet por
la IP del hogar) se cumplen íntegramente sobre IPv4. Además el punto de conexión
del túnel es la IPv4 pública del hogar, por lo que el transporte exterior es
IPv4 en cualquier caso.

*Coste asumido*: un cliente en una red exclusivamente IPv6 sin NAT64 no podría
establecer el túnel. Se considera marginal frente al fallo de arranque que evita.

## Risks / Trade-offs

- **[CGNAT en la línea del usuario]** → El diseño lo detecta en el primer
  diagnóstico y lo declara bloqueante antes de que el usuario invierta tiempo
  configurando routers. No se intenta sortear.
- **[Doble NAT mal configurado: sólo una de las dos reglas]** → Síntoma idéntico
  a puerto cerrado. Mitigación: el diagnóstico reporta explícitamente cuántos
  niveles de NAT hay y enumera la regla que corresponde a cada router.
- **[El túnel completo satura la subida doméstica]** → Se documenta; el usuario
  puede pasar un cliente a túnel dividido editando su fichero, a costa de perder
  la salida por IP de casa.
- **[Plataformas de streaming que bloquean IPs de VPN]** → No aplica del mismo
  modo que a una VPN comercial, porque el tráfico sale por una IP residencial
  real. Riesgo residual: algunas plataformas limitan el uso simultáneo fuera del
  hogar por sus propios términos. Queda fuera del control técnico del proyecto.
- **[Los dispositivos LAN ven todo el tráfico VPN como procedente del servidor]**
  → Consecuencia aceptada de D2. Mitigación opcional documentada: ruta estática
  en el router.
- **[Anclar `wg-easy:14` deja de recibir mejoras de la serie siguiente]** →
  Aceptado a cambio del despliegue desatendido. La actualización de serie será un
  cambio propio, no un efecto colateral.
- **[Pérdida del volumen de Docker = pérdida de todas las claves]** → Todos los
  clientes dejarían de conectar y habría que regenerarlos. Se documenta el
  volumen como el único estado que merece copia de seguridad.

## Migration Plan

No hay usuarios en producción. Para un despliegue previo del esquema antiguo:

1. `docker compose down`
2. Borrar `keys/`, `server/wg0.conf` y `client/*/`.
3. Ejecutar `./deploy.sh`.
4. Redistribuir los clientes generados; los antiguos dejan de ser válidos.

Reversión: el esquema anterior queda en el historial de git; volver a él exige
regenerar claves igualmente, por lo que no se mantiene ruta de compatibilidad.
