# HUËLLIK v2 — preflight y migración heredada de mascotas

Estado: **preparación documentada; no ejecutada en Supabase**.

## Resultado de la inspección actual

La inspección de solo lectura del proyecto Supabase tgdxjfjbldlqsoeinuwm confirma:

- public.pets: 1 registro.
- public.pet_contacts: 1 registro.
- petlink.pets: 0 registros.
- petlink.identifiers: 0 registros.
- Los 2 usuarios de Auth tienen correspondencia en public.profiles y petlink.app_users.
- El propietario de la mascota actual ya existe en petlink.app_users.
- No hay colisiones de UUID entre las mascotas de origen y destino ni contactos huérfanos.
- La mascota actual tiene un public_id y el contacto asociado es privado. No se copió ni mostró ningún dato personal durante esta auditoría.

## Decisiones de diseño

### 1. Enlaces públicos heredados

El public.pets.public_id actual **no es una etiqueta física QR/NFC**. Se conserva como petlink.pets.legacy_public_id. No se crea ninguna fila en petlink.identifiers a partir de ese valor.

La ruta y la función pública antiguas deben seguir funcionando hasta que exista una nueva función de resolución compatible y se haya probado con visitantes anónimos. No cambiar el frontend ni retirar public.get_public_pet_profile(uuid) en esta fase.

### 2. Datos de mascota

Se conservan los UUID, nombre, especie, raza, sexo, fecha de nacimiento, color, descripción pública, alertas médicas, visibilidad de las alertas, estado público, modo perdido y marcas de tiempo.

La tabla nueva solo admite dog, cat y other. Se normalizan dog/perro a dog, cat/gato a cat, y cualquier otro valor a other; el valor original queda en legacy_species.

No se inventa una foto, mensaje de pérdida ni fecha de inicio de pérdida. important_information se deja vacío: no se mezclan notas de privacidad desconocida con alertas médicas.

### 3. Propietarios

El propietario se conserva mediante petlink.pet_members con rol owner. No se crean usuarios nuevos: el propietario ya está sincronizado con petlink.app_users.

### 4. Contactos

La tabla antigua permite múltiples contactos con visibilidad por contacto. petlink.pet_private_contacts solo admite una fila por mascota, así que no es un destino válido.

La propuesta crea petlink.pet_contacts, conserva cada UUID, relación, teléfono/correo, WhatsApp, orden y visibilidad. La tabla queda con RLS activado y sin acceso directo para anon ni authenticated; el acceso futuro deberá pasar por funciones backend con autorización.

## Script preparado

docs/sql/huellik-legacy-pet-migration-draft-v1.sql

El script:
- añade columnas compatibles sin borrar las existentes;
- crea la tabla plural de contactos;
- aborta si las tablas destino ya contienen datos;
- comprueba que todos los propietarios existen;
- conserva UUID y enlaces públicos heredados;
- copia los contactos sin cambiar su visibilidad;
- valida conteos, propietarios e identificadores;
- no crea etiquetas QR/NFC ni toca tablas de pedidos, Plus o promociones.

**No ejecutar hasta contar con export/backup verificable y aprobación explícita.** Para un ensayo, sustituir el COMMIT final por ROLLBACK. La migración real deberá ir en una transacción controlada, con revisión de resultados y pruebas de acceso.

## Pasos posteriores a la migración (no incluidos)

1. Implementar resolución pública compatible con legacy_public_id.
2. Adaptar ficha pública para leer solo contactos is_public = true y alertas médicas solo si show_medical_alerts = true.
3. Probar visitante anónimo y dos cuentas autenticadas distintas.
4. Probar que un usuario no puede ver ni modificar mascotas de otro.
5. Solo después, crear/inventariar etiquetas físicas reales en petlink.identifiers.
6. Mantener el frontend antiguo y las tablas public como fuente activa hasta completar pruebas y cambio controlado de frontend.
