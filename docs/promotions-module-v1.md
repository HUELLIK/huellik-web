# HUËLLIK — módulo de promociones v1

Estado: interfaz y backend preparados en la rama de desarrollo; backend todavía no desplegado.

## Experiencia en el panel
- Formulario de creación y edición.
- Selector múltiple de alcance (Plus mensual/anual, etiqueta metálica/flexible o todos).
- Descuento porcentual o fijo en euros.
- Inicio, caducidad, límite global y límite por cuenta.
- Opción de nuevos clientes y activar/desactivar.
- Tabla con reservas y canjes.
- Desactivación lógica: no se borra historial.
- Una vez existen canjes, no se pueden alterar código, tipo/importe del descuento, divisa o productos elegibles. Sí se puede desactivar o ajustar vigencia/límites para detener usos futuros.

## Criterios de seguridad
- JWT obligatorio en Edge Function.
- Sesión validada con Auth.
- RPC vuelve a validar `auth.uid()` contra allowlist de propietario.
- Sin service_role en navegador ni en el código de esta función.
- Tablas `petlink` permanecen privadas.
- SQL con `search_path = ''` y nombres cualificados.
- Las redenciones se conservan; nunca se elimina físicamente un código.
- La función de administración no valida un carrito ni confirma descuentos: esa tarea pertenece al endpoint de validación y reserva transaccional, previo al checkout.

## Alcances actuales
`all`, `plus_monthly`, `plus_annual`, `tag_metal`, `tag_flex`.

El mes gratis no se aplica al anual. Los descuentos iniciales no implican descuento permanente en renovaciones. Divisa soportada: EUR.

## Estado de despliegue
- `admin.html`: interfaz conectada por código al endpoint `admin-promotions`.
- `supabase/functions/admin-promotions/index.ts`: borrador de Edge Function.
- `docs/sql/admin-promotions-rpc-draft.sql`: borrador de RPC.
- `docs/sql/huellik-v2-commerce-draft.sql`: borrador de tablas, no aplicado.
- No se ha ejecutado SQL, desplegado la función, activado Stripe ni modificado `main`.
