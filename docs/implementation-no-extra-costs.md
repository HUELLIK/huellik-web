# HUËLLIK v2 — implementación sin costes adicionales

## Restricción de presupuesto
No crear proyectos ni ramas de Supabase de pago. No activar servicios de pago, Stripe, dominios ni planes adicionales sin aprobación del propietario. Desarrollo en la rama GitHub `develop/huellik-v2`; producción permanece en `main` y en el proyecto Supabase existente.

## Producto confirmado
- HUËLLIK reemplaza el nombre histórico Petlink; ambas estructuras pertenecen al mismo producto.
- Perfil digital gratuito y etiquetas físicas QR/NFC.
- HUËLLIK Plus opcional para usuarios digitales y compradores de etiquetas.
- Posibilidad de incluir un periodo Plus con una compra, con renovación posterior solo si el cliente la acepta expresamente.
- Identificadores QR/NFC permanentes, únicos y reasignables únicamente con procedimiento autorizado.
- Panel de negocio exclusivo del propietario.
- Códigos promocionales configurables desde el panel: porcentaje o importe fijo, productos/planes elegibles, vigencia, límite global y por usuario, solo nuevos clientes opcional, activar/desactivar.
- Datos actuales de `public` y estructura histórica `petlink` se deben preservar durante la migración.

## Infraestructura que ya existe
- `public`: autenticación de frontend, perfiles, mascotas, contactos, historial y recordatorios.
- `petlink`: usuarios sincronizados, mascotas, miembros, contactos privados, identificadores, escaneos, pedidos, artículos de pedido, suscripciones, notificaciones y auditoría.
- No hay pagos Stripe activos ni Edge Functions desplegadas en el inventario auditado.
- `petlink` está aislado de los roles de navegador: no tiene USAGE para anon/authenticated ni políticas RLS. Mantenerlo privado hasta publicar funciones seguras.
- Las dos cuentas actuales coinciden por UUID en auth.users, public.profiles y petlink.app_users.
- La aplicación actual sigue consultando `public`; migrarla de forma gradual, no cambiarla de golpe.

## Trabajo preparado
- Rama GitHub: `develop/huellik-v2`.
- Documento de arquitectura y fases: `docs/architecture-v2.md`.
- Borrador de tablas de promociones, redenciones, derechos de Plus, webhooks y administración: `docs/sql/huellik-v2-commerce-draft.sql`.
- El SQL es un borrador no ejecutado. No constituye una migración oficial hasta generar el archivo mediante Supabase CLI en un entorno local y probarlo.

## Siguientes tareas técnicas
1. Confirmar qué cuenta de usuario es la propietaria del negocio para insertar su UUID en la allowlist privada `petlink.admin_users`.
2. Revisar la equivalencia de campos de mascotas y contactos en `public` y `petlink`; diseñar una migración reversible conservando UUID y datos.
3. Diseñar y probar Edge Functions para:
   - administración de promociones (crear, editar, desactivar, listar métricas);
   - validar y reservar promociones transaccionalmente;
   - crear Checkout para pedidos y Plus;
   - recibir webhooks Stripe firmados e idempotentes;
   - calcular derechos Plus a partir de suscripciones, compras incluidas, regalos y promociones.
4. Diseñar permisos de las tablas privadas. Nunca conceder acceso directo de cliente a tablas internas de promociones, pagos o administración.
5. Actualizar frontend en la rama de desarrollo con tienda, checkout, canje de códigos, Plus y panel de propietario, conectándolo únicamente cuando las funciones backend estén desplegadas y configuradas.
6. Probar flujos de usuario propietario, usuario normal, visitante QR, promoción válida/inválida, límites simultáneos, compra fallida, reembolso, cancelación y expiración.
7. Preparar despliegue Vercel en preview. No hacer merge a main ni activar pagos hasta la revisión final.

## Seguridad y privacidad
- La clave publishable de Supabase puede estar en el navegador; nunca exponer service_role ni claves secretas.
- No usar `raw_user_meta_data` para autorizar roles.
- La ficha pública debe devolver solo campos expresamente compartidos.
- Los escaneos solo almacenan localización aproximada con consentimiento.
- Mantener audit trail para reasignación de identificadores, cambios de promoción, pedidos y entitlements.
- Revisar protección de contraseñas filtradas y permisos de funciones SECURITY DEFINER.
- Revisar RGPD, privacidad, cookies, condiciones de compra y desistimiento antes de lanzamiento.

## Limitaciones actuales
No se puede completar el cobro real sin una cuenta Stripe y sus claves secretas configuradas en el panel seguro. El panel de administración no puede autorizar al propietario hasta confirmar qué cuenta registrada le pertenece. No se creará infraestructura Supabase de pago.
