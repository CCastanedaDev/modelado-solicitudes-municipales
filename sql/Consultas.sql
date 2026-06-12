-- =====================================================================
-- CONSULTAS DEL MODELO MUNICIPAL
-- Examen Final Transversal — Taller de Datos I Modelamiento (CD201ICDA)
--
-- Las consultas están organizadas en dos bloques:
--
--   A. OPERATIVAS — soporte al trabajo diario (tiempo real)
--      A.1 Cola de trabajo por unidad
--      A.2 Backlog crítico (SLA vencido)
--      A.3 Carga por cuadrilla
--      A.4 Detalle completo de una solicitud
--
--   B. ANALÍTICAS — responden a las 5 necesidades del municipio
--      B.1 Tasa de solicitudes por sector y tipo  → "patrones por sector"
--      B.2 Detección de ciudadanos reincidentes   → "perfiles de reincidencia"
--      B.3 Tiempo promedio de resolución          → "reducir tiempos de respuesta"
--      B.4 Cumplimiento de SLA por unidad         → "optimizar asignación"
--      B.5 Zonas críticas recurrentes             → "patrones por sector y tipo"
--      B.6 Consulta híbrida sobre JSONB           → demuestra modelo híbrido
-- =====================================================================


-- ┌───────────────────────────────────────────────────────────────────┐
-- │  A. CONSULTAS OPERATIVAS                                          │
-- └───────────────────────────────────────────────────────────────────┘

-- A.1 Cola de trabajo por unidad
-- Lista las solicitudes abiertas (no en estado final) ordenadas por
-- prioridad descendente y luego por antigüedad. Es la consulta que un
-- funcionario ejecuta al empezar el turno.
SELECT s.folio,
       u.nombre        AS unidad,
       t.nombre        AS tipo,
       sec.nombre      AS sector,
       s.prioridad,
       s.fecha_creacion AS ingreso,
       s.fecha_limite_respuesta AS vence,
       AGE(s.fecha_limite_respuesta, CURRENT_TIMESTAMP) AS tiempo_restante,
       e.nombre        AS estado
FROM solicitud s
JOIN unidad_municipal u ON u.unidad_id = s.unidad_id
JOIN tipo_solicitud t   ON t.tipo_id   = s.tipo_id
JOIN sector sec         ON sec.sector_id = s.sector_id
JOIN estado_solicitud e ON e.estado_id = s.estado_actual_id
WHERE e.es_final = FALSE
ORDER BY
    CASE s.prioridad
        WHEN 'URGENTE' THEN 1
        WHEN 'ALTA'    THEN 2
        WHEN 'MEDIA'   THEN 3
        WHEN 'BAJA'    THEN 4
    END,
    s.fecha_creacion ASC;


-- A.2 Backlog crítico — solicitudes con SLA vencido y aún sin cerrar
-- Atención: éstas son las que generan exposición legal bajo Ley 19.880.
SELECT s.folio,
       u.nombre AS unidad,
       t.nombre AS tipo,
       s.prioridad,
       s.fecha_creacion,
       s.fecha_limite_respuesta,
       CURRENT_TIMESTAMP - s.fecha_limite_respuesta AS atraso,
       e.nombre AS estado_actual
FROM solicitud s
JOIN unidad_municipal u ON u.unidad_id = s.unidad_id
JOIN tipo_solicitud t   ON t.tipo_id   = s.tipo_id
JOIN estado_solicitud e ON e.estado_id = s.estado_actual_id
WHERE e.es_final = FALSE
  AND s.fecha_limite_respuesta < CURRENT_TIMESTAMP
ORDER BY s.fecha_limite_respuesta ASC;


-- A.3 Carga activa por cuadrilla
-- Útil para decidir asignaciones nuevas — quién tiene capacidad libre.
SELECT cu.nombre        AS cuadrilla,
       u.nombre         AS unidad,
       cu.capacidad_diaria,
       COUNT(*) FILTER (WHERE ac.fecha_fin_trabajo IS NULL) AS activas,
       COUNT(*)                                              AS total_historicas
FROM cuadrilla cu
JOIN unidad_municipal u   ON u.unidad_id = cu.unidad_id
LEFT JOIN asignacion_cuadrilla ac ON ac.cuadrilla_id = cu.cuadrilla_id
WHERE cu.activo = TRUE
GROUP BY cu.cuadrilla_id, cu.nombre, u.nombre, cu.capacidad_diaria
ORDER BY activas DESC;


