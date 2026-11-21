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
La fuente de identidad es `petlink.app_users`, que mantiene FK a `auth.users`. Los recuentos de mascotas se obtienen desde `petlink.pet_members`; pedidos desde `petlink.orders`; estado de Plus se obtiene de la suscripción más reciente. No se cambia ni migra ningún perfil de `public`.

## Pendiente
- Prueba desde la sesión real del propietario en la preview.
- Revisar con el propietario si se necesitan acciones de soporte; no añadir bloqueo ni borrado sin política, auditoría y confirmación específica.
