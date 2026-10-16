# Traspaso integral — ObraFlow

Última recopilación: **14 de octubre de 2026**
Workspace: `C:\proyectos\gastos-proyectos`

Este documento permite continuar el proyecto en otro chat sin depender del historial anterior. El archivo principal para uso cotidiano sigue siendo `README.md`; este documento agrega decisiones, infraestructura, datos conocidos, riesgos y pendientes.

## Texto listo para iniciar el siguiente chat

> Continúa el proyecto ObraFlow ubicado en `C:\proyectos\gastos-proyectos`. Antes de modificarlo, lee completos `HANDOFF.md` y `README.md`, revisa el estado actual de los archivos y conserva todos los datos existentes. Es una aplicación con datos reales: no borres, reinicialices ni reemplaces información de SQLite, Firebase o Google Sheets sin mi confirmación explícita. Android es Flutter con SQLite offline-first y sincronización a Firestore; la web es Angular y usa el mismo espacio privado `users/{uid}`. Mantén el proyecto Firebase `gastos-proyecto-d2147`, el aislamiento por UID y el objetivo de bajo consumo/costo. La última función agregada permite eliminar proyectos solamente cuando no tienen gastos, con confirmación. Antes de entregar cualquier cambio ejecuta análisis, pruebas y compilación correspondientes, actualiza la documentación y genera un nuevo APK si el cambio afecta Android.

## Objetivo y criterios del producto

**ObraFlow** controla presupuestos y gastos de proyectos de construcción desde Android y web. Debe funcionar sin conexión en el teléfono, sincronizar cuando exista sesión e internet, separar los datos por usuario y mantener los costos de Firebase bajos.

Restricciones que deben mantenerse:

- Los datos actuales son reales y no deben perderse.
- Toda eliminación visible debe pedir confirmación.
- Un proyecto con gastos asociados no se puede eliminar; primero hay que mover sus gastos a otro proyecto.
- La eliminación actual de gastos termina en borrado físico local/remoto; no existe todavía papelera ni auditoría recuperable. La confirmación es obligatoria.
- La información de cada cuenta vive únicamente bajo `users/{uid}`.
- Evitar listeners permanentes en Android para reducir lecturas de Firestore.
- No agregar servicios pagados si no son necesarios; actualmente el plan esperado es Firebase Spark.
- No subir claves administrativas, archivos de firma ni secretos al repositorio.

## Arquitectura y carpetas

```text
gastos-proyectos/
├── README.md                  Manual de uso, desarrollo y compilación
├── HANDOFF.md                 Este traspaso integral
├── .firebaserc                Proyecto Firebase predeterminado
├── firebase.json              Reglas, índices y emulador Firestore
├── firestore.rules            Aislamiento por UID
├── firestore.indexes.json     Sin índices compuestos adicionales
├── apps/
│   ├── mobile/                Flutter/Android; SQLite offline-first
│   │   ├── lib/data/          Modelos, controlador y base local
│   │   ├── lib/services/      Firebase, Google, PIN/biometría, exportación
│   │   ├── lib/main.dart      UI principal
│   │   ├── android/           Proyecto Android
│   │   └── test/              Pruebas Flutter
│   └── web/                   Angular; acceso directo a Firebase
│       ├── src/app/           UI, auth, modelos y servicio de datos
│       └── test/              Pruebas de reglas Firestore
├── dist/                      APK de entrega; generado, no recomendado para Git
└── outputs/                   Reportes/archivos generados; no recomendado para Git
```

Flujo de datos:

```text
Android UI → SQLite obraflow.db → sync_queue → Firestore users/{uid}/...
Angular UI ─────────────────────────────────→ Firestore users/{uid}/...
                                             ↕
                                     Firebase Authentication

Google Sheet: reporte complementario creado y alineado manualmente;
no es actualmente una sincronización bidireccional en tiempo real.
```

## Estado funcional consolidado

### ObraFlow 2.0 — Personal y jornales

