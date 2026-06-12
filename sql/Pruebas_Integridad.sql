-- =====================================================================
-- PRUEBAS DE INTEGRIDAD DEL MODELO
-- Examen Final Transversal — Taller de Datos I Modelamiento (CD201ICDA)
--
-- Estructura:
--   A. Pruebas positivas (insert válido)
--   B. Pruebas negativas — agrupadas por criterio de calidad ISO/IEC 25012:
--      B.1 PRECISIÓN     (CHECK constraints, dominios, formatos)
--      B.2 COMPLETITUD   (NOT NULL, CHECK de presencia)
--      B.3 CONSISTENCIA  (FK, UNIQUE, integridad referencial)
--
-- Cada prueba negativa va envuelta en SAVEPOINT + ROLLBACK para no
-- abortar la transacción. La salida esperada de psql es la lista de
-- ERRORs (uno por prueba). Si alguna NO genera ERROR, hay un agujero.
-- =====================================================================

\set ON_ERROR_STOP off
\set VERBOSITY default

BEGIN;

-- =====================================================================
-- A. PRUEBAS POSITIVAS — el modelo acepta datos válidos
-- =====================================================================

-- A.1 Inserción válida de ciudadano + solicitud completa
SAVEPOINT sp_positiva;
INSERT INTO ciudadano (rut, nombre, apellido, email, telefono,
                       consentimiento_datos, fecha_consentimiento)
VALUES ('11111111-1', 'Test', 'Positivo', 'test@example.cl', '+56912345678',
        TRUE, CURRENT_TIMESTAMP);

INSERT INTO solicitud (folio, ciudadano_id, tipo_id, canal_id, unidad_id,
                       sector_id, estado_actual_id, prioridad, descripcion,
                       fecha_creacion, fecha_limite_respuesta, metadatos)
VALUES ('SOL-TEST-00001',
        (SELECT ciudadano_id FROM ciudadano WHERE rut = '11111111-1'),
        1, 1, 1, 1, 1, 'ALTA',
        'Solicitud de prueba con descripción válida y suficiente longitud.',
        CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '72 hours',
        '{"geolocalizacion":{"lat":-33.45,"lon":-70.65}}'::jsonb);

SELECT '✓ A.1 — Insert válido de ciudadano + solicitud' AS resultado;
ROLLBACK TO SAVEPOINT sp_positiva;


-- =====================================================================
-- B.1 PRUEBAS NEGATIVAS — PRECISIÓN (deben fallar con ERROR)
-- =====================================================================

-- B.1.1 RUT con formato inválido (sin guión, dígito verificador faltante)
SAVEPOINT sp1;
INSERT INTO ciudadano (rut, nombre, apellido, telefono)
VALUES ('123456789', 'Bad', 'RUT', '+56911111111');
ROLLBACK TO SAVEPOINT sp1;

-- B.1.2 Email con formato inválido
SAVEPOINT sp2;
INSERT INTO ciudadano (rut, nombre, apellido, email, telefono)
VALUES ('11111112-K', 'Bad', 'Email', 'no-es-un-email', '+56911111112');
ROLLBACK TO SAVEPOINT sp2;

-- B.1.3 Prioridad fuera del dominio enumerado
SAVEPOINT sp3;
INSERT INTO solicitud (folio, ciudadano_id, tipo_id, canal_id, unidad_id,
                       estado_actual_id, prioridad, descripcion,
                       fecha_creacion, fecha_limite_respuesta)
VALUES ('SOL-BAD-001', 1, 1, 1, 1, 1, 'CRITICA',
        'Descripción suficientemente larga para pasar el length check.',
        CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '24 hours');
ROLLBACK TO SAVEPOINT sp3;

-- B.1.4 Estado fuera del dominio enumerado
SAVEPOINT sp4;
INSERT INTO estado_solicitud (codigo, nombre, orden_flujo)
VALUES ('PAUSADA', 'Pausada', 99);
ROLLBACK TO SAVEPOINT sp4;

