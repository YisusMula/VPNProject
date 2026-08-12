## 1. Medición del tamaño de paquete

- [x] 1.1 Implementar `detect_path_mtu()` en `lib.sh` con sondas de tamaño decreciente y bit de no fragmentar (decisión D1). Verificar: devuelve un valor coherente con el MTU de la interfaz de salida
- [x] 1.2 Devolver estado no concluyente si falta `ping` o ninguna sonda obtiene respuesta, sin abortar. Verificar: con `ping` ausente, la función no tumba al script llamante
- [x] 1.3 Añadir la comprobación a `doctor.sh`: comparar el MTU del camino menos 80 con el que usa el túnel. Verificar: la salida muestra ambos valores
- [x] 1.4 Al detectar margen insuficiente, indicar el `WG_MTU` concreto y describir el síntoma (transferencias que se cuelgan). Verificar: forzar el escenario y comprobar el texto
- [x] 1.5 Exponer `WG_MTU` en `docker-compose.yml` sin valor por defecto. Verificar: `docker compose config` no fija MTU si la variable está vacía

## 2. Hora del sistema

- [x] 2.1 Implementar `detect_clock_skew()` en `lib.sh` usando la cabecera `Date` de una petición HTTPS (decisión D2). Verificar: devuelve una desviación cercana a cero en un equipo en hora
- [x] 2.2 Devolver estado no concluyente si no hay referencia externa. Verificar: forzar URLs inválidas y comprobar que no aborta
- [x] 2.3 Añadir la comprobación a `doctor.sh` con umbral de 60 segundos. Verificar: simular una desviación grande y comprobar el aviso
- [x] 2.4 Explicar en el aviso la relación entre la hora y el fallo de conexión, e indicar cómo corregirlo de forma permanente. Verificar: la salida menciona ambas cosas

## 3. Arranque automático

- [x] 3.1 Añadir a `doctor.sh` la comprobación de que el servicio de contenedores arranca con el equipo (decisión D3). Verificar: la salida refleja el estado real del sistema
- [x] 3.2 Indicar el comando exacto de habilitación cuando esté deshabilitado. Verificar: la salida contiene `systemctl enable docker`
- [x] 3.3 Declarar no concluyente si no hay gestor de servicios reconocible, nunca fallo. Verificar: sin `systemctl` en el PATH, la comprobación no falla

## 4. Registros acotados

- [x] 4.1 Añadir política de rotación a los dos servicios de `docker-compose.yml` (decisión D5). Verificar: `docker compose config` muestra `max-size` y `max-file` en ambos
- [x] 4.2 Comprobar que el contenedor sigue arrancando con la política aplicada. Verificar: levantar el stack y consultar su estado

## 5. El despliegue verifica el túnel

- [x] 5.1 Sustituir en `deploy.sh` la comprobación basada en el panel por una que verifique la interfaz del túnel (decisión D4). Verificar: `bash -n deploy.sh`
- [x] 5.2 Informar de despliegue incorrecto si el túnel no existe, indicando dónde mirar la causa. Verificar: reproducir un servidor sin túnel y comprobar el mensaje
- [x] 5.3 Mantener el despliegue correcto cuando el túnel sí existe. Verificar: desplegar contra un servidor con túnel operativo

## 6. Coherencia del puerto externo

- [x] 6.1 Calcular en `doctor.sh` el puerto de cara al exterior a partir de `WG_CONFIG_PORT`, con `WG_PORT` de respaldo (decisión D6). Verificar: con ambos definidos y distintos, se usa el externo
- [x] 6.2 Señalar en las reglas de reenvío que el puerto externo y el interno son distintos cuando lo sean. Verificar: la salida distingue origen y destino
- [x] 6.3 Mantener el comportamiento actual cuando coinciden. Verificar: sin `WG_CONFIG_PORT`, el consejo no cambia

## 7. Documentación

- [x] 7.1 Documentar el problema del tamaño de paquete, su síntoma y cómo aplicar el valor que indica el diagnóstico. Verificar: la sección existe
- [x] 7.2 Añadir a la tabla de problemas frecuentes la fila de transferencias que se cuelgan. Verificar: la fila existe
- [x] 7.3 Añadir la fila de "no conecta tras un corte de luz" cubriendo hora del sistema y arranque automático. Verificar: la fila existe
- [x] 7.4 Documentar `WG_MTU` en `.env.example` con el criterio para calcularlo. Verificar: el comentario explica el margen de 80 bytes

## 8. Verificación final

> **Alcance de la verificación.** Este cambio se pudo verificar mucho mejor que
> los anteriores: se compiló `wireguard-go` desde fuente y se construyó una
> imagen de prueba con implementación en espacio de usuario, lo que permitió
> levantar un `wg-easy` **real** con una interfaz `wg0` real pese a que el
> kernel de este entorno no soporta WireGuard (`CONFIG_WIREGUARD is not set`).
>
> Contra ese servidor real se comprobaron, con túnel establecido y negociación
> confirmada: el alta de dispositivos, el listado, la revocación (verificando
> que el cliente revocado deja de recibir respuesta), el enrutado del modo
> sólo-LAN (sólo la subred doméstica pasa por el túnel, la ruta por defecto no),
> el despliegue completo con túnel operativo y el despliegue con el túnel roto.
>
> Con ello quedan cerrados los pendientes que arrastraban los dos cambios
> anteriores.
>
> La sonda de MTU se validó contra un enlace de MTU conocido (1400): mide
> exactamente 1400 y la frontera es correcta (1372 pasa, 1373 no). El propio
> entorno reproduce el problema que este cambio persigue —camino de 1400 con
> túnel de 1420—, así que la rama de fallo se ejercitó de verdad, no simulada.
>
> No verificable aquí: la desviación horaria por encima del umbral (el reloj de
> este entorno está en hora) y el arranque automático deshabilitado.

- [x] 8.1 `bash -n` sobre todos los scripts. Verificar: sin salida
- [x] 8.2 `shellcheck` a nivel de warning sin avisos. Verificar: `shellcheck -S warning deploy.sh scripts/*.sh`
- [x] 8.3 Validar el cambio en OpenSpec. Verificar: `openspec validate robustez-operativa --strict`
- [x] 8.4 Ejecutar el diagnóstico completo contra el servidor real y revisar las secciones nuevas. Verificar: cada comprobación emite un veredicto coherente con el entorno
