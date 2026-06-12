-- =====================================================================
-- Examen Final Transversal — Taller de Datos I Modelamiento (CD201ICDA)
-- Caso: Sistema de Gestión y Análisis de Solicitudes Ciudadanas
--       en un Municipio Chileno
-- Motor: PostgreSQL 15+
--
-- Modelo híbrido: núcleo relacional normalizado (3FN) +
-- campo JSONB para datos semiestructurados (geolocalización,
-- metadatos de canal, atributos variables por tipo de solicitud).
--
-- Normativa aplicada: Ley 21.719 (protección de datos personales),
-- Ley 19.880 (procedimientos administrativos), Ley 20.285 (transparencia).
-- =====================================================================

-- Limpieza idempotente (orden inverso a las dependencias)
DROP TABLE IF EXISTS adjunto              CASCADE;
DROP TABLE IF EXISTS asignacion_cuadrilla CASCADE;
DROP TABLE IF EXISTS historial_estado     CASCADE;
DROP TABLE IF EXISTS solicitud            CASCADE;
DROP TABLE IF EXISTS ciudadano            CASCADE;
DROP TABLE IF EXISTS cuadrilla            CASCADE;
DROP TABLE IF EXISTS funcionario          CASCADE;
DROP TABLE IF EXISTS sector               CASCADE;
DROP TABLE IF EXISTS unidad_municipal     CASCADE;
DROP TABLE IF EXISTS estado_solicitud     CASCADE;
DROP TABLE IF EXISTS tipo_solicitud       CASCADE;
DROP TABLE IF EXISTS canal                CASCADE;


-- =====================================================================
-- 1. TABLAS DE CATÁLOGO (referenciales, baja cardinalidad)
-- =====================================================================

-- Canal de ingreso de la solicitud (web, app móvil, presencial)
CREATE TABLE canal (
    canal_id     SERIAL PRIMARY KEY,
    nombre       VARCHAR(20) NOT NULL UNIQUE
                 CHECK (nombre IN ('WEB','APP_MOVIL','PRESENCIAL')),
    descripcion  TEXT,
    activo       BOOLEAN NOT NULL DEFAULT TRUE
);

COMMENT ON TABLE  canal          IS 'Catálogo de canales de ingreso de solicitudes ciudadanas';
COMMENT ON COLUMN canal.nombre   IS 'Identificador canónico del canal — restringido a tres valores';


-- Tipo de solicitud (bache, luminaria, basura, ruido molesto, etc.)
CREATE TABLE tipo_solicitud (
    tipo_id      SERIAL PRIMARY KEY,
    codigo       VARCHAR(20)  NOT NULL UNIQUE,
    nombre       VARCHAR(100) NOT NULL,
    descripcion  TEXT,
    sla_horas    INT          NOT NULL CHECK (sla_horas > 0),
    activo       BOOLEAN      NOT NULL DEFAULT TRUE
);

COMMENT ON COLUMN tipo_solicitud.sla_horas IS 'Plazo máximo de respuesta en horas (Ley 19.880)';


-- Estados posibles del ciclo de vida de la solicitud
CREATE TABLE estado_solicitud (
    estado_id    SERIAL PRIMARY KEY,
    codigo       VARCHAR(20) NOT NULL UNIQUE
                 CHECK (codigo IN ('INGRESADA','ASIGNADA','EN_PROCESO',
                                   'RESUELTA','CERRADA','RECHAZADA')),
    nombre       VARCHAR(50) NOT NULL,
    es_final     BOOLEAN     NOT NULL DEFAULT FALSE,
    orden_flujo  INT         NOT NULL UNIQUE
);

COMMENT ON COLUMN estado_solicitud.es_final
    IS 'TRUE si el estado cierra el flujo (CERRADA, RECHAZADA)';


