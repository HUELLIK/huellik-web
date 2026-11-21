# HUËLLIK — ciclo de vida QR/NFC v1

## Backend preparado
- Edge Function `admin-identifiers`, JWT obligatorio.
- RPC owner-only para acciones de estado y lectura del historial.
- Sin `service_role`; la Edge Function conserva el JWT del propietario.
- Las operaciones se ejecutan dentro de una transacción PostgreSQL y bloquean la fila del identificador.
- Cada cambio escribe un evento en `petlink.audit_events` con actor, mascota, acción, estados anterior/nuevo, identificadores implicados y motivo.

## Transiciones admitidas
- `activate`: pendiente → activa.
- `mark_lost`: activa → perdida.
- `mark_found`: perdida → activa.
- `disable`: pendiente/activa/perdida → desactivada.
- `replace`: etiqueta antigua activa/perdida → sustituida y nueva etiqueta pendiente de la misma mascota → activa.

No se permite sustituir por una etiqueta vinculada a otra mascota, activar etiquetas desactivadas/sustituidas, ni repetir transiciones fuera de su estado válido. Todos los cambios requieren motivo de 8–300 caracteres.

## Historial
La RPC de auditoría solo devuelve eventos de estas transiciones. No expone ubicación de escaneos, user agents, teléfonos ni emails. Se puede filtrar por identificador y paginar.

## Importante
- No se crean identificadores nuevos desde este endpoint.
- No se migran mascotas de `public.pets` a `petlink.pets`.
- Actualmente `petlink.pets` e `identifiers` están vacías. Por ello las pruebas usan registros sintéticos dentro de una transacción que termina en ROLLBACK.
- No se añade aún UI de escritura. Antes debe probarse el backend y completarse la migración/alta de inventario de mascotas e identificadores.


## Verificación y conexión a la interfaz
- Migración `huellik_admin_identifier_lifecycle_v1` aplicada; validación adicional endurece el rechazo de acción nula.
- Edge Function `admin-identifiers` activa con `verify_jwt=true` (versión 2).
- Prueba transaccional con mascotas e identificadores sintéticos: activación, pérdida, recuperación, segunda pérdida, sustitución, desactivación y lectura del historial.
- Se comprobó que una sustitución entre mascotas diferentes se rechaza.
- Se comprobó que una acción nula se rechaza.
- La prueba verificó seis eventos de auditoría y que el historial filtra por identificador.
- Las pruebas se ejecutaron dentro de una transacción revertida; no quedan mascotas, etiquetas ni eventos de prueba.
- Permisos verificados: anon no puede ejecutar las RPC; el cuerpo comprueba el rol owner para cada petición.
- `admin.html` ahora muestra botones de transición según estado, pide confirmación y motivo, ofrece etiquetas pendientes de la misma mascota para sustitución y presenta un historial reciente.
- El JavaScript de la página se validó sintácticamente.
- No se ha probado todavía el flujo HTTP desde la sesión real del propietario en preview.
- No hay todavía identificadores reales ni mascotas en `petlink`; por tanto, no se han ejecutado acciones reales.
