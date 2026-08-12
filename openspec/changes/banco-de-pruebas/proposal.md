## Why

Hasta ahora, cada cambio de este proyecto se ha entregado con una nota de
"alcance de la verificación" explicando qué se probó de verdad y qué contra un
simulador. Esa nota existe porque **no hay forma repetible de comprobar que el
proyecto funciona**: cada vez hay que montar el escenario a mano.

Eso tiene dos consecuencias malas:

1. Lo que se verificó una vez no se vuelve a verificar. Un cambio futuro puede
   romper la revocación, el modo sólo-LAN o el arranque del túnel y nadie se
   entera hasta que falla en casa del usuario.
2. Las pruebas contra un simulador escrito a partir de suposiciones sólo
   confirman las suposiciones. Ya ocurrió: hizo falta leer el código de la
   imagen para descubrir que la contraseña en claro estaba prohibida y que la
   decisión D5 documentaba un motivo falso.

Durante el último cambio se demostró que **sí se puede levantar un servidor
real**: compilando `wireguard-go` se obtiene un WireGuard en espacio de usuario
que funciona aunque el kernel no lo soporte. Falta convertir aquel montaje
desechable en algo que se pueda ejecutar con un comando.

Además, un fallo encontrado al revisar: en `doctor.sh`, `read` sobre una
sustitución de proceso que no imprime nada **aborta el diagnóstico bajo
`set -e`**, saltándose las secciones que quedan. Con un JSON truncado del panel
pasaba exactamente eso, y se perdían las comprobaciones de la 5 a la 7.

## What Changes

- Nuevo `tests/run-tests.sh`: prueba de extremo a extremo contra un servidor
  **real**, no simulado. Levanta el stack, ejerce el ciclo completo y comprueba
  el resultado observable de cada operación.
- Nuevo `tests/lib-test.sh`: comprobaciones unitarias de las funciones de
  detección, alimentadas con salidas fijas conocidas (trazas de NAT, respuestas
  de MTU), para cubrir los escenarios que no se pueden reproducir de verdad:
  CGNAT, doble NAT, reloj desviado.
- El banco elige por sí solo cómo obtener WireGuard: **módulo del kernel** si el
  equipo lo tiene —el caso normal en la máquina del usuario— y **espacio de
  usuario compilado** si no. Si no puede ninguno de los dos, lo dice y no
  ejecuta las pruebas que lo necesitan, en lugar de fingir que pasan.
- **Corrección**: se blinda el `read` de `doctor.sh` y se degrada al camino de
  `wg show` cuando el JSON del panel no parsea, en lugar de informar de cero
  dispositivos, que mandaría al usuario a crear uno que ya tiene.

## Capabilities

### New Capabilities
- `banco-de-pruebas`: qué garantiza una ejecución del banco, cómo se comporta
  cuando el entorno no permite ejecutar parte de las pruebas, y qué no debe
  hacer nunca (tocar la instalación real del usuario).

### Modified Capabilities
- `diagnostico-red`: el diagnóstico debe completar todas sus secciones aunque
  una respuesta del panel llegue malformada.

## Impact

- **Ficheros nuevos**: `tests/run-tests.sh`, `tests/lib-test.sh`,
  `tests/fixtures/` con las salidas fijas.
- **Ficheros modificados**: `scripts/doctor.sh` (corrección del aborto),
  `README.md`, `.gitignore`.
- **Dependencias**: ninguna nueva para usar la VPN. El banco usa Docker, que ya
  es obligatorio, y opcionalmente Go para compilar el WireGuard de espacio de
  usuario cuando el kernel no lo trae.
- **Compatibilidad**: no cambia el comportamiento del producto. El banco vive en
  `tests/` y no toca el `.env` ni el volumen de la instalación real.