-- Unidad municipal responsable (Aseo, Alumbrado, Tránsito, etc.)
CREATE TABLE unidad_municipal (
    unidad_id      SERIAL PRIMARY KEY,
    codigo         VARCHAR(20)  NOT NULL UNIQUE,
    nombre         VARCHAR(100) NOT NULL,
    email_contacto VARCHAR(150)
                   CHECK (email_contacto IS NULL OR
                          email_contacto ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    activo         BOOLEAN NOT NULL DEFAULT TRUE
);


-- Sector geográfico / barrio (para analítica territorial)
CREATE TABLE sector (
    sector_id  SERIAL PRIMARY KEY,
    codigo     VARCHAR(20)  NOT NULL UNIQUE,
    nombre     VARCHAR(100) NOT NULL,
    poligono   JSONB        -- GeoJSON opcional para integración futura con PostGIS
);

COMMENT ON COLUMN sector.poligono
    IS 'Polígono geográfico opcional en formato GeoJSON';


-- =====================================================================
-- 2. TABLAS OPERATIVAS (recursos humanos municipales)
-- =====================================================================

-- Funcionario municipal que opera el sistema
CREATE TABLE funcionario (
    funcionario_id SERIAL PRIMARY KEY,
    rut            VARCHAR(12)  NOT NULL UNIQUE
                   CHECK (rut ~ '^[0-9]{7,8}-[0-9Kk]$'),
    nombre         VARCHAR(100) NOT NULL,
    apellido       VARCHAR(100) NOT NULL,
    email          VARCHAR(150) NOT NULL UNIQUE
                   CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    unidad_id      INT          NOT NULL REFERENCES unidad_municipal(unidad_id),
    activo         BOOLEAN      NOT NULL DEFAULT TRUE,
    fecha_ingreso  DATE         NOT NULL DEFAULT CURRENT_DATE
);


-- Cuadrilla de terreno (equipo operativo asignable)
CREATE TABLE cuadrilla (
    cuadrilla_id     SERIAL PRIMARY KEY,
    nombre           VARCHAR(50) NOT NULL,
    unidad_id        INT NOT NULL REFERENCES unidad_municipal(unidad_id),
    capacidad_diaria INT NOT NULL CHECK (capacidad_diaria > 0),
    activo           BOOLEAN NOT NULL DEFAULT TRUE,
    UNIQUE (nombre, unidad_id)
);

COMMENT ON COLUMN cuadrilla.capacidad_diaria
    IS 'Número máximo de solicitudes que la cuadrilla puede atender por día';


-- =====================================================================
-- 3. TABLAS DE NEGOCIO (ciudadanos y solicitudes)
-- =====================================================================

-- Ciudadano (sujeto de derechos sobre sus datos — Ley 21.719)
CREATE TABLE ciudadano (
    ciudadano_id          SERIAL PRIMARY KEY,
    rut                   VARCHAR(12)  NOT NULL UNIQUE
                          CHECK (rut ~ '^[0-9]{7,8}-[0-9Kk]$'),
    nombre                VARCHAR(100) NOT NULL,
    apellido              VARCHAR(100) NOT NULL,
    email                 VARCHAR(150)
                          CHECK (email IS NULL OR
                                 email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    telefono              VARCHAR(20),
    direccion             TEXT,
    sector_residencia_id  INT REFERENCES sector(sector_id),
    fecha_registro        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    consentimiento_datos  BOOLEAN   NOT NULL DEFAULT FALSE,
    fecha_consentimiento  TIMESTAMP,
    CHECK (email IS NOT NULL OR telefono IS NOT NULL),
    CHECK (consentimiento_datos = FALSE OR fecha_consentimiento IS NOT NULL)
);

COMMENT ON COLUMN ciudadano.consentimiento_datos
    IS 'Ley 21.719: consentimiento informado para el tratamiento de datos personales';


-- Solicitud ciudadana — entidad central del modelo híbrido
CREATE TABLE solicitud (
    solicitud_id            SERIAL PRIMARY KEY,
    folio                   VARCHAR(20) NOT NULL UNIQUE,
    ciudadano_id            INT NOT NULL REFERENCES ciudadano(ciudadano_id),
    tipo_id                 INT NOT NULL REFERENCES tipo_solicitud(tipo_id),
    canal_id                INT NOT NULL REFERENCES canal(canal_id),
    unidad_id               INT NOT NULL REFERENCES unidad_municipal(unidad_id),
    sector_id               INT REFERENCES sector(sector_id),
    estado_actual_id        INT NOT NULL REFERENCES estado_solicitud(estado_id),
    funcionario_registro_id INT REFERENCES funcionario(funcionario_id),
    prioridad               VARCHAR(10) NOT NULL DEFAULT 'MEDIA'
                            CHECK (prioridad IN ('BAJA','MEDIA','ALTA','URGENTE')),
    descripcion             TEXT NOT NULL CHECK (length(trim(descripcion)) >= 10),
    fecha_creacion          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_limite_respuesta  TIMESTAMP NOT NULL,
    fecha_cierre            TIMESTAMP,
    metadatos               JSONB NOT NULL DEFAULT '{}'::jsonb,
    CHECK (fecha_limite_respuesta > fecha_creacion),
    CHECK (fecha_cierre IS NULL OR fecha_cierre >= fecha_creacion)
);

COMMENT ON COLUMN solicitud.folio
    IS 'Identificador externo legible (ej. SOL-2026-00001) para comunicación con el ciudadano';
COMMENT ON COLUMN solicitud.estado_actual_id
    IS 'Denormalización controlada: refleja el último estado de historial_estado';
COMMENT ON COLUMN solicitud.metadatos
    IS 'JSONB con geolocalización, metadatos del canal y atributos variables por tipo';


-- =====================================================================
-- 4. TABLAS DE TRAZABILIDAD Y EVIDENCIA
-- =====================================================================

-- Bitácora de cambios de estado (trazabilidad regulatoria)
CREATE TABLE historial_estado (
    historial_id    SERIAL PRIMARY KEY,
    solicitud_id    INT NOT NULL REFERENCES solicitud(solicitud_id) ON DELETE CASCADE,
    estado_id       INT NOT NULL REFERENCES estado_solicitud(estado_id),
    funcionario_id  INT REFERENCES funcionario(funcionario_id),
    fecha_cambio    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    observacion     TEXT,
    UNIQUE (solicitud_id, estado_id, fecha_cambio)
);


-- Asignación de la solicitud a una cuadrilla de terreno
CREATE TABLE asignacion_cuadrilla (
    asignacion_id        SERIAL PRIMARY KEY,
    solicitud_id         INT NOT NULL REFERENCES solicitud(solicitud_id),
    cuadrilla_id         INT NOT NULL REFERENCES cuadrilla(cuadrilla_id),
    fecha_asignacion     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_inicio_trabajo TIMESTAMP,
    fecha_fin_trabajo    TIMESTAMP,
    observacion          TEXT,
    CHECK (fecha_inicio_trabajo IS NULL OR fecha_inicio_trabajo >= fecha_asignacion),
    CHECK (fecha_fin_trabajo    IS NULL OR fecha_fin_trabajo    >= fecha_inicio_trabajo)
);


-- Archivos adjuntos (solo referencia URI — los binarios viven fuera de la BD)
CREATE TABLE adjunto (
    adjunto_id      SERIAL PRIMARY KEY,
    solicitud_id    INT NOT NULL REFERENCES solicitud(solicitud_id) ON DELETE CASCADE,
    tipo_archivo    VARCHAR(20) NOT NULL
                    CHECK (tipo_archivo IN ('IMAGEN','DOCUMENTO','VIDEO','AUDIO')),
    uri             TEXT NOT NULL,
    nombre_original VARCHAR(255),
    tamano_bytes    BIGINT CHECK (tamano_bytes IS NULL OR tamano_bytes >= 0),
    fecha_carga     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON COLUMN adjunto.uri
    IS 'URI al almacenamiento externo (S3/MinIO/disco). Nunca BLOB en BD';


-- =====================================================================
-- 5. ÍNDICES (optimización de consultas operativas y analíticas)
-- =====================================================================

-- Operativos: filtros y JOINs frecuentes
CREATE INDEX idx_solicitud_fecha_creacion  ON solicitud(fecha_creacion);
CREATE INDEX idx_solicitud_ciudadano       ON solicitud(ciudadano_id);
CREATE INDEX idx_solicitud_estado_actual   ON solicitud(estado_actual_id);
CREATE INDEX idx_solicitud_unidad          ON solicitud(unidad_id);
CREATE INDEX idx_solicitud_tipo            ON solicitud(tipo_id);
CREATE INDEX idx_solicitud_sector          ON solicitud(sector_id);

-- Analíticos: consultas por sector + tipo (zonas críticas)
CREATE INDEX idx_solicitud_sector_tipo     ON solicitud(sector_id, tipo_id);

-- JSONB: búsqueda dentro del campo metadatos
CREATE INDEX idx_solicitud_metadatos_gin   ON solicitud USING GIN (metadatos);

-- Trazabilidad
CREATE INDEX idx_historial_solicitud       ON historial_estado(solicitud_id);
CREATE INDEX idx_historial_fecha           ON historial_estado(fecha_cambio);

-- Asignación de cuadrillas
CREATE INDEX idx_asignacion_cuadrilla      ON asignacion_cuadrilla(cuadrilla_id);
CREATE INDEX idx_asignacion_solicitud      ON asignacion_cuadrilla(solicitud_id);


-- =====================================================================
-- 6. CARGA DE CATÁLOGOS BASE
-- =====================================================================

INSERT INTO canal (nombre, descripcion) VALUES
    ('WEB',        'Portal web institucional'),
    ('APP_MOVIL',  'Aplicación móvil ciudadana'),
    ('PRESENCIAL', 'Oficina de atención al ciudadano');

INSERT INTO estado_solicitud (codigo, nombre, es_final, orden_flujo) VALUES
    ('INGRESADA',  'Ingresada',                FALSE, 1),
    ('ASIGNADA',   'Asignada a unidad',        FALSE, 2),
    ('EN_PROCESO', 'En proceso de atención',   FALSE, 3),
    ('RESUELTA',   'Resuelta en terreno',      FALSE, 4),
    ('CERRADA',    'Cerrada',                  TRUE,  5),
    ('RECHAZADA',  'Rechazada',                TRUE,  6);

INSERT INTO tipo_solicitud (codigo, nombre, descripcion, sla_horas) VALUES
    ('BACHE',      'Bache en calzada',          'Hoyo o desnivel en la vía pública', 168),
    ('LUMINARIA',  'Luminaria fundida',         'Poste de alumbrado público apagado', 120),
    ('BASURA',     'Acumulación de basura',     'Microbasural o falta de retiro',      72),
    ('AREAS_VERDES','Mantención áreas verdes',  'Pasto, árboles, plazas',             240),
    ('RUIDO',      'Ruido molesto',             'Denuncia por contaminación acústica', 48),
    ('SEMAFORO',   'Semáforo en falla',         'Semáforo apagado o intermitente',     24);

INSERT INTO unidad_municipal (codigo, nombre, email_contacto) VALUES
    ('DOM',     'Dirección de Obras Municipales', 'dom@municipalidad.cl'),
    ('ASEO',    'Aseo y Ornato',                  'aseo@municipalidad.cl'),
    ('TRAN',    'Tránsito y Transporte Público',  'transito@municipalidad.cl'),
    ('INSP',    'Inspección Municipal',           'inspeccion@municipalidad.cl');

INSERT INTO sector (codigo, nombre) VALUES
    ('CENTRO',   'Centro'),
    ('NORTE',    'Sector Norte'),
    ('SUR',      'Sector Sur'),
    ('ORIENTE',  'Sector Oriente'),
    ('PONIENTE', 'Sector Poniente');


-- =====================================================================
-- FIN DEL SCRIPT — modelo listo para recibir datos transaccionales
-- =====================================================================