-- B.1.5 Tipo de archivo no permitido en adjuntos
SAVEPOINT sp5;
INSERT INTO adjunto (solicitud_id, tipo_archivo, uri)
VALUES (1, 'EJECUTABLE', 's3://bucket/malware.exe');
ROLLBACK TO SAVEPOINT sp5;

-- B.1.6 Canal fuera del dominio
SAVEPOINT sp6;
INSERT INTO canal (nombre) VALUES ('TELEPATICO');
ROLLBACK TO SAVEPOINT sp6;

-- B.1.7 Fecha de cierre anterior a la creación (incoherencia temporal)
SAVEPOINT sp7;
INSERT INTO solicitud (folio, ciudadano_id, tipo_id, canal_id, unidad_id,
                       estado_actual_id, prioridad, descripcion,
                       fecha_creacion, fecha_limite_respuesta, fecha_cierre)
VALUES ('SOL-BAD-002', 1, 1, 1, 1, 5, 'MEDIA',
        'Descripción suficientemente larga para pasar el length check.',
        '2025-06-01', '2025-06-05', '2025-05-15');
ROLLBACK TO SAVEPOINT sp7;

-- B.1.8 Fecha límite anterior o igual a fecha de creación
SAVEPOINT sp8;
INSERT INTO solicitud (folio, ciudadano_id, tipo_id, canal_id, unidad_id,
                       estado_actual_id, prioridad, descripcion,
                       fecha_creacion, fecha_limite_respuesta)
VALUES ('SOL-BAD-003', 1, 1, 1, 1, 1, 'BAJA',
        'Descripción suficientemente larga para pasar el length check.',
        '2025-06-01 10:00:00', '2025-06-01 10:00:00');
ROLLBACK TO SAVEPOINT sp8;

-- B.1.9 SLA negativo en tipo_solicitud
SAVEPOINT sp9;
INSERT INTO tipo_solicitud (codigo, nombre, sla_horas)
VALUES ('NEGATIVO', 'SLA inválido', -10);
ROLLBACK TO SAVEPOINT sp9;

-- B.1.10 Capacidad diaria negativa en cuadrilla
SAVEPOINT sp10;
INSERT INTO cuadrilla (nombre, unidad_id, capacidad_diaria)
VALUES ('Cuadrilla X', 1, 0);
ROLLBACK TO SAVEPOINT sp10;

-- B.1.11 Tamaño de archivo negativo
SAVEPOINT sp11;
INSERT INTO adjunto (solicitud_id, tipo_archivo, uri, tamano_bytes)
VALUES (1, 'IMAGEN', 's3://bucket/x.jpg', -100);
ROLLBACK TO SAVEPOINT sp11;


-- =====================================================================
-- B.2 PRUEBAS NEGATIVAS — COMPLETITUD (deben fallar con ERROR)
-- =====================================================================

-- B.2.1 Solicitud sin descripción (NOT NULL)
SAVEPOINT sp12;
INSERT INTO solicitud (folio, ciudadano_id, tipo_id, canal_id, unidad_id,
                       estado_actual_id, prioridad,
                       fecha_creacion, fecha_limite_respuesta)
VALUES ('SOL-BAD-004', 1, 1, 1, 1, 1, 'MEDIA',
        CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '24 hours');
ROLLBACK TO SAVEPOINT sp12;

-- B.2.2 Solicitud con descripción demasiado corta (CHECK length >= 10)
SAVEPOINT sp13;
INSERT INTO solicitud (folio, ciudadano_id, tipo_id, canal_id, unidad_id,
                       estado_actual_id, prioridad, descripcion,
                       fecha_creacion, fecha_limite_respuesta)
VALUES ('SOL-BAD-005', 1, 1, 1, 1, 1, 'MEDIA', 'corto',
        CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '24 hours');
ROLLBACK TO SAVEPOINT sp13;

-- B.2.3 Ciudadano sin email NI teléfono (CHECK semántico de contacto)
SAVEPOINT sp14;
INSERT INTO ciudadano (rut, nombre, apellido)
VALUES ('11111113-1', 'Sin', 'Contacto');
ROLLBACK TO SAVEPOINT sp14;

