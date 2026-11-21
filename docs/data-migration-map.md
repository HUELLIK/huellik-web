# HUËLLIK v2 — mapa de transición de datos

Este documento registra la equivalencia entre el frontend actual (public) y el modelo histórico (petlink). No ejecutar cambios basándose solo en este mapa: cada migración debe probarse con copia de datos y validaciones de conteo.

## Identidad y perfiles

| Origen actual | Destino propuesto | Tratamiento |
|---|---|---|
| auth.users.id | petlink.app_users.id | Mantener UUID. Ya se comprobó que los dos usuarios actuales coinciden. |
| public.profiles.id | petlink.app_users.id | No duplicar identidad. Mantener tabla de perfil de presentación mientras el frontend la necesite. |
| public.profiles.display_name | petlink.app_users.display_name | Copiar solo si destino vacío o definir precedencia explícita. |
| public.profiles.plus_active | petlink.subscriptions / petlink.entitlement_grants | No traducir automáticamente a suscripción pagada. Revisar casos manuales; conservar el flag como compatibilidad hasta terminar la transición. |
| public.plus_requests | Registro histórico de solicitudes | Conservar solicitudes; no convertir solicitudes pendientes en suscripciones ni cobros. |

## Mascotas

| Origen public.pets | Destino petlink.pets | Tratamiento |
|---|---|---|
| id | id | Mantener UUID para no romper referencias. |
| owner_id | petlink.pet_members(user_id, pet_id, role='owner') | Crear una relación de propietario por mascota; validar unicidad y pertenencia. |
| public_id | legacy_public_id | Preservar el UUID público heredado en una columna propia. No confundirlo con una etiqueta física ni crear un registro en petlink.identifiers. |
| name, species, breed | Mismos campos | Copiar sin cambiar valores cuando estén dentro del dominio destino; normalizar especies no reconocidas a other y conservar el valor original en legacy_species. |
| sex, birth_date, color | Columnas compatibles en petlink.pets | Añadir antes de migrar; conservar valores. |
| public_description | Mismo campo | Copiar. |
| medical_alerts, show_medical_alerts | Columnas separadas | Añadir columnas separadas. No exponer important_information hasta clasificar su contenido y visibilidad. |
| is_public | is_public | Copiar. |
| is_lost | lost_mode | Copiar; lost_message y lost_mode_started_at quedan nulos si el origen no tiene esos datos. |
| created_at, updated_at | Mismos campos | Preservar fechas. |

## Contactos

La tabla actual public.pet_contacts admite varios contactos por mascota y controla la visibilidad individual. petlink.pet_private_contacts tiene una única fila por mascota y no modela la visibilidad individual.

No se deben comprimir varios contactos en esa tabla. La propuesta es crear petlink.pet_contacts con:
- id UUID;
- pet_id;
- name y relationship;
- phone y email;
- whatsapp_enabled;
- is_public;
- sort_order;
- created_at.

Copiar cada contacto conservando UUID, orden y visibilidad. La tabla nueva debe tener RLS activado y no conceder acceso directo a anon/authenticated; el acceso futuro debe pasar por funciones backend autorizadas. La tabla antigua petlink.pet_private_contacts se mantiene temporalmente para compatibilidad hasta decidir si se retira en una fase posterior.

## Identificadores QR/NFC

- Los public_id actuales son identificadores de ruta de perfil heredados, no inventario físico de etiquetas.
- Se conservan en petlink.pets.legacy_public_id para resolver los enlaces antiguos ?pet=<public_id>.
- La nueva RPC public.resolve_public_pet_profile(p_code) admite códigos físicos mediante ?tag=<public_code>, UUID heredados y compatibilidad temporal con la ficha antigua.
- Solo se resuelven etiquetas activas; etiquetas desactivadas/perdidas/reemplazadas y perfiles privados devuelven not_found.
- No crear identificadores QR/NFC a partir de public_id. Las etiquetas físicas deben tener códigos aleatorios propios y filas reales en petlink.identifiers.
- La URL heredada debe seguir resolviendo el perfil correcto hasta que la nueva función pública y el frontend estén probados.
- No reasignar identificadores automáticamente. Sustitución, pérdida y transferencia deben generar evento de auditoría.

## Plus, pedidos y promociones

- petlink.orders, petlink.order_items y petlink.subscriptions ya existen. No crear duplicados.
- petlink.subscriptions contiene plan, estado, intervalo, precio, periodos y referencias del proveedor.
- El acceso efectivo a Plus debe calcularse mediante derechos (entitlements) derivados de suscripciones, compras con periodo incluido, regalos o promociones.
- profiles.plus_active no debe seguir siendo la autoridad de facturación. Mantenerlo temporalmente como lectura de compatibilidad hasta que frontend y políticas usen la nueva lógica.
- plus_requests no representa pago ni suscripción; conservar como histórico o convertirlo a una tabla de solicitudes solo si sigue siendo necesaria.
- Las promociones y redenciones son nuevas entidades; su SQL está en docs/sql/huellik-v2-commerce-draft.sql.

## Secuencia segura de migración

1. Backup/export verificable y snapshot de conteos antes de escribir.
2. Añadir columnas/tablas destino sin eliminar las originales.
3. Copiar perfiles/mascotas/miembros/contactos con transacción y UUID preservados.
4. Comparar conteos, UUIDs, relaciones, visibilidad y resultados de RPC pública.
5. Ejecutar pruebas RLS con dos cuentas distintas y un visitante anónimo.
6. Cambiar frontend a la nueva fuente de datos en una rama de preview.
7. Mantener compatibilidad de rutas antiguas ?pet=<public_id>.
8. Solo tras validación, planear una fase separada para retirar dependencias antiguas. No borrar tablas durante el primer despliegue.

## Criterios de aceptación

- Ninguna mascota pierde propietario ni UUID.
- Todos los enlaces QR existentes siguen resolviendo el perfil correcto.
- Ningún contacto privado aparece en la ficha pública.
- Las alertas médicas solo aparecen con autorización explícita.
- Un usuario no puede consultar/editar mascotas de otro usuario.
- Las funciones Plus no se desbloquean por editar datos del navegador.
- Ninguna solicitud Plus se interpreta como pago recibido.

## Estado de preflight (2026-11-21)

Se verificó en solo lectura: 1 mascota y 1 contacto en public; 0 mascotas y 0 identificadores en petlink; los 2 usuarios Auth están sincronizados con petlink.app_users; el propietario de la mascota existe en el destino; no hay UUID de mascota duplicados entre origen y destino ni contactos huérfanos.

La mascota actual tiene un contacto privado. No se migró ningún dato ni se modificó el esquema. El script propuesto está en docs/sql/huellik-legacy-pet-migration-draft-v1.sql y la revisión detallada en docs/legacy-pet-migration-preflight-v1.md.
