# HUËLLIK — especificación del panel de administración v1

Estado: especificación de desarrollo. No es una implementación ni autoriza despliegues.
Rama objetivo: `develop/huellik-v2`.
Producción y `main`: no modificar.

## Estado confirmado del proyecto

- La web actual es un único `index.html` con Supabase JS v2.
- La autenticación ya existe mediante Supabase Auth.
- El panel de usuario existente gestiona mascotas y datos propios.
- El rol de propietario está registrado en `petlink.admin_users` para la cuenta confirmada.
- La tabla `petlink.admin_users` tiene RLS y no concede acceso a `anon` ni `authenticated`.
- `service_role` tiene USAGE en `petlink` y permisos sobre `admin_users`.
- Todavía no hay Edge Functions desplegadas.
- El esquema `petlink` no se debe abrir a usuarios públicos ni clientes autenticados.
- La protección de `TRUNCATE` ya se retiró de los seis recursos de `public` y se verificó.

## Objetivo y navegación

Añadir una ruta lógica `/admin` (o `?admin=1` mientras la web siga siendo un único HTML) con una interfaz de administración separada del dashboard de mascotas.

El enlace "Administración" solo se muestra a la cuenta propietaria. La comprobación visual es comodidad, no control de seguridad: cada función del servidor vuelve a comprobar la sesión y el rol.

Si el usuario no ha iniciado sesión, se solicita login. Si está autenticado pero no es propietario, se devuelve 403 y no se muestra información administrativa. Nunca se confía en email, user_metadata, parámetros URL o estado local como prueba de rol.

## Secciones del panel

1. **Resumen**: número de cuentas, mascotas, pedidos, identificadores y suscripciones; indicadores de incidencias. Solo datos agregados necesarios.
2. **Promociones**: crear, editar, activar/desactivar y consultar códigos.
   - Código normalizado en mayúsculas.
   - Descuento porcentual o fijo en EUR.
   - Aplicación a HUËLLIK Plus mensual/anual, etiqueta digital o compra elegible.
   - Inicio, caducidad, límite global y límite por usuario.
   - Solo nuevos clientes, si se activa.
   - Usos reservados, canjeados y anulados.
   - El servidor calcula y valida el descuento; nunca el navegador.
3. **Usuarios**: búsqueda limitada por correo o identificador, fecha de alta y estado de derechos. No exponer datos privados innecesarios ni permitir suplantación.
4. **Mascotas e identificadores**: consulta operativa de mascotas, QR/NFC, estado perdido y asignación. No permitir cambiar propietario o reasignar una etiqueta sin un flujo auditado y confirmación explícita.
5. **HUËLLIK Plus**: derechos activos, origen (suscripción, compra incluida, promoción, regalo o administración), periodo y estado. No modificar directamente `profiles.plus_active` como fuente de verdad futura.
6. **Pedidos**: consulta de estado, importe, envío y seguimiento. Cambios de estado con validaciones y registro.
7. **Actividad administrativa**: historial inmutable de actor, acción, recurso, fecha y metadatos no sensibles.

## Contrato de servidor propuesto

Edge Functions, a implementar más adelante:
- `admin-overview`: devuelve métricas agregadas.
- `admin-promotions`: lista y gestiona promociones.
- `admin-users`: búsqueda y resumen mínimo de cuentas.
- `admin-pets`: operaciones administrativas de mascotas e identificadores.
- `admin-entitlements`: consulta y concesión/revocación de derechos con motivo.
- `admin-orders`: consulta y actualización controlada de pedidos.
- `admin-audit-log`: consulta del registro administrativo.

Todas las funciones (salvo webhooks de proveedor) deben:
1. Validar el JWT del usuario con Supabase Auth.
2. Obtener el UUID de usuario desde el JWT validado.
3. Comprobar en el servidor que ese UUID tiene `role='owner'` en `petlink.admin_users`.
4. Rechazar solicitudes sin autorización con 401/403.
5. Validar estrictamente el esquema y los permisos de cada acción.
6. Registrar las mutaciones administrativas en auditoría.
7. No devolver claves, tokens, datos de pago completos ni datos privados innecesarios.

La clave `service_role` solo puede existir en secretos del servidor. Nunca en `index.html`, JavaScript del navegador, repositorio o variables públicas.

## Acceso al esquema privado

No activar acceso directo de `anon` ni `authenticated` al esquema `petlink`. Antes de implementar las Edge Functions se debe elegir y probar una de estas vías:
- Añadir `petlink` a los esquemas expuestos de Data API, manteniendo todos los privilegios de tablas revocados a `anon` y `authenticated`, y concediendo solo los mínimos a `service_role`; o
- Mantener `petlink` fuera de los esquemas expuestos y crear RPC wrappers estrechos en `public`, con `search_path` fijado, validación y EXECUTE solo para `service_role`.

No cambiar la configuración de API hasta verificar qué vía es compatible con el proyecto y probar que usuarios anónimos y autenticados no pueden leer tablas privadas.

## Seguridad adicional pendiente de revisión

- Las funciones trigger `handle_new_user()` y `petlink.handle_new_auth_user()` aparecen ejecutables por PUBLIC en el catálogo. Revisar sus cuerpos y triggers antes de revocar EXECUTE; conservar el funcionamiento de altas de usuario.
- `get_public_pet_profile(uuid)` es una RPC SECURITY DEFINER intencional para lectura pública del perfil QR; revisar su código, fijar `search_path` y limitar estrictamente los campos devueltos.
- Fijar `search_path` en las funciones `set_updated_at()`.
- Activar protección de contraseñas filtradas en Auth después de revisar el ajuste y su efecto sobre usuarios.
- Crear índices de claves foráneas solo cuando corresponda; no eliminar índices existentes por avisos de "unused" en una base casi vacía.
- Revisar las políticas RLS de `public` y optimizar llamadas `auth.uid()` con `(select auth.uid())` en una migración separada, sin cambiar la lógica.

## Orden de implementación

1. Probar la función de autorización de propietario y el rechazo de un usuario normal.
2. Definir el acceso seguro a `petlink` para Edge Functions.
3. Implementar y probar primero `admin-overview` (solo lectura).
4. Construir la pantalla /admin en una rama de desarrollo.
5. Implementar promociones con validación transaccional y límites antiabuso.
6. Añadir vistas de usuarios, mascotas, pedidos y Plus con permisos mínimos.
7. Añadir auditoría de cada acción de escritura.
8. Pruebas de seguridad y regresión en desarrollo.
9. Solo con aprobación explícita, planificar despliegue y cambios en producción.

## Límites de alcance y coste

- No crear un proyecto Supabase adicional ni una rama Supabase de pago.
- No contratar Stripe ni activar pagos hasta que el usuario decida hacerlo.
- No ejecutar cambios en `main` ni desplegar la web durante esta fase.
- No borrar ni renombrar tablas históricas.
- La funcionalidad de pagos reales y webhooks queda fuera de esta fase.
