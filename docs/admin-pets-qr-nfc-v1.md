# HUËLLIK — módulo de mascotas y QR/NFC v1

## Alcance
Panel privado de solo lectura:
- Buscar y paginar mascotas actuales por nombre, especie, raza, código público o nombre del propietario.
- Mostrar datos básicos, propietario, fecha de alta, visibilidad, modo perdido y número de contactos.
- Mostrar identificadores registrados: tipo QR/NFC, código público, estado, mascota vinculada, alta/activación y métricas agregadas de escaneos.
- Mostrar indicadores agregados de mascotas, perfiles públicos, modo perdido, identificadores por estado y escaneos.
- No muestra teléfonos, correos de contacto, alertas médicas, mensajes privados, ubicaciones de escaneos ni user agents.
- No permite editar, eliminar, activar, desactivar, transferir o sustituir identificadores en v1.

## Fuentes actuales
- Mascotas: public.pets, porque sigue siendo la fuente real usada por la web.
- Contactos: public.pet_contacts, solo para contar relaciones.
- Propietario: public.profiles.display_name.
- QR/NFC: petlink.identifiers unida a petlink.pets.
- Escaneos: petlink.scans, solo conteo y fecha del último escaneo.

## Transición de datos
Al construir v1 hay una mascota en public.pets, pero petlink.pets, petlink.identifiers y petlink.scans están vacías. La mascota actual conserva su public_id y su enlace público heredado. Ese código no se presenta como etiqueta física QR/NFC. No se crea una vinculación ficticia ni se migran datos.

## Seguridad
- Edge Function admin-pets exige JWT y valida la sesión con Auth.
- RPC huellik_admin_pets_v1 vuelve a comprobar auth.uid() como owner en petlink.admin_users.
- EXECUTE revocado a PUBLIC y anon; authenticated puede invocar, con autorización comprobada dentro de la función.
- El navegador no recibe acceso directo a tablas petlink.
- Respuesta no-store; sin service_role.
- Solo lectura y sin exposición de campos médicos, contactos privados o geolocalización.

## Pendiente
- Prueba desde la sesión real del propietario en la preview.
- Pruebas de acceso con usuario normal y visitante anónimo.
- Diseñar migración transaccional de mascotas y contactos a petlink preservando UUID y enlaces heredados.
- Diseñar acciones de ciclo de vida de identificadores con auditoría e idempotencia antes de habilitar escrituras.