Se incorporó el módulo laboral en Flutter y Angular con trabajadores activos/inactivos, oficios configurables, asignación a varios proyectos, tarifa diaria e historial de tarifas. Incluye asistencia completa/media/ausente/descanso, anticipos, pagos parciales y cálculo de ganado/saldo/crédito por compensar.

La asistencia usa un ID determinista `workerId_projectId_fecha`, impide duplicados dentro del proyecto y limita la suma diaria de distribuciones entre proyectos al 100 %. Las correcciones incrementan `revision` y guardan el valor previo en `worker_attendance_audit` / `workerAttendanceAudit`.

El costo devengado de la asistencia se suma al costo ejecutado del proyecto. Anticipos y pagos se muestran como flujo de caja y reducen el saldo laboral, pero no vuelven a aumentar el costo ejecutado. Angular exporta el período seleccionado a PDF y Excel.

SQLite subió de versión 5 a 6 mediante migración aditiva. No se desplegaron reglas ni se modificaron datos de Firebase real durante el desarrollo.

### Autenticación y seguridad local

- Firebase Authentication por correo/contraseña y Google.
- En Android, después de autenticar por primera vez, el usuario crea un PIN local de 4 a 6 dígitos.
- Aperturas posteriores permiten biometría/huella o PIN mientras Firebase mantenga la sesión.
- Android valida la biometría; ObraFlow no recibe ni guarda información biométrica.
- El PIN se almacena como SHA-256 con sal aleatoria en almacenamiento seguro, no en texto plano.
- La aplicación se vuelve a bloquear después de 30 segundos en segundo plano.
- Cerrar sesión o cambiar de cuenta puede requerir autenticación Firebase y configuración local nuevamente.

### Proyectos

- Crear, editar nombre/ubicación/presupuesto y consultar indicadores.
- Estados: `ACTIVE`, `PAUSED`, `COMPLETED`.
- Filtro inicial por proyectos activos.
- Gastos y reportes muestran únicamente proyectos activos según la regla funcional actual.
- Pausar/reactivar solicita confirmación.
- Eliminación protegida recientemente implementada:
  - si el proyecto tiene al menos un gasto, la operación se bloquea;
  - si no tiene gastos, se muestra confirmación;
  - Android encola la eliminación para sincronizarla;
  - Angular verifica gastos en Firestore y elimina el documento del proyecto.
- No se eliminó ningún proyecto real al implementar esta función; el usuario hará la selección correcta.

### Gastos y facturas

- Crear, editar y eliminar con confirmación.
- Campos: proyecto, fecha, categoría, descripción/artículo, proveedor opcional, número de factura, cantidad, precio unitario, subtotal, tasa de IVA, importe de IVA y total.
- La fecha se propone con el día actual y puede modificarse.
- La categoría se puede buscar desde el formulario.
- El proveedor queda vacío por defecto.
- IVA global configurable, pero editable en cada gasto; cambiar el valor global no altera gastos anteriores.
- Angular incluye búsqueda, filtro de proyecto activo, totales, proveedor/factura y acciones con iconos alineados.
- Semántica real de borrado: Android marca primero el registro para encolar la operación, pero después de sincronizar elimina el documento remoto y limpia el registro local; Angular usa `deleteDoc` directamente. No debe describirse como archivo lógico permanente.

### Categorías y proveedores

- Categorías editables y eliminables desde tabla/listado.
- Caché de categorías durante 24 horas para reducir lecturas.
- Botón de actualización manual cuando se requiere traer un cambio inmediatamente.
- Catálogo de proveedores editable; es opcional en gastos.

### Reportes

- Exportación mensual en PDF y Excel.
- Incluye resumen por proyecto y categoría, facturas, IVA y detalle de artículos.
- El mes inicia en el mes actual.
- Solo incluye movimientos de proyectos activos según la regla vigente.

### Identidad visual

- Marca compartida **ObraFlow**, colores verde/terracota, logo e icono propios.
- UI responsive en Angular y Flutter.
- Temas claro y oscuro en Android.

## Persistencia móvil y sincronización

Base local privada: `obraflow.db` mediante SQLite, esquema versión **6**.

