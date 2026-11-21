# HUËLLIK — módulo de usuarios v1

## Alcance
Directorio administrativo de solo lectura, accesible únicamente al propietario.
- Búsqueda por nombre o correo electrónico.
- Paginación de 20 filas (máximo de servidor 50).
- Datos mostrados: nombre, correo, verificación de correo, fecha de alta, número de mascotas vinculadas, pedidos, último estado/intervalo de suscripción y marca de cuenta propietaria.
- No se muestran teléfonos, direcciones de envío, referencias de pago ni identificadores de proveedor.
- No hay acciones de bloqueo, borrado, cambio de correo o modificación de Plus en esta fase.

## Seguridad
- Edge Function `admin-users` exige JWT y valida sesión con Auth.
- RPC `huellik_admin_users_v1` vuelve a comprobar `auth.uid()` en `petlink.admin_users` con rol `owner`.
- Tablas `petlink` permanecen privadas; el navegador no obtiene SELECT directo.
- Búsqueda y paginación se ejecutan en servidor.
- Respuesta `no-store`; no se usa service_role.
- Se limita la búsqueda a 80 caracteres y la página a 50 resultados.

## Modelo
La fuente de identidad es `petlink.app_users`, que mantiene FK a `auth.users`. Los recuentos de mascotas se obtienen desde `public.pets.owner_id`, porque `public` sigue siendo la fuente actual de las mascotas y todavía no se ha migrado a `petlink`. Los pedidos se cuentan desde `petlink.orders`; el estado de Plus se obtiene de la suscripción más reciente en `petlink.subscriptions`. No se cambia ni migra ningún perfil de `public`.

## Pendiente
- Prueba desde la sesión real del propietario en la preview.
- Revisar con el propietario si se necesitan acciones de soporte; no añadir bloqueo ni borrado sin política, auditoría y confirmación específica.


## Estado de implementación
- RPC aplicada en Supabase y Edge Function `admin-users` desplegada con `verify_jwt=true`.
- Pruebas transaccionales: listado, búsqueda sin coincidencias, límite de página, ausencia de campos sensibles y rechazo de usuario no propietario.
- Confirmado: `anon` no puede ejecutar la RPC; `authenticated` no puede leer directamente `petlink.app_users`.
- El recuento de mascotas del listado se contrasta con la tabla viva `public.pets`; prueba de consistencia superada.
- El panel de `develop/huellik-v2` incluye búsqueda y paginación; pendiente probarlo desde el navegador con la sesión real del propietario.
