# HUËLLIK v2 — mapa de transición de datos

Este documento registra la equivalencia entre el frontend actual (`public`) y el modelo histórico (`petlink`). No ejecutar cambios basándose solo en este mapa: cada migración debe probarse con copia de datos y validaciones de conteo.

## Identidad y perfiles

| Origen actual | Destino propuesto | Tratamiento |
|---|---|---|
| `auth.users.id` | `petlink.app_users.id` | Mantener UUID. Ya se comprobó que los dos usuarios actuales coinciden. |
| `public.profiles.id` | `petlink.app_users.id` | No duplicar identidad. Mantener tabla de perfil de presentación mientras el frontend la necesite. |
| `public.profiles.display_name` | `petlink.app_users.display_name` | Copiar solo si destino vacío o definir precedencia explícita. |
| `public.profiles.plus_active` | `petlink.subscriptions` / `petlink.entitlement_grants` | No traducir automáticamente a suscripción pagada. Revisar casos manuales; conservar el flag como compatibilidad hasta terminar la transición. |
| `public.plus_requests` | Registro histórico de solicitudes | Conservar solicitudes; no convertir solicitudes pendientes en suscripciones ni cobros. |

## Mascotas

| Origen `public.pets` | Destino `petlink.pets` | Tratamiento |
|---|---|---|
| `id` | `id` | Mantener UUID para no romper referencias. |
| `owner_id` | `petlink.pet_members(user_id, pet_id, role='owner')` | Crear una relación de propietario por mascota; validar unicidad y pertenencia. |
| `public_id` | `petlink.identifiers.public_code` | Mantener el valor actual como código público heredado para que los enlaces `?pet=` sigan funcionando. |
| `name`, `species`, `breed` | Mismos campos | Copiar sin cambiar valores. Revisar especies admitidas. |
| `sex`, `birth_date`, `color` | Sin columna equivalente | Añadir columnas compatibles a `petlink.pets` antes de migrar. |
| `public_description` | Mismo campo | Copiar. |
| `medical_alerts`, `show_medical_alerts` | Sin equivalencia exacta | Añadir columnas separadas. No exponer `important_information` hasta clasificar su contenido y visibilidad. |
| `is_public` | `is_public` | Copiar. |
| `is_lost` | `lost_mode` | Copiar; añadir `lost_message` solo cuando la familia lo haya indicado. |
| `created_at`, `updated_at` | Mismos campos | Preservar fechas. |

## Contactos

La tabla actual `public.pet_contacts` admite varios contactos por mascota y controla la visibilidad individual. `petlink.pet_private_contacts` tiene una única fila por mascota y no modela la visibilidad individual.

No se deben comprimir varios contactos en esa tabla. La propuesta es crear una tabla plural en `petlink` (por ejemplo `pet_contacts`) con:
- id UUID;
- pet_id;
- name y relationship;
- phone y email;
- whatsapp_enabled;
- is_public;
- sort_order;
- created_at.

Copiar cada contacto conservando orden y visibilidad. La tabla antigua `pet_private_contacts` puede mantenerse temporalmente para compatibilidad hasta decidir si se retira en una fase posterior.

## Identificadores QR/NFC

- Un `public_id` actual puede conservarse como `public_code` de un identificador QR de tipo heredado.
- La URL de destino debe abrir el perfil público usando el código, no exponer el UUID interno de mascota.
- Los nuevos códigos deben ser aleatorios y no predecibles.
- La tabla `petlink.identifiers` ya tiene unicidad en `public_code` y `destination_url`, y un índice parcial para limitar un identificador activo por mascota y tipo.
- No reasignar identificadores automáticamente. Sustitución, pérdida y transferencia deben generar evento de auditoría.

## Plus, pedidos y promociones

- `petlink.orders`, `petlink.order_items` y `petlink.subscriptions` ya existen. No crear duplicados.
- `petlink.subscriptions` contiene plan, estado, intervalo, precio, periodos y referencias del proveedor.
- El acceso efectivo a Plus debe calcularse mediante derechos (entitlements) derivados de suscripciones, compras con periodo incluido, regalos o promociones.
- `profiles.plus_active` no debe seguir siendo la autoridad de facturación. Mantenerlo temporalmente como lectura de compatibilidad hasta que frontend y políticas usen la nueva lógica.
- `plus_requests` no representa pago ni suscripción; conservar como histórico o convertirlo a una tabla de solicitudes solo si sigue siendo necesaria.
- Las promociones y redenciones son nuevas entidades; su SQL está en `docs/sql/huellik-v2-commerce-draft.sql`.

## Secuencia segura de migración

1. Backup/export verificable y snapshot de conteos antes de escribir.
2. Añadir columnas/tablas destino sin eliminar las originales.
3. Copiar perfiles/mascotas/miembros/contactos/identificadores con transacciones y UUID preservados.
4. Comparar conteos, UUIDs, relaciones, visibilidad y resultados de RPC pública.
5. Ejecutar pruebas RLS con dos cuentas distintas y un visitante anónimo.
6. Cambiar frontend a la nueva fuente de datos en una rama de preview.
7. Mantener compatibilidad de rutas antiguas `?pet=<public_id>`.
8. Solo tras validación, planear una fase separada para retirar dependencias antiguas. No borrar tablas durante el primer despliegue.

## Criterios de aceptación

- Ninguna mascota pierde propietario ni UUID.
- Todos los enlaces QR existentes siguen resolviendo el perfil correcto.
- Ningún contacto privado aparece en la ficha pública.
- Las alertas médicas solo aparecen con autorización explícita.
- Un usuario no puede consultar/editar mascotas de otro usuario.
- Las funciones Plus no se desbloquean por editar datos del navegador.
- Ninguna solicitud Plus se interpreta como pago recibido.