-- A.4 Detalle completo de una solicitud específica
-- Incluye historial de estados, asignaciones y adjuntos.
SELECT s.folio,
       c.nombre || ' ' || c.apellido AS ciudadano,
       c.rut,
       t.nombre   AS tipo,
       u.nombre   AS unidad,
       sec.nombre AS sector,
       s.prioridad,
       e.nombre   AS estado_actual,
       s.descripcion,
       s.metadatos,
       (SELECT json_agg(json_build_object(
               'fecha',     h.fecha_cambio,
               'estado',    es.nombre,
               'observacion', h.observacion))
        FROM historial_estado h
        JOIN estado_solicitud es ON es.estado_id = h.estado_id
        WHERE h.solicitud_id = s.solicitud_id)  AS historial,
       (SELECT COUNT(*) FROM adjunto a
        WHERE a.solicitud_id = s.solicitud_id)  AS num_adjuntos
FROM solicitud s
JOIN ciudadano c        ON c.ciudadano_id = s.ciudadano_id
JOIN tipo_solicitud t   ON t.tipo_id      = s.tipo_id
JOIN unidad_municipal u ON u.unidad_id    = s.unidad_id
JOIN sector sec         ON sec.sector_id  = s.sector_id
JOIN estado_solicitud e ON e.estado_id    = s.estado_actual_id
WHERE s.folio = 'SOL-2025-00001';


-- ┌───────────────────────────────────────────────────────────────────┐
-- │  B. CONSULTAS ANALÍTICAS                                          │
-- └───────────────────────────────────────────────────────────────────┘

-- B.1 Tasa de solicitudes por sector y tipo (matriz cruzada)
-- Responde a: "Analizar patrones de reclamos por sector y tipo"
SELECT sec.nombre AS sector,
       t.nombre   AS tipo,
       COUNT(*)   AS total,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY sec.sector_id), 1)
           AS porcentaje_dentro_del_sector
FROM solicitud s
JOIN sector sec         ON sec.sector_id = s.sector_id
JOIN tipo_solicitud t   ON t.tipo_id     = s.tipo_id
GROUP BY sec.sector_id, sec.nombre, t.tipo_id, t.nombre
ORDER BY sec.nombre, total DESC;


-- B.2 Detección de ciudadanos reincidentes (>= 5 solicitudes en el periodo)
-- Responde a: "Detectar perfiles de alta reincidencia"
SELECT c.rut,
       c.nombre || ' ' || c.apellido AS ciudadano,
       sec.nombre                    AS sector_residencia,
       COUNT(s.solicitud_id)         AS total_solicitudes,
       COUNT(DISTINCT s.tipo_id)     AS tipos_distintos,
       MIN(s.fecha_creacion)         AS primera,
       MAX(s.fecha_creacion)         AS ultima,
       ROUND(EXTRACT(EPOCH FROM (MAX(s.fecha_creacion) - MIN(s.fecha_creacion)))
             / 86400.0, 1)           AS dias_entre_primera_y_ultima
FROM ciudadano c
JOIN solicitud s   ON s.ciudadano_id = c.ciudadano_id
LEFT JOIN sector sec ON sec.sector_id = c.sector_residencia_id
GROUP BY c.ciudadano_id, c.rut, c.nombre, c.apellido, sec.nombre
HAVING COUNT(s.solicitud_id) >= 5
ORDER BY total_solicitudes DESC;


-- B.3 Tiempo promedio de resolución por unidad y tipo
-- Responde a: "Reducir tiempos de respuesta"
SELECT u.nombre   AS unidad,
       t.nombre   AS tipo,
       COUNT(*)                            AS cerradas,
       ROUND(AVG(EXTRACT(EPOCH FROM (s.fecha_cierre - s.fecha_creacion))
                 / 3600.0)::numeric, 1)    AS horas_promedio,
       ROUND(MIN(EXTRACT(EPOCH FROM (s.fecha_cierre - s.fecha_creacion))
                 / 3600.0)::numeric, 1)    AS horas_min,
       ROUND(MAX(EXTRACT(EPOCH FROM (s.fecha_cierre - s.fecha_creacion))
                 / 3600.0)::numeric, 1)    AS horas_max,
       t.sla_horas                         AS sla_objetivo