Tablas:

| Tabla | Propósito |
|---|---|
| `projects` | Proyectos, presupuesto, gasto, avance, estado y borrado lógico |
| `expenses` | Líneas detalladas de gastos/facturas y valores en centavos |
| `categories` | Categorías y grupos editables |
| `providers` | Proveedores opcionales |
| `settings` | IVA y marcadores de importación |
| `sync_queue` | Operaciones pendientes, intentos y errores |

Decisiones de datos:

- Montos de Android se guardan como centavos enteros para evitar errores decimales.
- Campos de sincronización: `client_id`, `remote_id`, `updated_at`, `sync_status`, `is_deleted`.
- Estados conocidos: `demo`, `pending`, `synced`, `failed`.
- Cambios Android: primero SQLite, luego `sync_queue`, después Firestore.
- Sin internet, el cambio queda local y se reintenta en el próximo inicio/sincronización manual.
- Android lee Firestore al iniciar sesión o al solicitar sincronización; no conserva listeners permanentes.
- Angular usa listeners de Firestore para proyectos, gastos, proveedores y parámetros; categorías tienen lectura/caché diaria y actualización manual.

## Firebase

- Proyecto: `gastos-proyecto-d2147`.
- Aplicación Android: `com.gastosproyectos.gastos_mobile`.
- Firestore fue creado en modo Producción.
- Proveedores Auth que deben permanecer activos: **Email/Password** y **Google**.
- Dominios de pruebas web deben estar en Authentication → Configuración → Dominios autorizados.
- No son necesarios actualmente Storage, Functions, autenticación telefónica ni servicios de IA.
- La configuración cliente de Firebase ya existe en el código. No hay credenciales administrativas en el proyecto.

Estructura remota:

```text
users/{uid}
├── projects/{projectId}
├── expenses/{expenseId}
├── categories/{categoryId}
├── providers/{providerId}
├── workers/{workerId}
├── workerRoles/{roleId}
├── workerRates/{rateId}
├── workerAttendance/{attendanceId}
├── workerAttendanceAudit/{auditId}
├── workerAdvances/{advanceId}
├── workerPayments/{paymentId}
└── settings/
    ├── general
    └── import-real-invoices-v1
```

Las reglas de `firestore.rules` permiten leer/escribir solo cuando `request.auth.uid == userId`. Todo acceso fuera de `users/{uid}` se rechaza. No hay índices compuestos configurados.

Publicación de reglas:

```powershell
cd C:\proyectos\gastos-proyectos\apps\web
npx firebase login
npx firebase deploy --config ..\..\firebase.json --only firestore
```

## Datos reales conocidos

La migración inicial usa IDs deterministas y dos marcadores: Android comprueba `settings.real_invoice_import_v1`; Angular comprueba `users/{uid}/settings/import-real-invoices-v1`. Cuando el marcador existe, la carga se omite. Si falta, el código limpia IDs antiguos/deterministas y vuelve a escribir el seed, por lo que **no se deben borrar ni recrear estos marcadores en una cuenta con datos reales**. Antes de cambiar el seed o su lógica, se requiere una copia de seguridad verificable.

- Fecha: **15 de agosto de 2026**.
- Proveedor: **Su Ferretero - Construcciones Cranbegal Cía. Ltda.**
- Facturas: `001-020-000380000` y `001-020-000380009`.
- Total: **USD 5.234,84**.
- IVA incluido registrado: **USD 451,96**.
- El seed original usa el proyecto `Por asignar`; el usuario puede haber reasignado ya los movimientos en Firestore. No se debe sobreescribir el estado actual con el seed.

