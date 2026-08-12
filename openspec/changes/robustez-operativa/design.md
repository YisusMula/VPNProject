## Context

Ver `proposal.md` — Why: los seis puntos están comprobados sobre el proyecto
actual, no supuestos.

El rasgo común de todos ellos es que **ninguno impide desplegar**. El despliegue
sale bien, el túnel conecta, y el problema aparece después: al descargar algo
grande, tras un corte de luz, o meses más tarde cuando la tarjeta SD se llena.
Por eso el sitio natural para casi todos es el diagnóstico, no el despliegue.

## Goals / Non-Goals

**Goals:**

- Que el diagnóstico detecte las condiciones del anfitrión que rompen la VPN de
  forma no evidente, y las traduzca a una acción concreta.
- Que el despliegue no pueda declarar éxito con el túnel roto.
- Que el paso del tiempo, por sí solo, no tumbe el equipo.

**Non-Goals:**

- Corregir automáticamente la hora, habilitar servicios o cambiar el MTU sin
  que el usuario lo decida. El diagnóstico es de sólo lectura y así se queda.
- Monitorización continua o alertas. El diagnóstico se ejecuta cuando el usuario
  quiere.
- Ajustar el MTU por cliente.

## Decisions

### D1 — El MTU se mide con sondas de tamaño creciente y bit de no fragmentar

Se envían paquetes con el bit *don't fragment* activo y tamaño decreciente hasta
que uno pasa. El mayor que pasa determina el MTU del camino.

*Motivo*: es la única medida fiable cuando el ICMP de "fragmentación necesaria"
viene filtrado, que es precisamente el caso que produce el agujero negro. Leer el
MTU de la interfaz local no vale: el cuello de botella suele estar en el enlace
del operador, no en la tarjeta de red del servidor.

El margen que necesita WireGuard sobre el MTU del camino es de **80 bytes** para
IPv4 (20 de IP + 8 de UDP + 32 de cabecera y etiqueta de WireGuard + 20 de
margen de seguridad). El valor recomendado es por tanto `MTU_camino - 80`.

*Alternativa descartada — fijar un valor conservador por defecto* (por ejemplo
1280, que siempre funciona): penaliza el rendimiento de todos los usuarios cuyo
camino sí admite 1420, que son mayoría. Se prefiere medir y avisar sólo cuando
hace falta.

*Alternativa descartada — corregirlo automáticamente*: el diagnóstico es de sólo
lectura por diseño, y una medida puntual puede no representar todos los caminos
que el cliente usará.

### D2 — La hora se compara contra la cabecera `Date` de una petición HTTPS

Se usa la cabecera `Date` de la misma consulta que ya sirve para obtener la IP
pública, en lugar de añadir una dependencia de cliente NTP.

*Motivo*: no requiere instalar nada, y la precisión de segundos sobra: el margen
que importa para WireGuard es de minutos.

*Umbral*: se avisa a partir de **60 segundos** de desviación. WireGuard tolera
cierto desfase, pero un reloj retrasado respecto al último intercambio registrado
hace que el servidor descarte los intentos del cliente por parecer repeticiones.
El caso real que se quiere cubrir —Raspberry Pi sin reloj con pila tras un corte
de luz— produce desviaciones de horas o días, muy por encima del umbral.

### D3 — El arranque automático se comprueba, no se habilita

Se consulta el estado del servicio y, si no arranca con el equipo, se da el
comando exacto.

*Motivo*: habilitar un servicio del sistema es una acción con efectos fuera del
proyecto. El diagnóstico no debe tener efectos secundarios; el usuario decide.

Si no hay gestor de servicios reconocible, la comprobación se declara **no
concluyente**, no fallida: hay sistemas donde Docker se gestiona de otra forma.

### D4 — El despliegue verifica la interfaz del túnel, no el panel

`deploy.sh` deja de considerar suficiente que responda el panel. Pasa a
comprobar que el túnel existe realmente dentro del contenedor.

*Motivo*: el servidor web y el túnel son independientes. El panel puede responder
con el túnel caído, y de hecho lo hizo durante el desarrollo. Un despliegue que
informa de éxito con el túnel roto es peor que uno que falla: manda al usuario a
configurar el router para un problema que no está ahí.

### D5 — Rotación de registros acotada en el propio Compose

Se limita el tamaño y el número de ficheros de registro por servicio.

*Motivo*: una línea de configuración que elimina un modo de fallo lento y difícil
de atribuir —el disco se llena y cae todo el equipo, no sólo la VPN—. El
histórico que se pierde no tiene valor: para diagnosticar sirve lo reciente.

### D6 — El puerto externo se distingue del interno en los consejos

El diagnóstico calcula el puerto de cara al exterior a partir de la variable
correspondiente, con el puerto de escucha como respaldo, y cuando difieren lo
señala en cada regla de reenvío.

*Motivo*: un consejo que nombra el puerto equivocado es peor que ninguno, porque
el usuario configura el router y sigue sin funcionar, sin motivo aparente.

## Risks / Trade-offs

- **[La sonda de MTU mide un camino, no todos]** → El camino desde el servidor a
  internet no tiene por qué coincidir con el de un cliente en itinerancia. Se
  presenta como indicio accionable, no como verdad absoluta, y sólo se avisa
  cuando el margen es insuficiente.
- **[La sonda de MTU necesita `ping` y respuesta a ICMP]** → Si el destino no
  responde, la comprobación queda no concluyente. Se acepta: es preferible a
  inventar un valor.
- **[La hora tomada de una cabecera HTTP puede desviarse unos segundos]** →
  Irrelevante frente a un umbral de 60 segundos y a los desfases reales que se
  quieren detectar.
- **[Acotar los registros pierde histórico antiguo]** → Aceptado a cambio de que
  el disco no se llene. Quien necesite histórico puede cambiar la política.
- **[Un usuario con `WG_MTU` mal puesto empeora su conexión]** → El diagnóstico
  da el valor calculado en lugar de dejarlo a la intuición, y se documenta cómo
  volver atrás.
