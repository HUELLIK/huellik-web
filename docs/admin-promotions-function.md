# admin-promotions — gestión de códigos HUËLLIK

Estado: desplegado y activo en Supabase con `verify_jwt = true`.

## Funciones previstas
- Listar códigos y contadores de reservas/canjes.
- Crear códigos.
- Editar condiciones.
- Desactivar sin borrar historial.
- No eliminar redenciones ni pedidos.
- El servidor valida datos y el propietario en cada operación.

## Campos
- Código de 3–40 caracteres, mayúsculas, números, guion y guion bajo.
- Descuento: porcentaje (1–100) o fijo en EUR.
- Ámbito: todo, Plus mensual, Plus anual, etiqueta metal o etiqueta flexible.
- Fecha de inicio y caducidad opcional.
- Límite global y límite por usuario.
- Solo nuevos clientes (opcional).
- Activo/inactivo.
- Recuento de reservas y canjes.

## Seguridad
La Edge Function usa JWT del usuario y clave publicable. La RPC vuelve a comprobar `auth.uid()` en `petlink.admin_users` con rol `owner`. No utiliza service_role ni expone tablas privadas. La RPC debe revisarse con especial atención porque SECURITY DEFINER omite RLS; se fija `search_path = ''`, se cualifican las tablas y se valida el propietario dentro de la función.

## Dependencias
1. Revisar y aplicar el borrador de tablas `petlink.promo_codes` y `petlink.promo_redemptions`.
2. Revisar y aplicar `docs/sql/admin-promotions-rpc-draft.sql`.
3. Desplegar `admin-promotions` con `verify_jwt = true`.
4. Probar propietario, usuario normal, anónimo, código duplicado, fechas, scopes, límites y edición después de canjes.
5. Activar la interfaz en `admin.html` tras verificar el backend.

## Reglas comerciales ya decididas
- Plus mensual y anual son alcances separados.
- El mes gratis solo se aplica al plan mensual, no al anual.
- Descuento fijo solo EUR y nunca superior al subtotal elegible (la validación de carrito será un endpoint separado).
- No se aplican descuentos automáticamente a renovaciones.
- No se activan pagos ni Stripe en esta fase.
- Los límites se volverán a comprobar transaccionalmente en el endpoint de validación/reserva antes del checkout.
