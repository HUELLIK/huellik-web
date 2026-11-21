# HUËLLIK — validación de promociones v1

Estado: validación de elegibilidad implementada en servidor. No activa pagos, no reserva un canje y no calcula el importe final.

## Endpoint `validate-promo`
- POST autenticado con JWT de Supabase.
- Entradas: `code` y `scope` (Plus mensual/anual o etiqueta metálica/flexible).
- La identidad procede de `auth.getUser()` y `auth.uid()`, nunca del cuerpo.
- Normaliza el código en servidor y comprueba existencia, activo, inicio/caducidad y alcance.
- Comprueba condición de primer cliente contra pedidos pagados/en curso y suscripciones activas/en prueba.
- Comprueba límites contando canjes confirmados y reservas recientes (ventana de 30 minutos).
- Devuelve el tipo y valor del descuento configurado, no un total de carrito ni un precio calculado.
- Respuesta genérica para códigos desconocidos, inactivos, caducados, fuera de alcance o sin usos.

## Limitaciones deliberadas
El catálogo y los precios de etiquetas aún no están cerrados y los precios de Plus de la web están marcados como provisionales. Por tanto:
- No se acepta subtotal, precio unitario ni importe de descuento desde el navegador.
- No se declara un descuento definitivo ni se crea una redención.
- La comprobación de límites es orientativa; no reserva capacidad y no evita por sí sola dos compras simultáneas.
- El futuro `create-checkout` deberá obtener precios desde catálogo confiable, volver a validar el cupón y reservar bajo bloqueo transaccional en la misma operación de checkout.
- La reserva tendrá expiración, se anulará al fallar/cancelar checkout y solo pasará a `redeemed` tras confirmación firmada del pago.

## Seguridad
- RLS sigue activado; tablas privadas sin SELECT directo para anon/authenticated.
- RPC SECURITY DEFINER con `search_path = ''`, referencias cualificadas y permisos solo authenticated.
- Edge Function con JWT obligatorio y sin service_role.
- No hay cambios en `main`, no se habilita Stripe.
