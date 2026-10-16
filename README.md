# ObraFlow — Control de gastos de construcción

ObraFlow incluye una aplicación Flutter para Android y una versión web Angular para visualizar y registrar gastos de construcción. Android utiliza **SQLite local**, Firebase Authentication y Cloud Firestore. Angular utiliza los mismos servicios Firebase y mantiene los datos privados por usuario.

> Estado documentado: **15 de octubre de 2026**. Versión móvil `2.0.1+14`, versión web `2.0.1`.

## Contenido

- [Estado actual](#estado-actual)
- [Personal y jornales](#personal-y-jornales--obraflow-20)
- [Datos reales iniciales](#datos-reales-iniciales)
- [Instalar y probar el APK](#instalar-y-probar-el-apk)
- [Flujos recomendados](#flujos-recomendados)
- [Desarrollo y validación](#requisitos-de-desarrollo)
- [Firebase y sincronización](#activar-firestore-y-publicar-las-reglas)
- [Base de datos local](#base-de-datos-local-y-sincronización)
- [Limitaciones y siguientes pasos](#limitaciones-actuales)

## Estado actual

La aplicación Android utiliza acceso con correo y contraseña, conserva los datos localmente cuando no hay conexión y sincroniza con Firestore al ingresar, después de guardar cambios o cuando el usuario pulsa **Sincronización**. La versión web Angular utiliza Firebase Authentication con correo/contraseña y Google. Cada cuenta almacena proyectos, gastos, categorías y parámetros en `users/{uid}`.

Incluye:

- dashboard financiero responsive;
- presupuesto, gasto, disponible, avance y proyección final;
- carga inicial de las dos facturas reales proporcionadas, con ocho artículos;
- historial local de gastos persistente;
- creación local de proyectos con presupuesto inicial;
- edición de nombre, ubicación y presupuesto de proyectos;
- eliminación protegida de proyectos sin gastos asociados;
- estados Activo, Pausado y Completado, con confirmación al pausar o reactivar;
- filtro inicial Activos/Pausados/Todos; Gastos y Reportes incluyen únicamente proyectos activos;
- parámetro local de IVA y desglose de subtotal, IVA y total por gasto;
- categorías editables en tabla, con caché diaria y actualización manual;
- buscador de categorías dentro del formulario de gastos;
- catálogo editable de proveedores, vacío inicialmente, y selector opcional en gastos;
- identidad visual propia compartida por Android y Angular;
- edición y eliminación de gastos con confirmación;
- detalle de presupuesto por proyecto y etapa;
- distribución entre materiales, mano de obra y otros;
- formulario rápido con cálculo automático;
- navegación para móvil, tablet y escritorio;
- temas claro y oscuro;
- cola local de cambios y sincronización efectiva con Firestore;
- reportes por rango de fechas en PDF y Excel con resumen por proyecto, categoría, factura, IVA y detalle de artículos;
- versión web responsive en Angular con las mismas reglas principales;
- módulo **Personal y jornales** en Android y Angular: trabajadores, oficios configurables, asistencia, anticipos, pagos y resumen financiero;
- tarifas históricas, distribución de jornadas entre proyectos y auditoría de correcciones de asistencia;
- integración del costo de mano de obra devengado con el gasto ejecutado del proyecto, sin volver a sumar anticipos o pagos;
- exportación de jornales a PDF y Excel desde Angular.

### Plataformas y persistencia

| Componente | Tecnología | Persistencia | Uso principal |
|---|---|---|---|
| Android | Flutter/Dart | SQLite local + Firestore | Operación en obra, incluso sin conexión |
| Web | Angular/TypeScript | Firestore + caché del navegador | Administración desde escritorio |
| Identidad | Firebase Authentication | Sesión Firebase | Correo/contraseña y Google |
| Seguridad local móvil | Biometría/PIN | Almacenamiento seguro cifrado | Desbloqueo después del primer acceso |
| Reportes | PDF y Excel | Archivo compartible | Gastos por período y jornales |

La separación por usuario se realiza bajo `users/{uid}`. Una cuenta autenticada no puede leer ni modificar los datos de otra cuenta según las reglas incluidas en el repositorio.

## Personal y jornales — ObraFlow 2.0

Abre **Personal** en el menú principal. El módulo diferencia tres conceptos:

- **Costo devengado:** nace de la asistencia y aumenta el costo ejecutado del proyecto.
- **Anticipo:** salida de caja que se compensa contra lo ganado, sin duplicar el costo.
- **Pago:** salida de caja que reduce el saldo pendiente, sin duplicar el costo.

El trabajador conserva nombre, cédula opcional, teléfono, oficio, tarifa diaria, ingreso, estado, observaciones y proyectos asignados. Al cambiar la tarifa se cierra la tarifa anterior y se crea una nueva vigencia; las asistencias ya registradas conservan la tarifa aplicada.

La asistencia admite día completo, medio día, ausencia o descanso. Una combinación trabajador/proyecto/fecha es única. La jornada puede distribuirse entre proyectos, pero el total diario no puede superar el 100 %. Cada corrección incrementa la revisión y guarda una copia de auditoría antes de reemplazar el valor vigente.

Los anticipos mayores al valor ganado quedan como crédito pendiente de compensación y nunca generan un saldo de pago negativo. Las referencias de pago repetidas para el mismo trabajador se rechazan.

> Este módulo es un control operativo de jornales. No sustituye nómina, IESS, décimos, beneficios ni otras obligaciones laborales aplicables en Ecuador.

### Flujo de Personal

1. Abre **Personal** y crea los oficios que necesites.
2. Registra al trabajador, su tarifa diaria y los proyectos a los que puede asignarse.
3. En **Asistencia diaria**, selecciona trabajador, proyecto, fecha, tipo de jornada y porcentaje de distribución.
4. Registra anticipos indicando método, referencia y proyecto opcional.
5. Registra pagos indicando período, fecha, monto, método y una referencia única.
6. Revisa el resumen por trabajador: jornadas equivalentes, ganado, anticipos, pagos, crédito por compensar y saldo pendiente.
7. En Angular, exporta el reporte de jornales a PDF o Excel.

El costo devengado se incorpora al gasto ejecutado del proyecto mediante la asistencia. Los anticipos y pagos representan movimientos de caja y no vuelven a incrementar ese costo.

## Datos reales iniciales

La migración de datos reales sustituye la demostración anterior por las facturas `001-020-000380000` y `001-020-000380009`, fechadas el 15 de agosto de 2026. Se cargan ocho líneas de compra del proveedor **Su Ferretero - Construcciones Cranbegal Cía. Ltda.**, por un total de **USD 5.234,84**, incluido **USD 451,96 de IVA**.

Como todavía no se indicó el proyecto definitivo, los movimientos se asignan a **Por asignar**. Se puede editar ese proyecto o mover cada gasto al proyecto correcto posteriormente. Algunas descripciones se transcribieron desde fotografías de baja nitidez; conviene validarlas contra el comprobante físico.

La importación utiliza identificadores fijos y una marca de migración, por lo que se ejecuta una sola vez y no duplica facturas. En Android se guarda primero en SQLite; tras iniciar sesión se envía al espacio privado `users/{uid}` de Firestore. Angular realiza la misma importación única para la cuenta autenticada. **No se deben borrar los marcadores de importación ni volver a ejecutar semillas sobre una cuenta con datos reales sin respaldo.**

## Instalar y probar el APK

1. Copia `C:\proyectos\gastos-proyectos\dist\ObraFlow-v2.0.1.apk` al teléfono Android.
2. Ábrelo desde el administrador de archivos.
3. Si Android lo solicita, permite temporalmente la instalación desde esa fuente.
4. Instala **ObraFlow Demo**.
5. Ingresa con Google, con correo y contraseña, o crea la cuenta personal una sola vez.
6. Crea un PIN local de 4 a 6 números.
7. En los accesos posteriores usa huella/biometría o el PIN.
8. Recorre Inicio, Proyectos, Gastos, Reportes y Más.

El APK usa la firma de desarrollo de Flutter. Es adecuado para pruebas directas, pero no para publicar en Google Play.

Artefacto verificado:

- ruta: `C:\proyectos\gastos-proyectos\dist\ObraFlow-v2.0.1.apk`;
- tamaño: `62.146.917` bytes;
- SHA-256: `3B7C7BA0E7C9AC93F6F5ECDF441FD754A5E2EC7C1B59524EF6AB9A568CBC7BDE`.

## Flujos recomendados

### Consultar un proyecto

1. Abre **Inicio**.
2. Selecciona un proyecto activo.
3. Revisa gasto, disponible, avance y presupuesto por etapa.

### Registrar una compra o gasto

1. Pulsa **Registrar gasto**.
2. Selecciona proyecto y categoría.
3. Revisa la fecha, que aparece automáticamente con el día actual, o selecciona otra.
4. Ingresa el número de factura y la descripción del artículo o servicio.
5. Modifica cantidad y precio unitario.
6. Verifica subtotal, porcentaje de IVA, valor del IVA y total automático.
7. Pulsa **Guardar gasto**.

El gasto se guarda en la base SQLite del celular y permanece disponible después de cerrar o reiniciar la aplicación.

Cada cambio queda marcado como `pending` y genera una operación en `sync_queue`. Con sesión iniciada, el servicio la envía a `users/{uid}` en Firestore y cambia el estado local a `synced`. Si no hay internet, el cambio permanece en SQLite y se reintenta en la siguiente sincronización.

### Crear un proyecto y presupuesto

1. Abre **Proyectos**.
2. Pulsa **Nuevo proyecto**.
3. Ingresa nombre, ubicación y presupuesto inicial en USD.
4. Pulsa **Crear proyecto**.

El proyecto queda disponible inmediatamente en el dashboard y en el formulario de gastos.

Para editarlo, abre **Proyectos**, pulsa el menú de tres puntos de la tarjeta y selecciona **Editar proyecto**. Si cambia el nombre, los gastos asociados se actualizan localmente.

Desde el mismo menú puedes **Pausar proyecto**. Se solicita confirmación y la obra deja de aparecer en Inicio cuando está seleccionado el filtro Activos, en Gastos y en Reportes. En Proyectos permanece visible para editarla o reactivarla.

También puedes elegir **Eliminar proyecto**. Para proteger la información real, la aplicación bloquea la eliminación cuando existe al menos un gasto asociado. Primero debes editar esos gastos y moverlos al proyecto correcto. Si el proyecto no tiene movimientos, se muestra una confirmación antes de eliminarlo y sincronizar el cambio con Firebase.

### Configurar el IVA

1. Abre **Más** y selecciona **Parámetros**.
2. Ingresa el porcentaje de IVA entre 0 y 100.
3. Pulsa **Guardar parámetros**.

La tasa se propone en los gastos nuevos. Cada gasto conserva su subtotal, tasa, importe de IVA y total, por lo que un cambio posterior del parámetro no altera movimientos anteriores.

### Crear una categoría

1. Abre **Más**.
2. Selecciona **Categorías**.
3. Pulsa **Nueva categoría**.
4. Selecciona Materiales, Mano de obra u Otros e ingresa el nombre.
5. Usa el menú de la categoría para editarla o eliminarla. Los gastos anteriores conservan el texto histórico.

Las categorías se consultan desde Firebase como máximo una vez cada 24 horas y se leen desde la caché local durante el resto del día. Pulsa **Actualizar** en la pantalla de categorías si necesitas traer inmediatamente un cambio realizado desde otro dispositivo.

### Administrar proveedores

1. Abre **Más → Proveedores** en Android o **Proveedores** en la navegación web.
2. Pulsa **Nuevo proveedor** e ingresa nombre, contacto y teléfono.
3. Edita o elimina registros desde la tabla/listado.
4. Al crear un gasto, el proveedor aparece vacío por defecto y es opcional. Selecciona uno del catálogo si corresponde.

En el formulario de gastos, pulsa Categoría para abrir el buscador y filtrar el catálogo por nombre.

### Exportar PDF o Excel

1. Abre **Reportes**.
2. Selecciona **Desde** y **Hasta**. Por defecto se muestra desde hace un mes hasta hoy.
3. Pulsa **Exportar PDF** o **Exportar Excel**.
4. Selecciona una aplicación del menú Compartir para guardar o enviar el archivo.

El Excel y el PDF incluyen únicamente los movimientos comprendidos entre ambas fechas, inclusive, y de proyectos activos, con resumen por proyecto, resumen por categoría, número de factura, IVA y detalle de cada artículo comprado. El período también queda impreso dentro del archivo exportado. El valor inicial es un mes calendario antes de la fecha actual hasta hoy; por ejemplo, el 15 de octubre se propone del 15 de septiembre al 15 de octubre.

También existe el [Google Sheet mensual](https://docs.google.com/spreadsheets/d/1FEQ0mIaByngWkej3-AfqKzc3kSoHLlptIEK9yRpsSpU/edit). En la pestaña `Reporte_Mensual`, cambia **Mes del reporte** para recalcular facturas, total, IVA, categorías y detalle de compras.

### Editar o eliminar un gasto

1. Abre **Gastos**.
2. Pulsa el menú de tres puntos del movimiento.
3. Selecciona **Editar** para modificar proyecto, categoría, descripción, proveedor, cantidad o precio.
4. Selecciona **Eliminar** para anularlo.

Antes de eliminar se muestra una confirmación con descripción, proyecto y monto. En Android primero se marca localmente para sincronizar la operación; al completar la sincronización se elimina el documento remoto y se limpia el registro local. Angular elimina directamente el documento de Firestore. Actualmente no existe papelera ni historial recuperable, por lo que la confirmación es la protección disponible.

### Cambiar el tema

Abre **Más** y selecciona **Cambiar tema**.

### Sincronizar manualmente en Android

1. Abre **Más → Sincronización**.
2. Revisa si existen operaciones pendientes o fallidas.
3. Pulsa la acción de sincronización cuando tengas conexión.
4. Confirma que el estado vuelva a sincronizado antes de cambiar de teléfono, cerrar sesión o reinstalar la aplicación.

No borres los datos de la aplicación ni la desinstales mientras existan cambios pendientes: SQLite contiene la copia local que todavía debe llegar a Firestore.

## Requisitos de desarrollo

- Flutter 3.44.6 o compatible;
- Dart 3.12.2 o compatible;
- Angular 22.1.x;
- Node.js compatible con Angular 22 y npm 11;
- Android SDK;
- Java 17;
- Android mínimo API 24;
- emulador Android o dispositivo con depuración USB para `flutter run`.

## Estructura

```text
gastos-proyectos/
├── README.md
├── HANDOFF.md
├── firebase.json
├── firestore.rules
├── dist/
└── apps/
    ├── mobile/
    │   ├── android/
    │   ├── ios/
    │   ├── web/
    │   ├── lib/
    │   │   ├── main.dart
    │   │   ├── firebase_options.dart
    │   │   ├── data/
    │   │   │   ├── expenses_controller.dart
    │   │   │   ├── local_database.dart
    │   │   │   ├── local_expense.dart
    │   │   │   ├── local_labor.dart
    │   │   │   └── otros modelos locales
    │   │   └── services/
    │   │       ├── export_service.dart
    │   │       ├── firebase_sync_service.dart
    │   │       ├── google_auth_service.dart
    │   │       └── local_lock_service.dart
    │   ├── test/
    │   └── pubspec.yaml
    └── web/
        ├── src/app/
        │   ├── app.ts
        │   ├── app.html
        │   ├── app.scss
        │   ├── data.service.ts
        │   ├── auth.service.ts
        │   └── labor-calculator.ts
        ├── angular.json
        └── package.json
```

## Ejecutar desde el código

```powershell
cd C:\proyectos\gastos-proyectos\apps\mobile
flutter pub get
flutter run
```

## Validación

```powershell
cd C:\proyectos\gastos-proyectos\apps\mobile
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Último resultado verificado:

- `flutter analyze`: sin problemas;
- `flutter test`: 12 pruebas aprobadas;
- `npm run build`: compilación Angular correcta;
- `npm test -- --watch=false`: 7 pruebas aprobadas;
- reglas Firestore del módulo laboral: aislamiento por usuario aprobado con emulador y Firebase CLI 14.22.0.

La compilación Angular mantiene advertencias no bloqueantes de optimización CommonJS asociadas con jsPDF/canvg.

## Ejecutar la versión web Angular

```powershell
cd C:\proyectos\gastos-proyectos\apps\web
npm install
npm start
```

Abre `http://localhost:4200`. Tras iniciar sesión, los datos se sincronizan con Firestore. Las categorías se guardan durante 24 horas en la caché del navegador para reducir lecturas; el resto de datos usa la caché administrada por Firebase durante la sesión.

No abras `src/app/app.html` directamente desde el explorador: ese archivo es una plantilla Angular y el navegador mostrará expresiones como `{{ ... }}` y `@if` sin procesar.

Para probar desde otro equipo conectado a la misma red:

```powershell
cd C:\proyectos\gastos-proyectos\apps\web
npm start -- --host 0.0.0.0
```

Luego abre `http://IP-DE-LA-PC:4200` desde el otro dispositivo. La IP puede cambiar; consúltala en la máquina que ejecuta Angular y permite el puerto únicamente en una red confiable.

Antes de ingresar, habilita en Firebase Authentication los proveedores **Correo electrónico/contraseña** y **Google**. Los dominios usados para pruebas, como `localhost` o el túnel temporal, deben constar en **Authentication → Configuración → Dominios autorizados**.

## Activar Firestore y publicar las reglas

1. En Firebase Console abre **Compilación → Firestore Database**.
2. Crea la base de datos en modo Producción y elige su ubicación definitiva.
3. Instala o ejecuta la CLI desde `apps/web`, inicia sesión y publica reglas:

```powershell
cd C:\proyectos\gastos-proyectos\apps\web
npx firebase login
npx firebase deploy --config ..\..\firebase.json --only firestore
```

La ubicación de Firestore no puede cambiarse después. Para usuarios principalmente en Ecuador, `southamerica-east1` (São Paulo) es una opción regional cercana.

Estructura sincronizada:

```text
users/{uid}/projects/{projectId}
users/{uid}/expenses/{expenseId}
users/{uid}/categories/{categoryId}
users/{uid}/providers/{providerId}
users/{uid}/settings/general
users/{uid}/workers/{workerId}
users/{uid}/workerRoles/{roleId}
users/{uid}/workerRates/{rateId}
users/{uid}/workerAttendance/{attendanceId}
users/{uid}/workerAttendanceAudit/{auditId}
users/{uid}/workerAdvances/{advanceId}
users/{uid}/workerPayments/{paymentId}
```

Las reglas de [firestore.rules](firestore.rules) solo permiten acceso cuando el `uid` autenticado coincide con el `uid` de la ruta. La importación real inicial se realiza de forma independiente y una sola vez para cada cuenta.

### Aplicación Android y consumo de Firebase

La aplicación Android está registrada con el paquete `com.gastosproyectos.gastos_mobile`. FlutterFire generó `apps/mobile/android/app/google-services.json` y `apps/mobile/lib/firebase_options.dart`.

Para minimizar el uso de la cuota gratuita, Android no mantiene listeners permanentes: lee Firestore al iniciar sesión y al solicitar una sincronización. Los cambios se guardan primero en SQLite y luego se envían. En **Más → Sincronización** se muestra el estado y se puede ejecutar una actualización manual.

Antes de probar, activa **Authentication → Proveedores de acceso → Correo electrónico/contraseña** y **Google**. Mantén el proyecto en el plan Spark y no es necesario habilitar Storage, Functions, autenticación telefónica ni servicios de IA.

### Huella y PIN local

El primer acceso en un teléfono utiliza Google o correo y contraseña de Firebase. A continuación, ObraFlow solicita crear un PIN local de 4 a 6 números. En aperturas posteriores, mientras Firebase conserve la sesión, la aplicación solicita huella/biometría y ofrece el PIN como alternativa.

- La huella es validada por Android y ObraFlow no recibe ni almacena información biométrica.
- El PIN no se guarda en texto: se almacena una huella SHA-256 con una sal aleatoria dentro del almacenamiento seguro cifrado de Android.
- La aplicación vuelve a bloquearse si permanece en segundo plano por más de 30 segundos.
- **Volver a iniciar sesión** permite recuperar el acceso con las credenciales de Firebase si se olvida el PIN.
- Cerrar sesión, cambiar de cuenta, reinstalar la aplicación o invalidar la sesión de Firebase puede requerir nuevamente correo y contraseña.

Para generar el build web de producción:

```powershell
npm run build
```

Salida: `apps/web/dist/obraflow-web/browser/`.

## Generar nuevamente el APK

```powershell
cd C:\proyectos\gastos-proyectos\apps\mobile
flutter clean
flutter pub get
flutter build apk --release
```

Salida estándar de Flutter:

```text
apps/mobile/build/app/outputs/flutter-apk/app-release.apk
```

Copia de entrega con nombre reconocible:

```text
dist/ObraFlow-v2.0.1.apk
```

## Limitaciones actuales

- el acceso móvil admite Google, correo/contraseña, huella/biometría y PIN local;
- no se almacenan todavía fotografías de comprobantes;
- no hay notificaciones push;
- no existe todavía sincronización automática bidireccional entre Firestore y Google Sheets;
- el APK actual no tiene firma de producción para Google Play;
- las tablas de períodos y sus estados están preparadas para extensión, pero la interfaz de cierre/reapertura autorizada de períodos todavía no está habilitada;
- la exportación específica de jornales a PDF/Excel está disponible actualmente en Angular; Android conserva el resumen y registro operativo, pero todavía no genera ese comprobante laboral específico;
- la gestión visual de tarifas por proyecto/período está pendiente; el modelo y `worker_rates` ya conservan el historial de la tarifa predeterminada aplicada.

## Base de datos local y sincronización

SQLite crea el archivo privado `obraflow.db` dentro del almacenamiento interno de la aplicación. Android protege esa ubicación y otras aplicaciones no pueden acceder normalmente a ella.

Tablas actuales:

- `projects`: proyectos locales y campos de identificación remota;
- `categories`: categorías iniciales y creadas por el usuario;
- `providers`: catálogo opcional de proveedores;
- `expenses`: gastos detallados, número de factura, montos en centavos, fechas UTC y estado de sincronización;
- `sync_queue`: operaciones locales pendientes de enviar a Firebase;
- `settings`: parámetros locales, incluido `iva_rate_percent`;
- `workers`, `worker_roles`, `worker_assignments`, `worker_rates`: personal, oficios, asignaciones e historial de tarifas;
- `worker_attendance`, `worker_attendance_audit`: asistencia vigente y auditoría de correcciones;
- `worker_advances`, `worker_payments`: anticipos y pagos;
- `payroll_periods`, `payroll_items`: estructura extensible para cierres de períodos;
- `labor_cost_allocations`: distribución del costo entre proyectos.

La migración SQLite **5 → 6** es incremental: solo crea tablas e índices del módulo laboral y carga los oficios iniciales con `INSERT ... IGNORE`. No elimina ni reinicializa proyectos, gastos, categorías, proveedores o parámetros existentes.

Campos clave para sincronización:

- `client_id`: identificador único generado en el celular;
- `remote_id`: identificador que devolverá Firebase;
- `updated_at`: fecha UTC de la última modificación;
- `sync_status`: `demo`, `pending`, `synced` o `failed`;
- `is_deleted`: marca transitoria usada antes de completar el borrado sincronizado; no funciona como papelera permanente;
- `attempts` y `last_error`: reintentos de la cola.

Los importes se almacenan como centavos enteros (`INTEGER`) para evitar errores de precisión monetaria.

## Próximas mejoras opcionales

La siguiente fase debe mantener las pantallas, SQLite, repositorios y servicios actuales, y reforzar estos puntos:

1. restringir las reglas al UID definitivo del propietario;
2. retirar el botón de creación de cuenta después del primer registro;
3. permitir cambiar el PIN desde Parámetros;
4. agregar fotografía y comprobantes únicamente si se decide habilitar Storage;
5. agregar auditoría y resolución avanzada de conflictos;
6. automatizar Firestore ↔ Google Sheets solo si se define un mecanismo seguro y controlado;
7. preparar firma, ficha y canal de publicación para Google Play;
8. añadir respaldo y restauración verificables de Firestore y `obraflow.db`.

## Seguridad de datos reales

- Trata el proyecto Firebase `gastos-proyecto-d2147` como producción.
- No borres proyectos o gastos para hacer pruebas. Usa registros claramente identificados como prueba.
- Un proyecto solo puede eliminarse desde la aplicación cuando no tiene gastos asociados; antes se deben reasignar sus movimientos.
- La eliminación de gastos es definitiva después de sincronizarse; actualmente no existe papelera recuperable.
- No borres marcadores de importación, no reinicialices SQLite y no ejecutes migraciones destructivas sin respaldo.
- Antes de cerrar sesión, reinstalar o cambiar de teléfono, comprueba que no existan operaciones locales pendientes.
- No agregues claves administrativas, cuentas de servicio, almacenes de claves o certificados privados al repositorio.

## Preparar el repositorio Git

La carpeta puede inicializarse como repositorio cuando se defina el remoto. El archivo `.gitignore` ya excluye compilaciones, dependencias, archivos locales y credenciales administrativas.

Debe versionarse el código fuente, pruebas, assets, archivos de bloqueo de dependencias, reglas y configuración cliente de Firebase. No deben versionarse `node_modules`, `build`, `.dart_tool`, `.angular`, `dist`, `outputs`, `local.properties`, archivos efímeros de iOS, logs, `.jks`, `.keystore` ni cuentas de servicio.

Antes de cada envío revisa cuidadosamente:

```powershell
git status
git diff --cached
```

No deben agregarse credenciales privadas al repositorio. Las credenciales administrativas de Firebase deberán existir únicamente en el backend.

## Identidad de compilación

- nombre: `ObraFlow Demo`;
- application ID: `com.gastosproyectos.gastos_mobile`;
- versión: `2.0.1+14`;
- modalidad: SQLite offline-first, Firebase Authentication con Google o correo, desbloqueo biométrico/PIN y sincronización bajo demanda con Firestore.

## Integración Git y aplicación web vigente

La rama de integración conserva mediante un commit de fusión las historias de
`main` y `feature/obraflow-2.0.1`. La aplicación web vigente (2.0.1) está en
`apps/web`; `apps/mobile` contiene Flutter. El Angular 1.9.0 en la raíz
(`src`, `public`, `test`, `angular.json`, `package*.json` y `tsconfig*.json`)
se conserva como referencia histórica. Los comandos npm y las tareas de VS Code
de la raíz todavía corresponden a esa versión antigua. Para trabajar en 2.0.1:

```powershell
cd C:\proyectos\gastos-proyectos\apps\web
npm ci
npm run build
```

En una copia nueva, antes de compilar, copia
`src/environments/firebase.config.example.ts` a
`src/environments/firebase.config.ts` y completa la configuración cliente del
proyecto autorizado. El archivo local permanece excluido de Git; la plantilla
no permite conectar con producción. No incluyas credenciales administrativas.
La compilación no ejecuta la aplicación ni sincroniza datos. No inicies la
aplicación contra producción para verificar esta integración.

La eliminación o reubicación del Angular antiguo queda para un cambio separado.
