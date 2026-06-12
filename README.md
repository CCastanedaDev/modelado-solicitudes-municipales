# Modelado de Solicitudes Ciudadanas Municipales

Modelo de datos híbrido (PostgreSQL + JSONB) para un sistema
de gestión de solicitudes ciudadanas en una municipalidad
chilena. Combina núcleo relacional normalizado con campo JSONB
validado por JSON Schema (Draft 2020-12).

## Stack
- PostgreSQL 15+
- Python 3.10+ (jsonschema, pandas, faker, matplotlib)
- JSON Schema Draft 2020-12

## Estructura
- **docs/** — Informe técnico, evidencias de validación,
  diccionario de datos y diagrama ER
- **sql/** — Esquema DDL, datos sintéticos, pruebas de
  integridad y consultas operativas/analíticas
- **schema/** — JSON Schema con discriminador if/then/else
- **notebooks/** — Notebook integrador end-to-end
- **scripts/** — Validador del JSON Schema

## Reproducir

```bash
psql -d municipio -f sql/Script_Modelo.sql
psql -d municipio -f sql/Datos_Sinteticos.sql
psql -d municipio -f sql/Pruebas_Integridad.sql
pip install jsonschema faker pandas matplotlib
python scripts/validar_json.py
```

## Características del modelo
- 12 tablas en 4 grupos funcionales (catálogos, recursos,
  negocio, trazabilidad)
- Campo JSONB con discriminador para 6 tipos de solicitud
- 437 puntos de validación automatizada
- Cumple ISO/IEC 25012 en sus 4 dimensiones de calidad

Ver `docs/Informe_Tecnico.pdf` para el detalle completo.