FROM solicitud s
JOIN unidad_municipal u ON u.unidad_id = s.unidad_id
JOIN tipo_solicitud t   ON t.tipo_id   = s.tipo_id
WHERE s.fecha_cierre IS NOT NULL
GROUP BY u.unidad_id, u.nombre, t.tipo_id, t.nombre, t.sla_horas
ORDER BY u.nombre, horas_promedio DESC;


-- B.4 Cumplimiento de SLA por unidad
-- Responde a: "Optimizar asignación de cuadrillas"
WITH cerradas AS (
    SELECT s.unidad_id,
           s.solicitud_id,
           s.fecha_cierre <= s.fecha_limite_respuesta AS cumple_sla
    FROM solicitud s
    WHERE s.fecha_cierre IS NOT NULL
)
SELECT u.nombre AS unidad,
       COUNT(*)                                          AS total_cerradas,
       SUM(CASE WHEN cumple_sla THEN 1 ELSE 0 END)       AS cumplidas,
       SUM(CASE WHEN NOT cumple_sla THEN 1 ELSE 0 END)   AS atrasadas,
       ROUND(100.0 * SUM(CASE WHEN cumple_sla THEN 1 ELSE 0 END)
             / COUNT(*), 1)                              AS pct_cumplimiento
FROM cerradas c
JOIN unidad_municipal u ON u.unidad_id = c.unidad_id
GROUP BY u.unidad_id, u.nombre
ORDER BY pct_cumplimiento DESC;


-- B.5 Zonas críticas recurrentes (top sectores + tipo predominante)
-- Responde a: "Identificar zonas críticas recurrentes" (decisión estratégica)
WITH tipos_por_sector AS (
    SELECT s.sector_id,
           s.tipo_id,
           COUNT(*) AS n,
           ROW_NUMBER() OVER (PARTITION BY s.sector_id ORDER BY COUNT(*) DESC) AS rk
    FROM solicitud s
    GROUP BY s.sector_id, s.tipo_id
)
SELECT sec.nombre                AS sector,
       COUNT(s.solicitud_id)     AS total_solicitudes,
       (SELECT t.nombre
        FROM tipos_por_sector tps
        JOIN tipo_solicitud t ON t.tipo_id = tps.tipo_id
        WHERE tps.sector_id = sec.sector_id AND tps.rk = 1) AS tipo_predominante,
       ROUND(100.0 * COUNT(s.solicitud_id) /
             (SELECT COUNT(*) FROM solicitud), 1)            AS porcentaje_global
FROM sector sec
LEFT JOIN solicitud s ON s.sector_id = sec.sector_id
GROUP BY sec.sector_id, sec.nombre
ORDER BY total_solicitudes DESC;


-- B.6 Consulta híbrida sobre JSONB — agregaciones desde el modelo híbrido
-- Demuestra que el modelo permite consultas que combinan columnas
-- relacionales con extracción de campos del JSONB metadatos.
-- Responde a: validación práctica del diseño híbrido (Parte 2.2 del enunciado)
SELECT ca.nombre                                              AS canal,
       COUNT(*)                                               AS total,
       COUNT(*) FILTER (WHERE s.metadatos -> 'canal_origen'
                              ->> 'version_app' IS NOT NULL)  AS con_version_app,
       ROUND(AVG((s.metadatos -> 'geolocalizacion' ->> 'precision_m')::numeric), 1)
           AS precision_promedio_metros
FROM solicitud s
JOIN canal ca ON ca.canal_id = s.canal_id
GROUP BY ca.canal_id, ca.nombre
ORDER BY total DESC;

-- B.6.bis Extracción de atributos JSONB específicos por tipo
-- Ejemplo: profundidad promedio de los baches reportados, por sector.
SELECT sec.nombre AS sector,
       COUNT(*) AS total_baches,
       ROUND(AVG((s.metadatos -> 'atributos' ->> 'profundidad_cm')::numeric), 1)
           AS profundidad_promedio_cm,
       MAX((s.metadatos -> 'atributos' ->> 'profundidad_cm')::int)
           AS profundidad_maxima_cm
FROM solicitud s
JOIN tipo_solicitud t ON t.tipo_id = s.tipo_id
JOIN sector sec       ON sec.sector_id = s.sector_id
WHERE t.codigo = 'BACHE'
  AND s.metadatos -> 'atributos' ->> 'profundidad_cm' IS NOT NULL
GROUP BY sec.sector_id, sec.nombre
ORDER BY profundidad_promedio_cm DESC;


-- =====================================================================
-- FIN DE CONSULTAS — el modelo responde a las 5 necesidades del cliente
-- =====================================================================