| Factura | Artículo | Cant. | IVA | IVA USD | Total USD |
|---|---|---:|---:|---:|---:|
| 001-020-000380000 | Hierro Adelca 10 x 12 mm | 96 | 5% | 32,33 | 678,92 |
| 001-020-000380000 | Hierro Adelca 12 x 12 mm | 207 | 5% | 100,41 | 2.108,52 |
| 001-020-000380000 | Hierro Adelca 14 x 12 m | 147 | 15% | 291,01 | 2.231,06 |
| 001-020-000380000 | Rollo de alambre #18 galvanizado | 5 | 15% | 21,61 | 165,68 |
| 001-020-000380000 | Disco de corte para hierro Norton | 10 | 15% | 3,27 | 25,13 |
| 001-020-000380009 | Martillo Truper 16 oz | 1 | 15% | 1,50 | 11,50 |
| 001-020-000380009 | Alicate Stanley original | 1 | 15% | 1,15 | 8,77 |
| 001-020-000380009 | Flexómetro Truper 3 m | 1 | 15% | 0,68 | 5,26 |

Algunas descripciones fueron transcritas desde fotos de poca nitidez; conviene contrastarlas con el comprobante físico antes de realizar correcciones contables.

## Google Sheet asociado

- Nombre: **Control de Gastos ObraFlow - Reporte mensual**.
- URL: <https://docs.google.com/spreadsheets/d/1FEQ0mIaByngWkej3-AfqKzc3kSoHLlptIEK9yRpsSpU/edit>
- ID: `1FEQ0mIaByngWkej3-AfqKzc3kSoHLlptIEK9yRpsSpU`.
- Pestañas: `Resumen`, `Facturas`, `Gastos_App`, `Catalogos`, `Reporte_Mensual`.
- `Reporte_Mensual` permite elegir el mes y recalcular facturas, total, IVA, categorías y detalle.
- Estado actual: refleja el modelo y los datos conocidos, pero no existe todavía sincronización automática bidireccional con Firestore.

## Versiones, validación y artefactos

- Flutter: 3.44.6 o compatible.
- Dart: 3.12.2 o compatible.
- Java/JVM: 17.
- Android mínimo: API 24.
- Angular: 22.1.x.
- Firebase JS: 12.17.1.
- Aplicación móvil: `2.0.1+14`.
- Web: `2.0.1`.
- Nombre Android visible: `ObraFlow Demo`.
- El APK actual usa firma de desarrollo; sirve para prueba directa, no para Google Play.

Última validación conocida de ObraFlow 2.0 y el módulo Personal y jornales:

- `flutter analyze`: sin problemas.
- `flutter test`: 12 pruebas aprobadas.
- Angular build: correcto; solo advertencias de optimización CommonJS por jsPDF/canvg.
- Angular tests: 7 pruebas aprobadas.
- Reglas Firestore: aislamiento del módulo laboral aprobado con emulador y Firebase CLI 14.22.0; la CLI 15 instalada requiere Java 21 y la máquina tiene Java 17.

APK actual:

- Ruta esperada: `C:\proyectos\gastos-proyectos\dist\ObraFlow-v2.0.1.apk`
- Tamaño: 62.146.917 bytes.
- SHA-256: `3B7C7BA0E7C9AC93F6F5ECDF441FD754A5E2EC7C1B59524EF6AB9A568CBC7BDE`.

## Comandos habituales

Android, desarrollo y verificación:

```powershell
cd C:\proyectos\gastos-proyectos\apps\mobile
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter run
```

Generar APK:

```powershell
cd C:\proyectos\gastos-proyectos\apps\mobile
flutter clean
flutter pub get
flutter build apk --release
```

Salida: `C:\proyectos\gastos-proyectos\apps\mobile\build\app\outputs\flutter-apk\app-release.apk`.

Angular:

```powershell
cd C:\proyectos\gastos-proyectos\apps\web
npm install
npm start
npm run build
npm test -- --watch=false
```

Web local: `http://localhost:4200`. Para verla desde otro equipo de la misma red puede usarse `npm start -- --host 0.0.0.0`, abrir el puerto de forma controlada y entrar por la IP LAN de la máquina. Una IP o túnel anterior no debe asumirse vigente.

## Git: estado e inventario

Al recopilar este documento, `C:\proyectos\gastos-proyectos` **no era todavía un repositorio Git**. Se añadió `.gitignore` para proteger artefactos locales y generados.

