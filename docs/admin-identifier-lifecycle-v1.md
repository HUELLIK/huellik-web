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