-- B.2.4 Solicitud sin estado_actual_id (NOT NULL)
SAVEPOINT sp15;
INSERT INTO solicitud (folio, ciudadano_id, tipo_id, canal_id, unidad_id,
                       prioridad, descripcion,
                       fecha_creacion, fecha_limite_respuesta)
VALUES ('SOL-BAD-006', 1, 1, 1, 1, 'MEDIA',
        'Descripción suficientemente larga para pasar el length check.',
        CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '24 hours');
ROLLBACK TO SAVEPOINT sp15;


-- =====================================================================
-- B.3 PRUEBAS NEGATIVAS — CONSISTENCIA (deben fallar con ERROR)
-- =====================================================================

-- B.3.1 FK a ciudadano inexistente
SAVEPOINT sp16;
INSERT INTO solicitud (folio, ciudadano_id, tipo_id, canal_id, unidad_id,
                       estado_actual_id, prioridad, descripcion,
                       fecha_creacion, fecha_limite_respuesta)
VALUES ('SOL-BAD-007', 99999, 1, 1, 1, 1, 'MEDIA',
        'Descripción suficientemente larga para pasar el length check.',
        CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '24 hours');
ROLLBACK TO SAVEPOINT sp16;

-- B.3.2 FK a tipo_solicitud inexistente
SAVEPOINT sp17;
INSERT INTO solicitud (folio, ciudadano_id, tipo_id, canal_id, unidad_id,
                       estado_actual_id, prioridad, descripcion,
                       fecha_creacion, fecha_limite_respuesta)
VALUES ('SOL-BAD-008', 1, 9999, 1, 1, 1, 'MEDIA',
        'Descripción suficientemente larga para pasar el length check.',
        CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '24 hours');
ROLLBACK TO SAVEPOINT sp17;

-- B.3.3 Folio duplicado (UNIQUE)
SAVEPOINT sp18;
INSERT INTO solicitud (folio, ciudadano_id, tipo_id, canal_id, unidad_id,
                       estado_actual_id, prioridad, descripcion,
                       fecha_creacion, fecha_limite_respuesta)
VALUES ('SOL-2025-00001', 1, 1, 1, 1, 1, 'MEDIA',
        'Folio duplicado de un registro ya existente en la BD.',
        CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '24 hours');
ROLLBACK TO SAVEPOINT sp18;

-- B.3.4 RUT de ciudadano duplicado (UNIQUE)
SAVEPOINT sp19;
INSERT INTO ciudadano (rut, nombre, apellido, telefono)
VALUES ((SELECT rut FROM ciudadano LIMIT 1),
        'Duplicado', 'RUT', '+56999999999');
ROLLBACK TO SAVEPOINT sp19;

-- B.3.5 Funcionario asignado a unidad inexistente
SAVEPOINT sp20;
INSERT INTO funcionario (rut, nombre, apellido, email, unidad_id)
VALUES ('11111114-K', 'Test', 'Funcionario', 'test@municipalidad.cl', 9999);
ROLLBACK TO SAVEPOINT sp20;


-- =====================================================================
-- Verificación: cuántas filas hay en cada tabla después de las pruebas
-- (debe coincidir con el dataset original — todas las pruebas hicieron ROLLBACK)
-- =====================================================================
SELECT 'ciudadano' AS tabla, COUNT(*) AS filas FROM ciudadano
UNION ALL SELECT 'solicitud', COUNT(*) FROM solicitud
UNION ALL SELECT 'historial_estado', COUNT(*) FROM historial_estado
UNION ALL SELECT 'asignacion_cuadrilla', COUNT(*) FROM asignacion_cuadrilla
UNION ALL SELECT 'adjunto', COUNT(*) FROM adjunto
ORDER BY tabla;

ROLLBACK;

-- =====================================================================
-- RESUMEN ESPERADO AL EJECUTAR:
--   • 1 mensaje de éxito en la prueba positiva (A.1)
--   • 20 mensajes ERROR (B.1.1 a B.3.5), uno por cada violación
--   • Conteo final de filas = conteo inicial (todo rollback)
--
-- Si alguna prueba B.x NO produce ERROR, ese constraint está faltante
-- o mal definido en el esquema.
-- =====================================================================
