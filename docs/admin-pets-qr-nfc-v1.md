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


## Verificación técnica
- Migración SQL aplicada: huellik_admin_pets_v1.
- RPC probada con identidad owner: devuelve arrays de mascotas e identificadores y métricas consistentes.
- Prueba de autorización: una cuenta autenticada que no es owner es rechazada.
- Permisos: anon no tiene EXECUTE; authenticated puede invocar la RPC, que vuelve a validar owner dentro del cuerpo.
- Respuesta comprobada sin campos medical_alerts ni datos de teléfono/contacto.
- Edge Function admin-pets desplegada y ACTIVE con verify_jwt=true.
- Script JavaScript de admin.html validado sintácticamente.
- La invocación HTTP desde una sesión real del propietario en el navegador sigue pendiente.

## Nota del asesor de seguridad
Supabase Advisor señala que la RPC SECURITY DEFINER es invocable por authenticated. Es una concesión intencionada para que el Edge Function pueda llamarla con el JWT del propietario: el cuerpo vuelve a comprobar auth.uid() contra petlink.admin_users y rechaza cuentas normales; EXECUTE está revocado a PUBLIC y anon. La prueba de usuario no propietario ha pasado. Se debe mantener este control y revisar el diseño si se mueve la RPC fuera del esquema API en una futura iteración.
