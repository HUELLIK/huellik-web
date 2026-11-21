# HUËLLIK v2 — contratos de backend (borrador)

Los endpoints se implementarán como Supabase Edge Functions y no se desplegarán hasta contar con configuración segura. La interfaz nunca decide precios, descuentos, permisos ni derechos de Plus.

## Autenticación común

- Funciones invocadas desde el navegador: exigir sesión Supabase válida.
- Verificar identidad en backend con Supabase Auth; no confiar en el correo o UUID enviados en el cuerpo.
- Operaciones administrativas: comprobar que el UUID autenticado está en `petlink.admin_users` con rol `owner`.
- No utilizar `raw_user_meta_data` / `user_metadata` como prueba de rol.
- El acceso privilegiado a datos internos se hace solo con secretos del entorno de Edge Functions.
- CORS limitado al dominio de HUËLLIK y a previews controladas.

## Funciones previstas

### `admin-promotions`
Métodos: GET, POST, PATCH, DELETE lógico.
- GET: lista códigos, estado, periodo, límites y redenciones agregadas; no devuelve datos personales de compradores.
- POST: crea código con tipo percent/fixed, valor, scope, fechas, límite total, límite por usuario y first_time_only.
- PATCH: edita campos permitidos; si ya tiene redenciones, no cambiar su código ni el significado de descuentos anteriores.
- DELETE: desactivar (soft delete), nunca borrar redenciones.
- Todas las operaciones requieren rol owner.

### `validate-promo` (v1 desplegada)
Entrada: code y scope (Plus mensual/anual, etiqueta metálica/flexible).
- Normalizar código y validar active, starts_at, expires_at, scope, primer cliente y límites actuales.
- No acepta precio/subtotal desde el navegador, no calcula importe final y no reserva canje.
- Devuelve tipo/valor configurado y elegibilidad; el checkout debe volver a validar y reservar atómicamente.
- Respuesta genérica si no es válido; no filtra límites ni datos de otros usuarios.

### `create-checkout`
Entrada: tipo de compra, productos/plan, identificador de mascota opcional y código promocional opcional.
- Obtener catálogo y precios vigentes desde servidor.
- Validar propietario de mascota y promo.
- Crear reserva de promoción con bloqueo transaccional.
- Crear sesión Stripe Checkout con renovación desactivada salvo consentimiento explícito para suscripción.
- Guardar referencias de sesión en pedido/reserva.
- Devolver solo la URL de Checkout.

### `stripe-webhook`
- Endpoint externo sin JWT de Supabase, pero obligatorio verificar firma Stripe sobre el cuerpo original.
- Insertar `event_id` único en `webhook_events`.
- Procesar idempotentemente pago completado, pago fallido, reembolso, cancelación y cambios de suscripción.
- Solo después de pago confirmado marcar pedido pagado, redención como redeemed y crear/actualizar entitlement.
- No confiar en la URL de retorno del navegador como prueba de pago.
- No guardar PAN, CVC ni datos de tarjeta.

### `owner-dashboard`
- Resumen de pedidos, códigos promocionales, redenciones, suscripciones y mascotas/identificadores.
- Solo datos agregados necesarios; evitar exportar información privada de contacto.
- Todas las acciones mutables se validan otra vez en servidor.

## Códigos promocionales

Scopes iniciales propuestos:
- `plus_monthly`
- `plus_annual`
- `tag_metal`
- `tag_flex`
- `all`

Reglas:
- Descuento porcentual 1–100 o fijo en EUR.
- El descuento nunca supera el subtotal elegible.
- Ventana de validez con zona horaria UTC.
- Límite global y por usuario; reservas pendientes cuentan contra el límite hasta expirar o anularse.
- La comprobación de límites se hace bajo bloqueo transaccional de la fila del código.
- No aplicar códigos acumulativos salvo decisión comercial futura.
- Un descuento sobre una suscripción inicial no debe interpretarse como descuento permanente en renovaciones.

## Respuestas y errores

- 400: entrada inválida o promoción no aplicable.
- 401: no autenticado.
- 403: usuario autenticado sin permiso.
- 409: límite alcanzado o conflicto de reserva.
- 500: error interno con identificador de correlación; no incluir secretos ni trazas en respuesta pública.

## Pruebas mínimas

- Usuario anónimo intentando administrar promociones.
- Usuario normal intentando crear/modificar promociones.
- Propietario autorizado.
- Código vencido, inactivo, desconocido, alcance incorrecto y divisa incorrecta.
- Límite global/per-user con dos peticiones concurrentes.
- Pago exitoso repetido (webhook duplicado).
- Pago fallido, reembolso y cancelación.
- Plus incluido en compra con fin de periodo.
- Renovación solo con consentimiento.