Hasta que exista un primer commit, remote y rama base, no hay un punto de restauración Git confiable. Antes de una modificación amplia conviene inicializar el repositorio o conservar una copia/snapshot completo del workspace.

Debe subirse:

- `README.md`, `HANDOFF.md`, `.gitignore`;
- `.firebaserc`, `firebase.json`, `firestore.rules`, `firestore.indexes.json`;
- código fuente, assets, pruebas y archivos de dependencias bloqueadas de Flutter/Angular;
- configuración cliente de Firebase (`firebase_options.dart` y `google-services.json`) solo como configuración de aplicación cliente; nunca claves administrativas;
- Gradle wrapper/proyecto Android y proyecto iOS fuente.

No debe subirse:

- `.codex_tmp/`, `.runtime/`, `outputs/`, `dist/`;
- `node_modules/`, `build/`, `.dart_tool/`, `.angular/`, coberturas;
- `apps/mobile/android/local.properties`;
- `apps/mobile/ios/Flutter/ephemeral/`, `Generated.xcconfig`, `flutter_export_environment.sh`;
- logs de Firebase/npm;
- `.jks`, `.keystore`, cuentas de servicio o credenciales Admin SDK.

## Límites y pendientes claros

Ya implementado: paridad funcional principal Android/web, autenticación, sincronización Firestore, persistencia SQLite, proyectos/estados/presupuestos, gastos detallados, IVA, categorías, proveedores, reportes, identidad visual, Google login, PIN/biometría y eliminación protegida de proyectos.

Pendientes u opciones todavía no implementadas:

1. Fotografías de comprobantes; requeriría decidir si habilitar Firebase Storage y su costo/cuota.
2. OCR de facturas.
3. Sincronización automática real entre Firestore y Google Sheets.
4. Notificaciones push.
5. Firma de producción y preparación para Google Play.
6. Restringir las reglas al UID definitivo si se decide que solo una cuenta podrá usar el sistema.
7. Retirar el registro de nuevas cuentas después de crear la cuenta propietaria, si se desea uso estrictamente personal.
8. Cambio de PIN desde Parámetros.
9. Auditoría y resolución de conflictos más avanzada entre dispositivos.
10. Papelera o tombstones permanentes para gastos/proyectos si se necesita restauración y auditoría; hoy el borrado final es físico.

## Información operativa todavía no conocida

El código y los archivos locales no revelan con seguridad:

- el correo/UID definitivo del propietario;
- la región finalmente elegida para Firestore;
- un proyecto Firebase separado para desarrollo/pruebas;
- un backup vigente de Firestore;
- un procedimiento probado para exportar/restaurar `obraflow.db`;
- remote, rama o commit base de Git, porque el workspace aún no era repositorio.

Hasta completar esos datos, se puede inspeccionar, documentar, compilar y probar unitariamente, pero no conviene ejecutar semillas, sincronizaciones conectadas, migraciones ni despliegues contra `gastos-proyecto-d2147` sin confirmar primero que existe respaldo y que se está usando la cuenta correcta. Las pruebas de reglas usan el emulador `demo-obraflow`; las aplicaciones normales apuntan al proyecto real.

## Reglas para cualquier continuación

1. Leer el estado real del código antes de editar; este documento describe la última verificación, no sustituye una inspección.
2. No ejecutar migraciones destructivas ni volver a sembrar datos reales sobre una cuenta existente.
3. No eliminar proyectos/gastos reales durante pruebas. Usar registros de prueba claramente identificados y retirarlos solo con autorización.
4. No borrar los marcadores de importación; mantener IDs y semillas idempotentes.
5. Tratar `gastos-proyecto-d2147` como producción hasta que se documente un entorno de pruebas independiente.
6. Probar tanto Android como Angular cuando se modifique el contrato Firestore.
7. Actualizar `README.md`, este archivo, número de versión y APK cuando corresponda.
8. Antes de publicar en Git, revisar `git status` y comprobar que ningún secreto, archivo local o artefacto pesado quedó incluido.
